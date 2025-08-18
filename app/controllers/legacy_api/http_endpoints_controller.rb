# frozen_string_literal: true

module LegacyAPI
  class HTTPEndpointsController < BaseController

    # Returns a list of all HTTP endpoints for the current server
    #
    #   URL:            /api/v1/http_endpoints
    #   Method:         GET
    #
    #   Parameters:     page        => Page number (default: 1)
    #                   per_page    => Items per page (default: 25, max: 100)
    #                   search      => Search by endpoint name or URL
    #                   encoding    => Filter by encoding (BodyAsJSON, FormData)
    #                   format      => Filter by format (Hash, RawMessage)
    #                   sort        => Sort field (name, url, created_at, updated_at)
    #
    #   Response:       A hash containing an array of HTTP endpoint objects with pagination metadata
    #
    def index
      http_endpoints = @current_credential.server.http_endpoints

      # Filtrage simple comme AddressEndpoints
      http_endpoints = http_endpoints.where("name LIKE ?", "%#{params["search"]}%") if params["search"].present?

      total_count = http_endpoints.count

      # Tri
      sort_field = %w[name url created_at updated_at].include?(params["sort"]) ? params["sort"] : "name"
      http_endpoints = http_endpoints.order(sort_field)

      # Pagination
      http_endpoints = http_endpoints.then(&paginate)

      render_success(
        http_endpoints: http_endpoints.map { |endpoint| serialize_http_endpoint(endpoint) },
        meta: pagination_meta(total_count)
      )
    end

    # Returns details about a specific HTTP endpoint
    #
    #   URL:            /api/v1/http_endpoints/:id
    #   Method:         GET
    #
    #   Parameters:     id              => REQ: The UUID of the HTTP endpoint
    #
    #   Response:       A hash containing HTTP endpoint information
    #                   OR an error if the endpoint does not exist.
    #
    def show
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      http_endpoint = @current_credential.server.http_endpoints.find_by(uuid: params[:id])
      if http_endpoint
        render_success(http_endpoint: serialize_http_endpoint(http_endpoint))
      else
        render_error "HTTPEndpointNotFound",
                     message: "No HTTP endpoint found matching provided ID",
                     id: params[:id]
      end
    end

    # Creates a new HTTP endpoint for the current server
    #
    #   URL:            /api/v1/http_endpoints
    #   Method:         POST
    #
    #   Parameters:     name                 => REQ: The endpoint name
    #                   url                  => REQ: The webhook URL
    #                   encoding             => Encoding format (BodyAsJSON, FormData, default: BodyAsJSON)
    #                   format               => Data format (Hash, RawMessage, default: Hash)
    #                   strip_replies        => Strip reply content (default: false)
    #                   include_attachments  => Include attachments (default: true)
    #                   timeout              => Request timeout in seconds (5-60, default: 5)
    #
    #   Response:       A hash containing HTTP endpoint information
    #                   OR an error if validation fails
    #
    def create
      if api_params["name"].blank?
        render_parameter_error "`name` parameter is required but is missing"
        return
      end

      if api_params["url"].blank?
        render_parameter_error "`url` parameter is required but is missing"
        return
      end

      http_endpoint = @current_credential.server.http_endpoints.build(http_endpoint_params)

      if http_endpoint.save
        render_success http_endpoint: serialize_http_endpoint(http_endpoint), message: "HTTP endpoint created successfully"
      else
        render_parameter_error http_endpoint.errors.full_messages.join(", ")
      end
    end

    # Updates an existing HTTP endpoint
    #
    #   URL:            /api/v1/http_endpoints/:id
    #   Method:         PUT/PATCH
    #
    #   Parameters:     id                   => REQ: The UUID of the HTTP endpoint
    #                   name                 => The endpoint name
    #                   url                  => The webhook URL
    #                   encoding             => Encoding format
    #                   format               => Data format
    #                   strip_replies        => Strip reply content
    #                   include_attachments  => Include attachments
    #                   timeout              => Request timeout in seconds
    #
    #   Response:       A hash containing updated HTTP endpoint information
    #                   OR an error if validation fails or endpoint not found
    #
    def update
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      http_endpoint = @current_credential.server.http_endpoints.find_by(uuid: params[:id])
      unless http_endpoint
        render_error "HTTPEndpointNotFound",
                     message: "No HTTP endpoint found matching provided ID",
                     id: params[:id]
        return
      end

      if http_endpoint.update(http_endpoint_params)
        render_success http_endpoint: serialize_http_endpoint(http_endpoint), message: "HTTP endpoint updated successfully"
      else
        render_parameter_error http_endpoint.errors.full_messages.join(", ")
      end
    end

    # Deletes an HTTP endpoint from the current server
    #
    #   URL:            /api/v1/http_endpoints/:id
    #   Method:         DELETE
    #
    #   Parameters:     id              => REQ: The UUID of the HTTP endpoint
    #
    #   Response:       A success message
    #                   OR an error if endpoint not found or cannot be deleted
    #
    def destroy
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      http_endpoint = @current_credential.server.http_endpoints.find_by(uuid: params[:id])
      unless http_endpoint
        render_error "HTTPEndpointNotFound",
                     message: "No HTTP endpoint found matching provided ID",
                     id: params[:id]
        return
      end

      if http_endpoint.destroy
        render_success message: "HTTP endpoint deleted successfully"
      else
        render_error "HTTPEndpointDeletionFailed", message: "Failed to delete HTTP endpoint"
      end
    end

    private

    def http_endpoint_params
      allowed_params = api_params.slice("name", "url", "encoding", "format", "strip_replies", "include_attachments", "timeout")
      
      # Valeurs par défaut (attention aux majuscules pour format et encoding!)
      allowed_params["encoding"] ||= "BodyAsJSON"
      allowed_params["format"] ||= "Hash"
      allowed_params["strip_replies"] = false if allowed_params["strip_replies"].nil?
      allowed_params["include_attachments"] = true if allowed_params["include_attachments"].nil?
      allowed_params["timeout"] ||= 5
      
      # Conversion timeout en integer si présent
      allowed_params["timeout"] = allowed_params["timeout"].to_i if allowed_params["timeout"].present?

      # Conversion des valeurs booléennes
      allowed_params["strip_replies"] = [true, "true", "1", 1].include?(allowed_params["strip_replies"])
      allowed_params["include_attachments"] = [true, "true", "1", 1].include?(allowed_params["include_attachments"])
      
      allowed_params
    end

    def serialize_http_endpoint(http_endpoint)
      {
        id: http_endpoint.uuid,
        name: http_endpoint.name,
        url: http_endpoint.url,
        encoding: http_endpoint.encoding,
        format: http_endpoint.format,
        strip_replies: http_endpoint.strip_replies,
        include_attachments: http_endpoint.include_attachments,
        timeout: http_endpoint.timeout,
        
        # Statut
        error: http_endpoint.error,
        disabled_until: http_endpoint.disabled_until,
        last_used_at: http_endpoint.last_used_at,
        
        # Routes associées (si la relation existe)
        routes_count: http_endpoint.respond_to?(:routes) ? http_endpoint.routes.count : 0,
        
        # Timestamps
        created_at: http_endpoint.created_at,
        updated_at: http_endpoint.updated_at
      }
    end

  end
end