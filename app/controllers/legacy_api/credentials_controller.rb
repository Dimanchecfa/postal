# frozen_string_literal: true

module LegacyAPI
  class CredentialsController < BaseController

    # Returns a list of all credentials for the current server
    #
    #   URL:            /api/v1/credentials
    #   Method:         GET
    #
    #   Parameters:     page        => Page number (default: 1)
    #                   per_page    => Items per page (default: 25)
    #                   type        => Filter by credential type (API, SMTP-IP)
    #                   sort        => Sort field (name, created_at, last_used_at)
    #
    #   Response:       A hash containing an array of credential objects with pagination metadata
    #
    def index
      begin
        credentials = @current_credential.server.credentials

        # Filtrage
        credentials = credentials.where(type: params["type"]) if params["type"].present?
        
        total_count = credentials.count
        
        # Tri
        sort_field = %w[name created_at last_used_at].include?(params["sort"]) ? params["sort"] : "name"
        credentials = credentials.order(sort_field)
        
        # Pagination avec le nouveau module
        credentials = credentials.then(&paginate)

        render_success(
          credentials: credentials.map { |credential| serialize_credential(credential) },
          meta: pagination_meta(total_count)
        )
      rescue => e
        render_error "InternalError", message: "Error: #{e.message}"
      end
    end

    # Returns details about a specific credential
    #
    #   URL:            /api/v1/credentials/:id
    #   Method:         GET
    #
    #   Parameters:     id              => REQ: The UUID of the credential
    #
    #   Response:       A hash containing credential information
    #                   OR an error if the credential does not exist.
    #
    def show
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      credential = @current_credential.server.credentials.find_by(uuid: params[:id])
      if credential
        render_success(credential: serialize_credential(credential))
      else
        render_error "CredentialNotFound",
                     message: "No credential found matching provided ID",
                     id: params[:id]
      end
    end

    # Creates a new credential for the current server
    #
    #   URL:            /api/v1/credentials
    #   Method:         POST
    #
    #   Parameters:     name            => REQ: Credential name
    #                   type            => Credential type (API, SMTP-IP, default: API)
    #                   key             => Credential key (auto-generated for API type)
    #                   hold            => Hold messages flag
    #                   options         => Additional options
    #
    #   Response:       A hash containing credential information
    #                   OR an error if validation fails
    #
    def create
      if credential_params["name"].blank?
        render_parameter_error "`name` parameter is required but is missing"
        return
      end

      credential = @current_credential.server.credentials.build(credential_params)
      if credential.save
        render_success credential: serialize_credential(credential), message: "Credential created successfully"
      else
        render_parameter_error credential.errors.full_messages.join(", ")
      end
    end

    # Updates an existing credential
    #
    #   URL:            /api/v1/credentials/:id
    #   Method:         PUT/PATCH
    #
    #   Parameters:     id              => REQ: The UUID of the credential
    #                   name            => Credential name
    #                   type            => Credential type
    #                   hold            => Hold messages flag
    #                   options         => Additional options
    #
    #   Response:       A hash containing updated credential information
    #                   OR an error if validation fails or credential not found
    #
    def update
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      credential = @current_credential.server.credentials.find_by(uuid: params[:id])
      unless credential
        render_error "CredentialNotFound",
                     message: "No credential found matching provided ID",
                     id: params[:id]
        return
      end

      # Don't allow key modifications for security
      update_params = credential_params.except("key")

      if credential.update(update_params)
        render_success credential: serialize_credential(credential), message: "Credential updated successfully"
      else
        render_parameter_error credential.errors.full_messages.join(", ")
      end
    end

    # Deletes a credential from the current server
    #
    #   URL:            /api/v1/credentials/:id
    #   Method:         DELETE
    #
    #   Parameters:     id              => REQ: The UUID of the credential
    #
    #   Response:       A success message
    #                   OR an error if credential not found or cannot be deleted
    #
    def destroy
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      credential = @current_credential.server.credentials.find_by(uuid: params[:id])
      unless credential
        render_error "CredentialNotFound",
                     message: "No credential found matching provided ID",
                     id: params[:id]
        return
      end

      # Prevent deletion of the current credential being used for API authentication
      if credential == @current_credential
        render_error "CannotDeleteCurrentCredential",
                     message: "Cannot delete the credential currently being used for authentication"
        return
      end

      if credential.destroy
        render_success message: "Credential deleted successfully"
      else
        render_error "CredentialDeletionFailed", message: "Failed to delete credential"
      end
    end

    private

    def credential_params
      allowed_params = api_params.slice("name", "type", "key", "hold", "options")

      # Set default type if not provided
      allowed_params["type"] ||= "API"

      # Validate IP address for SMTP-IP type
      if allowed_params["type"] == "SMTP-IP" && allowed_params["key"].present?
        begin
          IPAddr.new(allowed_params["key"])
        rescue IPAddr::InvalidAddressError
          render_parameter_error("Key must be a valid IP address for SMTP-IP type")
          return {}
        end
      end

      allowed_params
    end

    def serialize_credential(credential)
      {
        id: credential.uuid,
        name: credential.name,
        type: credential.type,
        key: credential.key,
        last_used_at: credential.last_used_at,
        hold: credential.hold,
        created_at: credential.created_at,
        updated_at: credential.updated_at
      }
    end

  end
end