# frozen_string_literal: true

module LegacyAPI
  class SMTPEndpointsController < BaseController

    # Returns a list of all SMTP endpoints for the current server
    #
    #   URL:            /api/v1/smtp_endpoints
    #   Method:         GET
    #
    #   Parameters:     page        => Page number (default: 1)
    #                   per_page    => Items per page (default: 25, max: 100)
    #                   search      => Search by endpoint name or hostname
    #                   hostname    => Filter by hostname
    #                   ssl_mode    => Filter by SSL mode (None, Auto, STARTTLS, TLS)
    #                   sort        => Sort field (name, hostname, created_at, updated_at)
    #
    #   Response:       A hash containing an array of SMTP endpoint objects with pagination metadata
    #
    def index
      smtp_endpoints = @current_credential.server.smtp_endpoints

      # Filtrage
      if params["search"].present?
        search_term = "%#{params["search"]}%"
        smtp_endpoints = smtp_endpoints.where("name LIKE ? OR hostname LIKE ?", search_term, search_term)
      end
      smtp_endpoints = smtp_endpoints.where(hostname: params["hostname"]) if params["hostname"].present?
      smtp_endpoints = smtp_endpoints.where(ssl_mode: params["ssl_mode"]) if params["ssl_mode"].present?

      total_count = smtp_endpoints.count

      # Tri
      sort_field = %w[name hostname created_at updated_at].include?(params["sort"]) ? params["sort"] : "name"
      smtp_endpoints = smtp_endpoints.order(sort_field)

      # Pagination
      smtp_endpoints = smtp_endpoints.then(&paginate)

      render_success(
        smtp_endpoints: smtp_endpoints.map { |endpoint| serialize_smtp_endpoint(endpoint) },
        meta: pagination_meta(total_count)
      )
    end

    # Returns details about a specific SMTP endpoint
    #
    #   URL:            /api/v1/smtp_endpoints/:id
    #   Method:         GET
    #
    #   Parameters:     id              => REQ: The UUID of the SMTP endpoint
    #
    #   Response:       A hash containing SMTP endpoint information
    #                   OR an error if the endpoint does not exist.
    #
    def show
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      smtp_endpoint = @current_credential.server.smtp_endpoints.find_by(uuid: params[:id])
      if smtp_endpoint
        render_success(smtp_endpoint: serialize_smtp_endpoint(smtp_endpoint))
      else
        render_error "SMTPEndpointNotFound",
                     message: "No SMTP endpoint found matching provided ID",
                     id: params[:id]
      end
    end

    # Creates a new SMTP endpoint for the current server
    #
    #   URL:            /api/v1/smtp_endpoints
    #   Method:         POST
    #
    #   Parameters:     name                 => REQ: The endpoint name
    #                   hostname             => REQ: The SMTP server hostname
    #                   port                 => SMTP port (default: 25)
    #                   ssl_mode             => SSL mode (None, Auto, STARTTLS, TLS, default: Auto)
    #
    #   Response:       A hash containing SMTP endpoint information
    #                   OR an error if validation fails
    #
    def create
      if api_params["name"].blank?
        render_parameter_error "`name` parameter is required but is missing"
        return
      end

      if api_params["hostname"].blank?
        render_parameter_error "`hostname` parameter is required but is missing"
        return
      end

      smtp_endpoint = @current_credential.server.smtp_endpoints.build(smtp_endpoint_params)

      if smtp_endpoint.save
        render_success smtp_endpoint: serialize_smtp_endpoint(smtp_endpoint), message: "SMTP endpoint created successfully"
      else
        render_parameter_error smtp_endpoint.errors.full_messages.join(", ")
      end
    end

    # Updates an existing SMTP endpoint
    #
    #   URL:            /api/v1/smtp_endpoints/:id
    #   Method:         PUT/PATCH
    #
    #   Parameters:     id                   => REQ: The UUID of the SMTP endpoint
    #                   name                 => The endpoint name
    #                   hostname             => The SMTP server hostname
    #                   port                 => SMTP port
    #                   ssl_mode             => SSL mode
    #
    #   Response:       A hash containing updated SMTP endpoint information
    #                   OR an error if validation fails or endpoint not found
    #
    def update
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      smtp_endpoint = @current_credential.server.smtp_endpoints.find_by(uuid: params[:id])
      unless smtp_endpoint
        render_error "SMTPEndpointNotFound",
                     message: "No SMTP endpoint found matching provided ID",
                     id: params[:id]
        return
      end

      if smtp_endpoint.update(smtp_endpoint_params)
        render_success smtp_endpoint: serialize_smtp_endpoint(smtp_endpoint), message: "SMTP endpoint updated successfully"
      else
        render_parameter_error smtp_endpoint.errors.full_messages.join(", ")
      end
    end

    # Deletes an SMTP endpoint from the current server
    #
    #   URL:            /api/v1/smtp_endpoints/:id
    #   Method:         DELETE
    #
    #   Parameters:     id              => REQ: The UUID of the SMTP endpoint
    #
    #   Response:       A success message
    #                   OR an error if endpoint not found or cannot be deleted
    #
    def destroy
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      smtp_endpoint = @current_credential.server.smtp_endpoints.find_by(uuid: params[:id])
      unless smtp_endpoint
        render_error "SMTPEndpointNotFound",
                     message: "No SMTP endpoint found matching provided ID",
                     id: params[:id]
        return
      end

      if smtp_endpoint.destroy
        render_success message: "SMTP endpoint deleted successfully"
      else
        render_error "SMTPEndpointDeletionFailed", message: "Failed to delete SMTP endpoint"
      end
    end

    private

    def smtp_endpoint_params
      allowed_params = api_params.slice("name", "hostname", "port", "ssl_mode")
      
      # Valeurs par défaut
      allowed_params["ssl_mode"] ||= "Auto"
      allowed_params["port"] = allowed_params["port"].to_i if allowed_params["port"].present?
      
      allowed_params
    end

    def serialize_smtp_endpoint(smtp_endpoint)
      {
        id: smtp_endpoint.uuid,
        name: smtp_endpoint.name,
        hostname: smtp_endpoint.hostname,
        port: smtp_endpoint.port,
        ssl_mode: smtp_endpoint.ssl_mode,
        
        # Statut
        error: smtp_endpoint.error,
        disabled_until: smtp_endpoint.disabled_until,
        last_used_at: smtp_endpoint.last_used_at,
        
        # Routes associées (si la relation existe)
        routes_count: smtp_endpoint.respond_to?(:routes) ? smtp_endpoint.routes.count : 0,
        
        # Timestamps
        created_at: smtp_endpoint.created_at,
        updated_at: smtp_endpoint.updated_at
      }
    end

  end
end