# frozen_string_literal: true

module LegacyAPI
  class UsersController < BaseController

    # Returns a list of all users for the current organization
    #
    #   URL:            /api/v1/users
    #   Method:         GET
    #
    #   Parameters:     page        => Page number (default: 1)
    #                   per_page    => Items per page (default: 25)
    #                   search      => Search by email or name
    #                   admin       => Filter by admin status (true/false)
    #                   sort        => Sort field (email_address, created_at, last_name)
    #
    #   Response:       A hash containing an array of user objects with pagination metadata
    #
    def index
      users = @current_credential.server.organization.users
      
      # Filtrage
      if params["search"].present?
        search_term = "%#{params["search"]}%"
        users = users.where("email_address LIKE ? OR first_name LIKE ? OR last_name LIKE ?", 
                            search_term, search_term, search_term)
      end
      
      if params["admin"].present?
        org_users = @current_credential.server.organization.organization_users
        if params["admin"] == "true"
          org_users = org_users.where(admin: true)
        else
          org_users = org_users.where(admin: false)
        end
        users = users.joins(:organization_users).merge(org_users)
      end
      
      total_count = users.count
      
      # Tri
      sort_field = %w[email_address created_at last_name].include?(params["sort"]) ? params["sort"] : "email_address"
      users = users.order(sort_field)
      
      # Pagination avec le nouveau module
      users = users.then(&paginate)

      render_success(
        users: users.map { |user| serialize_user(user) },
        meta: pagination_meta(total_count)
      )
    end

    # Returns details about a specific user
    #
    #   URL:            /api/v1/users/:id
    #   Method:         GET
    #
    #   Parameters:     id              => REQ: The UUID of the user
    #
    #   Response:       A hash containing user information
    #                   OR an error if the user does not exist.
    #
    def show
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      user = @current_credential.server.organization.users.find_by(uuid: params[:id])
      if user
        render_success(user: serialize_user(user))
      else
        render_error "UserNotFound",
                     message: "No user found matching provided ID",
                     id: params[:id]
      end
  end

    # Creates a new user or adds an existing user to the organization
    #
    #   URL:            /api/v1/users
    #   Method:         POST
    #
    #   Parameters:     first_name      => REQ: User's first name
    #                   last_name       => REQ: User's last name
    #                   email_address   => REQ: User's email address
    #                   password        => Password (auto-generated if not provided)
    #                   admin           => Admin privileges (default: false)
    #                   time_zone       => User's timezone
    #
    #   Response:       A hash containing user information
    #                   OR an error if validation fails
    #
    def create
      if user_params["email_address"].blank?
        render_parameter_error "`email_address` parameter is required but is missing"
        return
      end

      if user_params["first_name"].blank?
        render_parameter_error "`first_name` parameter is required but is missing"
        return
      end

      if user_params["last_name"].blank?
        render_parameter_error "`last_name` parameter is required but is missing"
        return
      end

      # Check if user already exists
      existing_user = User.find_by(email_address: user_params["email_address"])

      if existing_user
        # Add existing user to organization if not already a member
        unless @current_credential.server.organization.users.include?(existing_user)
          @current_credential.server.organization.organization_users.create!(
            user: existing_user,
            admin: user_params["admin"] || false
          )
        end
        render_success(user: serialize_user(existing_user), message: "User added to organization")
      else
        # Create new user
        user = User.new(user_params)
        user.password = user_params["password"] || SecureRandom.alphanumeric(12)
        user.email_verified_at = Time.current # Auto-verify for API created users

        if user.save
          @current_credential.server.organization.organization_users.create!(
            user: user,
            admin: user_params["admin"] || false
          )
          render_success(user: serialize_user(user), message: "User created successfully")
        else
          render_parameter_error(user.errors.full_messages.join(", "))
        end
      end
    end

    # Updates an existing user
    #
    #   URL:            /api/v1/users/:id
    #   Method:         PUT/PATCH
    #
    #   Parameters:     id              => REQ: The UUID of the user
    #                   first_name      => User's first name
    #                   last_name       => User's last name
    #                   password        => New password
    #                   admin           => Admin privileges
    #                   time_zone       => User's timezone
    #
    #   Response:       A hash containing updated user information
    #                   OR an error if validation fails or user not found
    #
    def update
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      @user = @current_credential.server.organization.users.find_by(uuid: params[:id])
      unless @user
        render_error "UserNotFound",
                     message: "No user found matching provided ID",
                     id: params[:id]
        return
      end

    update_params = user_params.except("email_address") # Don't allow email changes
    update_params.delete("password") if update_params["password"].blank?

    if @user.update(update_params)
      # Update organization admin status if specified
      if user_params.key?("admin")
        org_user = @current_credential.server.organization.organization_users.find_by(user: @user)
        org_user&.update(admin: user_params["admin"])
      end

      render_success(user: serialize_user(@user), message: "User updated successfully")
    else
      render_parameter_error(@user.errors.full_messages.join(", "))
    end
  end

    # Removes a user from the organization or deletes them entirely
    #
    #   URL:            /api/v1/users/:id
    #   Method:         DELETE
    #
    #   Parameters:     id              => REQ: The UUID of the user
    #
    #   Response:       A success message
    #                   OR an error if user not found or cannot be deleted
    #
    def destroy
      if params[:id].blank?
        render_parameter_error "`id` parameter is required but is missing"
        return
      end

      @user = @current_credential.server.organization.users.find_by(uuid: params[:id])
      unless @user
        render_error "UserNotFound",
                     message: "No user found matching provided ID",
                     id: params[:id]
        return
      end

      # Prevent deletion of organization owner
      if @user == @current_credential.server.organization.owner
        render_error "CannotDeleteOwner",
                     message: "Cannot delete the organization owner"
        return
      end

      # Remove user from organization
      @current_credential.server.organization.organization_users.where(user: @user).destroy_all

      # Delete user entirely if they're not in any other organizations
      if @user.organizations.empty?
        @user.destroy
      end

      render_success message: "User removed successfully"
  end

    private

    def user_params
    allowed_params = api_params.slice("first_name", "last_name", "email_address", "password", "admin", "time_zone")
    allowed_params
  end

    def serialize_user(user)
      org_user = @current_credential.server.organization.organization_users.find_by(user: user)
      organization = @current_credential.server.organization
      
      # Récupérer les serveurs accessibles pour cet utilisateur
      servers = if org_user&.admin?
                  organization.servers
                else
                  # Pour un utilisateur non-admin, montrer seulement les serveurs où il a des permissions
                  organization.servers.joins(:credentials).where(credentials: { id: @current_credential.id }).distinct
                end
      
      {
        id: user.uuid,
        first_name: user.first_name,
        last_name: user.last_name,
        email_address: user.email_address,
        full_name: "#{user.first_name} #{user.last_name}".strip,
        
        # Statut et permissions
        admin: org_user&.admin || false,
        owner: user == organization.owner,
        
        # Configuration
        time_zone: user.time_zone || "UTC",
        email_verified_at: user.email_verified_at,
        email_verified: user.email_verified_at.present?,
        
        # Serveurs accessibles
        servers: servers.map { |s| 
          {
            id: s.uuid,
            name: s.name,
            permalink: s.permalink,
            mode: s.mode,
            message_retention_days: s.message_retention_days
          }
        },
        
        # Activité
        activity: {
          created_days_ago: ((Time.now - user.created_at) / 86400).floor
        },
        
        # Organisation
        organization: {
          id: organization.uuid,
          name: organization.name,
          permalink: organization.permalink
        },
        
        # Timestamps
        created_at: user.created_at,
        updated_at: user.updated_at
      }
    end

  end
end