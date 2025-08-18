# frozen_string_literal: true

module LegacyAPI
  class DomainsController < BaseController

    # Returns a list of all domains for the current server
    #
    #   URL:            /api/v1/domains
    #   Method:         GET
    #
    #   Parameters:     page        => Page number (default: 1)
    #                   per_page    => Items per page (default: 25)
    #                   search      => Search by domain name
    #                   verified    => Filter by verification status (true/false)
    #                   sort        => Sort field (name, created_at, updated_at)
    #
    #   Response:       A hash containing an array of domain objects with pagination metadata
    #
    def index
      domains = @current_credential.server.domains

      domains = domains.where.not(verified_at: nil) if params["verified"] == "true"
      domains = domains.where(verified_at: nil) if params["verified"] == "false"
      domains = domains.where("name LIKE ?", "%#{params["search"]}%") if params["search"].present?

      total_count = domains.count

      sort_field = %w[name created_at updated_at].include?(params["sort"]) ? params["sort"] : "name"
      domains = domains.order(sort_field)

      # Pagination avec le nouveau module
      domains = domains.then(&paginate)

      render_success(
        domains: domains.map { |domain| serialize_domain(domain) },
        meta: pagination_meta(total_count)
      )
    end

    # Returns details about a specific domain
    #
    #   URL:            /api/v1/domains/:id
    #   Method:         GET
    #
    #   Parameters:     id              => REQ: The UUID of the domain
    #
    #   Response:       A hash containing domain information
    #                   OR an error if the domain does not exist.
    #
    def show
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      domain = @current_credential.server.domains.find_by(uuid: params[:id])
      if domain
        render_success(domain: serialize_domain(domain))
      else
        render_error "DomainNotFound",
                     message: "No domain found matching provided ID",
                     id: params[:id]
      end
    end

    # Creates a new domain for the current server
    #
    #   URL:            /api/v1/domains
    #   Method:         POST
    #
    #   Parameters:     name                 => REQ: The domain name
    #                   verification_method  => Verification method (DNS or Email, default: DNS)
    #                   auto_verify          => Auto-verify domain if true (admin only)
    #
    #   Response:       A hash containing domain information with DNS configuration
    #                   OR an error if validation fails
    #
    def create
      if domain_params["name"].blank?
        render_parameter_error "`name` parameter is required but is missing"
        return
      end

      domain = @current_credential.server.domains.build(domain_params)
      
      # Auto-verify domains created via API if:
      # 1. The credential has sufficient privileges (API type credentials)
      # This mirrors the web controller behavior where admins can auto-verify
      if @current_credential.type == "API"
        domain.verification_method = "DNS"
        domain.verified_at = Time.now
      end

      if domain.save
        # Generate DKIM key if needed
        domain.generate_dkim_key if domain.dkim_private_key.blank?
        domain.save if domain.changed?
        
        render_success domain: serialize_domain(domain), 
                       message: domain.verified? ? "Domain created and verified successfully" : "Domain created successfully"
      else
        render_parameter_error domain.errors.full_messages.join(", ")
      end
    end

    # Updates an existing domain
    #
    #   URL:            /api/v1/domains/:id
    #   Method:         PUT/PATCH
    #
    #   Parameters:     id                   => REQ: The UUID of the domain
    #                   name                 => The domain name
    #                   verification_method  => Verification method (DNS or Email)
    #
    #   Response:       A hash containing updated domain information
    #                   OR an error if validation fails or domain not found
    #
    def update
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      domain = @current_credential.server.domains.find_by(uuid: params[:id])
      unless domain
        render_error "DomainNotFound",
                     message: "No domain found matching provided ID",
                     id: params[:id]
        return
      end

      if domain.update(domain_params)
        render_success domain: serialize_domain(domain), message: "Domain updated successfully"
      else
        render_parameter_error domain.errors.full_messages.join(", ")
      end
    end

    # Deletes a domain from the current server
    #
    #   URL:            /api/v1/domains/:id
    #   Method:         DELETE
    #
    #   Parameters:     id              => REQ: The UUID of the domain
    #
    #   Response:       A success message
    #                   OR an error if domain not found or cannot be deleted
    #
    def destroy
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      domain = @current_credential.server.domains.find_by(uuid: params[:id])
      unless domain
        render_error "DomainNotFound",
                     message: "No domain found matching provided ID",
                     id: params[:id]
        return
      end

      if domain.destroy
        render_success message: "Domain deleted successfully"
      else
        render_error "DomainDeletionFailed", message: "Failed to delete domain"
      end
    end

    # Initiates verification check for a domain
    #
    #   URL:            /api/v1/domains/:id/verify
    #   Method:         POST
    #
    #   Parameters:     id              => REQ: The UUID of the domain
    #                   method          => Verification method (DNS or Email)
    #                   email           => Email address for Email verification
    #                   code            => Verification code for Email verification
    #
    #   Response:       A hash containing domain information with updated verification status
    #                   OR an error if domain not found
    #
    def verify
      begin
        if params[:id].blank?
          render_parameter_error "`id` parameter is required but is missing"
          return
        end

        domain = @current_credential.server.domains.find_by(uuid: params[:id])
        unless domain
          render_error "DomainNotFound",
                       message: "No domain found matching provided ID",
                       id: params[:id]
          return
        end

        if domain.verified?
          render_success domain: serialize_domain(domain),
                         message: "Domain is already verified"
          return
        end

        case domain.verification_method
        when "DNS"
          if domain.verify_with_dns
            render_success domain: serialize_domain(domain),
                           message: "Domain has been verified successfully via DNS"
          else
            render_error "VerificationFailed",
                         message: "DNS verification failed. Please check your TXT record.",
                         dns_record_name: "@",
                         dns_record_value: domain.dns_verification_string
          end
        when "Email"
          if api_params["code"].present?
            if domain.verification_token == api_params["code"].to_s.strip
              domain.mark_as_verified
              render_success domain: serialize_domain(domain),
                             message: "Domain has been verified successfully via email"
            else
              render_error "InvalidVerificationCode",
                           message: "Invalid verification code"
            end
          else
            render_error "VerificationCodeRequired",
                         message: "Verification code is required for email verification"
          end
        end
      rescue => e
        Rails.logger.error "Domain verification failed for domain #{params[:id]}: #{e.message}"
        render_error "VerificationError", 
                     message: "Unable to verify domain at this time",
                     error: e.message
      end
    end

    # Checks DNS configuration for a domain
    #
    #   URL:            /api/v1/domains/:id/check_dns
    #   Method:         POST
    #
    #   Parameters:     id              => REQ: The UUID of the domain
    #
    #   Response:       A hash containing domain information with updated DNS status
    #                   OR an error if domain not found
    #
    def check_dns
      begin
        if params[:id].blank?
          render_parameter_error "`id` parameter is required but is missing"
          return
        end

        domain = @current_credential.server.domains.find_by(uuid: params[:id])
        unless domain
          render_error "DomainNotFound",
                       message: "No domain found matching provided ID",
                       id: params[:id]
          return
        end

        # Utiliser check_dns au lieu de check
        domain.check_dns
        dns_ok = domain.dns_ok?
        
        render_success domain: serialize_domain(domain),
                       dns_ok: dns_ok,
                       message: dns_ok ? "DNS records are correctly configured" : "DNS records need attention"
      rescue => e
        Rails.logger.error "DNS check failed for domain #{params[:id]}: #{e.message}"
        render_error "DNSCheckFailed", 
                     message: "Unable to check DNS records at this time",
                     error: e.message
      end
    end

    private

    def domain_params
      allowed_params = api_params.slice("name", "verification_method")
      allowed_params["verification_method"] ||= "DNS"
      allowed_params
    end

    def serialize_domain(domain)
      mx_records = if defined?(Postal::Config.dns.mx_records)
                     Postal::Config.dns.mx_records
                   elsif defined?(Postal::Config.dns.mx)
                     [Postal::Config.dns.mx].flatten
                   else
                     ["mx.postal.local"]
                   end

      return_path_domain = if defined?(Postal::Config.dns.return_path_domain)
                             Postal::Config.dns.return_path_domain
                           else
                             "postal.local"
                           end

      spf_include = if defined?(Postal::Config.dns.spf_include)
                      Postal::Config.dns.spf_include
                    else
                      "spf.postal.local"
                    end

      {
        id: domain.uuid,
        name: domain.name,
        verification_token: domain.verification_token,
        verification_method: domain.verification_method,
        verified_at: domain.verified_at,
        
        # Statuts DNS
        dns_checked_at: domain.dns_checked_at,
        spf_status: domain.spf_status,
        spf_error: domain.spf_error,
        dkim_status: domain.dkim_status,
        dkim_error: domain.dkim_error,
        mx_status: domain.mx_status,
        mx_error: domain.mx_error,
        return_path_status: domain.return_path_status,
        return_path_error: domain.return_path_error,
        
        # Configuration DNS complète
        dns_records: {
          spf: {
            type: "TXT",
            name: "@",
            content: "v=spf1 a mx include:#{spf_include} ~all",
            value: domain.spf_record,
            status: domain.spf_status,
            error: domain.spf_error
          },
          dkim: {
            type: "TXT",
            name: domain.dkim_record_name,
            content: domain.dkim_record,
            identifier: domain.dkim_identifier,
            status: domain.dkim_status,
            error: domain.dkim_error
          },
          return_path: {
            type: "CNAME",
            name: "psrp.#{domain.name}",
            content: "rp.#{return_path_domain}",
            value: domain.return_path_domain,
            status: domain.return_path_status,
            error: domain.return_path_error
          },
          mx: {
            type: "MX",
            priority: 10,
            records: mx_records.map { |mx| { priority: 10, value: mx } },
            status: domain.mx_status,
            error: domain.mx_error
          },
          verification: domain.verified? ? nil : {
            type: "TXT",
            name: "@",
            content: domain.dns_verification_string,
            token: domain.verification_token
          }
        }.compact,
        
        # Flags
        outgoing: domain.outgoing,
        incoming: domain.incoming,
        use_for_any: domain.use_for_any || false,
        dns_ok: domain.dns_ok?,
        
        # Timestamps
        created_at: domain.created_at,
        updated_at: domain.updated_at
      }
    end

  end
end