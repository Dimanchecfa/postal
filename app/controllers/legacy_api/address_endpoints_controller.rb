# frozen_string_literal: true

module LegacyAPI
  class AddressEndpointsController < BaseController

    # Returns a list of all address endpoints for the current server
    #
    #   URL:            /api/v1/address_endpoints
    #   Method:         GET
    #
    #   Parameters:     page        => Page number (default: 1)
    #                   per_page    => Items per page (default: 25, max: 100)
    #                   search      => Search by address
    #                   domain      => Filter by domain part of address
    #                   sort        => Sort field (address, created_at, updated_at)
    #
    #   Response:       A hash containing an array of address endpoint objects with pagination metadata
    #
    def index
      address_endpoints = @current_credential.server.address_endpoints

      # Filtrage
      address_endpoints = address_endpoints.where("address LIKE ?", "%#{params["search"]}%") if params["search"].present?
      address_endpoints = address_endpoints.where("address = ?", params["address"]) if params["address"].present?

      total_count = address_endpoints.count

      # Tri
      sort_field = %w[address created_at updated_at].include?(params["sort"]) ? params["sort"] : "address"
      address_endpoints = address_endpoints.order(sort_field)

      # Pagination
      address_endpoints = address_endpoints.then(&paginate)

      render_success(
        address_endpoints: address_endpoints.map { |endpoint| serialize_address_endpoint(endpoint) },
        meta: pagination_meta(total_count)
      )
    end

    # Returns details about a specific address endpoint
    #
    #   URL:            /api/v1/address_endpoints/:id
    #   Method:         GET
    #
    #   Parameters:     id              => REQ: The UUID of the address endpoint
    #
    #   Response:       A hash containing address endpoint information
    #                   OR an error if the endpoint does not exist.
    #
    def show
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      address_endpoint = @current_credential.server.address_endpoints.find_by(uuid: params[:id])
      if address_endpoint
        render_success(address_endpoint: serialize_address_endpoint(address_endpoint))
      else
        render_error "AddressEndpointNotFound",
                     message: "No address endpoint found matching provided ID",
                     id: params[:id]
      end
    end

    # Creates a new address endpoint for the current server
    #
    #   URL:            /api/v1/address_endpoints
    #   Method:         POST
    #
    #   Parameters:     address              => REQ: The target email address
    #
    #   Response:       A hash containing address endpoint information
    #                   OR an error if validation fails
    #
    def create
      if api_params["address"].blank?
        render_parameter_error "`address` parameter is required but is missing"
        return
      end

      address_endpoint = @current_credential.server.address_endpoints.build(address_endpoint_params)

      if address_endpoint.save
        render_success address_endpoint: serialize_address_endpoint(address_endpoint), message: "Address endpoint created successfully"
      else
        render_parameter_error address_endpoint.errors.full_messages.join(", ")
      end
    end

    # Updates an existing address endpoint
    #
    #   URL:            /api/v1/address_endpoints/:id
    #   Method:         PUT/PATCH
    #
    #   Parameters:     id                   => REQ: The UUID of the address endpoint
    #                   address              => The target email address
    #
    #   Response:       A hash containing updated address endpoint information
    #                   OR an error if validation fails or endpoint not found
    #
    def update
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      address_endpoint = @current_credential.server.address_endpoints.find_by(uuid: params[:id])
      unless address_endpoint
        render_error "AddressEndpointNotFound",
                     message: "No address endpoint found matching provided ID",
                     id: params[:id]
        return
      end

      if address_endpoint.update(address_endpoint_params)
        render_success address_endpoint: serialize_address_endpoint(address_endpoint), message: "Address endpoint updated successfully"
      else
        render_parameter_error address_endpoint.errors.full_messages.join(", ")
      end
    end

    # Deletes an address endpoint from the current server
    #
    #   URL:            /api/v1/address_endpoints/:id
    #   Method:         DELETE
    #
    #   Parameters:     id              => REQ: The UUID of the address endpoint
    #
    #   Response:       A success message
    #                   OR an error if endpoint not found or cannot be deleted
    #
    def destroy
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      address_endpoint = @current_credential.server.address_endpoints.find_by(uuid: params[:id])
      unless address_endpoint
        render_error "AddressEndpointNotFound",
                     message: "No address endpoint found matching provided ID",
                     id: params[:id]
        return
      end

      if address_endpoint.destroy
        render_success message: "Address endpoint deleted successfully"
      else
        render_error "AddressEndpointDeletionFailed", message: "Failed to delete address endpoint"
      end
    end

    private

    def address_endpoint_params
      api_params.slice("address")
    end

    def serialize_address_endpoint(address_endpoint)
      {
        id: address_endpoint.uuid,
        address: address_endpoint.address,
        
        # Statut
        last_used_at: address_endpoint.last_used_at,
        
        # Routes associées (si la relation existe)
        routes_count: address_endpoint.respond_to?(:routes) ? address_endpoint.routes.count : 0,
        
        # Timestamps
        created_at: address_endpoint.created_at,
        updated_at: address_endpoint.updated_at
      }
    end

  end
end