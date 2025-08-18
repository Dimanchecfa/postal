# frozen_string_literal: true

module LegacyAPI
  class RoutesController < BaseController

    # Returns a list of all routes for the current server
    #
    #   URL:            /api/v1/routes
    #   Method:         GET
    #
    #   Parameters:     page        => Page number (default: 1)
    #                   per_page    => Items per page (default: 25, max: 100)
    #                   search      => Search by route name
    #                   domain      => Filter by domain name
    #                   mode        => Filter by route mode (Endpoint, Accept, Hold, Bounce, Reject)
    #                   sort        => Sort field (name, created_at, updated_at)
    #
    #   Response:       A hash containing an array of route objects with pagination metadata
    #
    def index
      routes = @current_credential.server.routes.includes(:domain, :endpoint)

      # Filtrage
      routes = routes.joins(:domain).where(domains: { name: params["domain"] }) if params["domain"].present?
      routes = routes.where("name LIKE ?", "%#{params["search"]}%") if params["search"].present?
      routes = routes.where(mode: params["mode"]) if params["mode"].present?

      total_count = routes.count

      # Tri
      sort_field = %w[name created_at updated_at].include?(params["sort"]) ? params["sort"] : "name"
      routes = routes.order(sort_field)

      # Pagination avec le nouveau module
      routes = routes.then(&paginate)

      render_success(
        routes: routes.map { |route| serialize_route(route) },
        meta: pagination_meta(total_count)
      )
    end

    # Returns details about a specific route
    #
    #   URL:            /api/v1/routes/:id
    #   Method:         GET
    #
    #   Parameters:     id              => REQ: The UUID of the route
    #
    #   Response:       A hash containing route information
    #                   OR an error if the route does not exist.
    #
    def show
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      route = @current_credential.server.routes.includes(:domain, :endpoint).find_by(uuid: params[:id])
      if route
        render_success(route: serialize_route(route))
      else
        render_error "RouteNotFound",
                     message: "No route found matching provided ID",
                     id: params[:id]
      end
    end

    # Creates a new route for the current server
    #
    #   URL:            /api/v1/routes
    #   Method:         POST
    #
    #   Parameters:     name                 => REQ: The route name (pattern)
    #                   domain_id            => REQ: The domain UUID (unless return path)
    #                   mode                 => Route mode (default: Endpoint)
    #                   spam_mode           => Spam handling (Mark, Quarantine, Fail)
    #                   endpoint_id         => Endpoint UUID if mode is Endpoint
    #                   endpoint_type       => Endpoint type (HTTPEndpoint, SMTPEndpoint, AddressEndpoint)
    #
    #   Response:       A hash containing route information
    #                   OR an error if validation fails
    #
    def create
      if api_params["name"].blank?
        render_parameter_error "`name` parameter is required but is missing"
        return
      end

      route = @current_credential.server.routes.build(route_params)

      if route.save
        render_success route: serialize_route(route), message: "Route created successfully"
      else
        render_parameter_error route.errors.full_messages.join(", ")
      end
    end

    # Updates an existing route
    #
    #   URL:            /api/v1/routes/:id
    #   Method:         PUT/PATCH
    #
    #   Parameters:     id                   => REQ: The UUID of the route
    #                   name                 => The route name
    #                   domain_id            => The domain UUID
    #                   mode                 => Route mode
    #                   spam_mode           => Spam handling
    #                   endpoint_id         => Endpoint UUID
    #                   endpoint_type       => Endpoint type
    #
    #   Response:       A hash containing updated route information
    #                   OR an error if validation fails or route not found
    #
    def update
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      route = @current_credential.server.routes.find_by(uuid: params[:id])
      unless route
        render_error "RouteNotFound",
                     message: "No route found matching provided ID",
                     id: params[:id]
        return
      end

      if route.update(route_params)
        render_success route: serialize_route(route), message: "Route updated successfully"
      else
        render_parameter_error route.errors.full_messages.join(", ")
      end
    end

    # Deletes a route from the current server
    #
    #   URL:            /api/v1/routes/:id
    #   Method:         DELETE
    #
    #   Parameters:     id              => REQ: The UUID of the route
    #
    #   Response:       A success message
    #                   OR an error if route not found or cannot be deleted
    #
    def destroy
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      route = @current_credential.server.routes.find_by(uuid: params[:id])
      unless route
        render_error "RouteNotFound",
                     message: "No route found matching provided ID",
                     id: params[:id]
        return
      end

      if route.destroy
        render_success message: "Route deleted successfully"
      else
        render_error "RouteDeletionFailed", message: "Failed to delete route"
      end
    end

    private

    def route_params
      allowed_params = api_params.slice("name", "domain_id", "spam_mode", "mode", "endpoint_id", "endpoint_type")
      
      # Conversion domain_id si UUID fourni
      if allowed_params["domain_id"].present?
        domain = @current_credential.server.domains.find_by(uuid: allowed_params["domain_id"])
        if domain
          allowed_params["domain_id"] = domain.id
        else
          allowed_params.delete("domain_id")
        end
      end

      # Gestion de l'endpoint
      if allowed_params["endpoint_id"].present? && allowed_params["endpoint_type"].present?
        endpoint_class = allowed_params["endpoint_type"].constantize
        endpoint = @current_credential.server.public_send(endpoint_class.name.underscore.pluralize).find_by(uuid: allowed_params["endpoint_id"])
        if endpoint
          allowed_params["_endpoint"] = "#{endpoint_class.name}##{endpoint.uuid}"
        end
        allowed_params.delete("endpoint_id")
        allowed_params.delete("endpoint_type")
      end

      # Valeurs par défaut
      allowed_params["spam_mode"] ||= "Mark"
      allowed_params["mode"] ||= "Endpoint"

      allowed_params
    end

    def serialize_route(route)
      {
        id: route.uuid,
        name: route.name,
        description: route.description,
        mode: route.mode,
        spam_mode: route.spam_mode,
        token: route.token,
        
        # Domaine associé
        domain: route.domain ? {
          id: route.domain.uuid,
          name: route.domain.name,
          verified: route.domain.verified?
        } : nil,
        
        # Endpoint associé
        endpoint: route.endpoint ? {
          id: route.endpoint.uuid,
          type: route.endpoint_type,
          name: route.endpoint.respond_to?(:name) ? route.endpoint.name : nil,
          description: route.endpoint.description
        } : nil,
        
        # Métadonnées
        wildcard: route.wildcard?,
        return_path: route.return_path?,
        forward_address: route.forward_address,
        
        # Timestamps
        created_at: route.created_at,
        updated_at: route.updated_at
      }
    end

  end
end