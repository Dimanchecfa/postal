# frozen_string_literal: true

Rails.application.routes.draw do
  # Legacy API Routes
  match "/api/v1/send/message" => "legacy_api/send#message", via: [:get, :post, :patch, :put]
  match "/api/v1/send/raw" => "legacy_api/send#raw", via: [:get, :post, :patch, :put]
  match "/api/v1/messages/message" => "legacy_api/messages#message", via: [:get, :post, :patch, :put]
  match "/api/v1/messages/deliveries" => "legacy_api/messages#deliveries", via: [:get, :post, :patch, :put]

  # New API v1 Resource Management Routes
  # Domains
  match "/api/v1/domains" => "legacy_api/domains#index", via: [:get]
  match "/api/v1/domains" => "legacy_api/domains#create", via: [:post]
  match "/api/v1/domains/:id" => "legacy_api/domains#show", via: [:get]
  match "/api/v1/domains/:id" => "legacy_api/domains#update", via: [:put, :patch]
  match "/api/v1/domains/:id" => "legacy_api/domains#destroy", via: [:delete]
  match "/api/v1/domains/:id/verify" => "legacy_api/domains#verify", via: [:post]
  match "/api/v1/domains/:id/check_dns" => "legacy_api/domains#check_dns", via: [:post]

  # Credentials (API Keys)
  match "/api/v1/credentials" => "legacy_api/credentials#index", via: [:get]
  match "/api/v1/credentials" => "legacy_api/credentials#create", via: [:post]
  match "/api/v1/credentials/:id" => "legacy_api/credentials#show", via: [:get]
  match "/api/v1/credentials/:id" => "legacy_api/credentials#update", via: [:put, :patch]
  match "/api/v1/credentials/:id" => "legacy_api/credentials#destroy", via: [:delete]

  # Users
  match "/api/v1/users" => "legacy_api/users#index", via: [:get]
  match "/api/v1/users" => "legacy_api/users#create", via: [:post]
  match "/api/v1/users/:id" => "legacy_api/users#show", via: [:get]
  match "/api/v1/users/:id" => "legacy_api/users#update", via: [:put, :patch]
  match "/api/v1/users/:id" => "legacy_api/users#destroy", via: [:delete]

  # Routes
  match "/api/v1/routes" => "legacy_api/routes#index", via: [:get]
  match "/api/v1/routes" => "legacy_api/routes#create", via: [:post]
  match "/api/v1/routes/:id" => "legacy_api/routes#show", via: [:get]
  match "/api/v1/routes/:id" => "legacy_api/routes#update", via: [:put, :patch]
  match "/api/v1/routes/:id" => "legacy_api/routes#destroy", via: [:delete]

  # HTTP Endpoints
  match "/api/v1/http_endpoints" => "legacy_api/http_endpoints#index", via: [:get]
  match "/api/v1/http_endpoints" => "legacy_api/http_endpoints#create", via: [:post]
  match "/api/v1/http_endpoints/:id" => "legacy_api/http_endpoints#show", via: [:get]
  match "/api/v1/http_endpoints/:id" => "legacy_api/http_endpoints#update", via: [:put, :patch]
  match "/api/v1/http_endpoints/:id" => "legacy_api/http_endpoints#destroy", via: [:delete]

  # SMTP Endpoints
  match "/api/v1/smtp_endpoints" => "legacy_api/smtp_endpoints#index", via: [:get]
  match "/api/v1/smtp_endpoints" => "legacy_api/smtp_endpoints#create", via: [:post]
  match "/api/v1/smtp_endpoints/:id" => "legacy_api/smtp_endpoints#show", via: [:get]
  match "/api/v1/smtp_endpoints/:id" => "legacy_api/smtp_endpoints#update", via: [:put, :patch]
  match "/api/v1/smtp_endpoints/:id" => "legacy_api/smtp_endpoints#destroy", via: [:delete]

  # Address Endpoints
  match "/api/v1/address_endpoints" => "legacy_api/address_endpoints#index", via: [:get]
  match "/api/v1/address_endpoints" => "legacy_api/address_endpoints#create", via: [:post]
  match "/api/v1/address_endpoints/:id" => "legacy_api/address_endpoints#show", via: [:get]
  match "/api/v1/address_endpoints/:id" => "legacy_api/address_endpoints#update", via: [:put, :patch]
  match "/api/v1/address_endpoints/:id" => "legacy_api/address_endpoints#destroy", via: [:delete]

  scope "org/:org_permalink", as: "organization" do
    resources :domains, only: [:index, :new, :create, :destroy] do
      match :verify, on: :member, via: [:get, :post]
      get :setup, on: :member
      post :check, on: :member
    end
    resources :servers, except: [:index] do
      resources :domains, only: [:index, :new, :create, :destroy] do
        match :verify, on: :member, via: [:get, :post]
        get :setup, on: :member
        post :check, on: :member
      end
      resources :track_domains do
        post :toggle_ssl, on: :member
        post :check, on: :member
      end
      resources :credentials
      resources :routes
      resources :http_endpoints
      resources :smtp_endpoints
      resources :address_endpoints
      resources :ip_pool_rules
      resources :messages do
        get :incoming, on: :collection
        get :outgoing, on: :collection
        get :held, on: :collection
        get :activity, on: :member
        get :plain, on: :member
        get :html, on: :member
        get :html_raw, on: :member
        get :attachments, on: :member
        get :headers, on: :member
        get :attachment, on: :member
        get :download, on: :member
        get :spam_checks, on: :member
        post :retry, on: :member
        post :cancel_hold, on: :member
        get :suppressions, on: :collection
        delete :remove_from_queue, on: :member
        get :deliveries, on: :member
      end
      resources :webhooks do
        get :history, on: :collection
        get "history/:uuid", on: :collection, action: "history_request", as: "history_request"
      end
      get :limits, on: :member
      get :retention, on: :member
      get :queue, on: :member
      get :spam, on: :member
      get :delete, on: :member
      get "help/outgoing" => "help#outgoing"
      get "help/incoming" => "help#incoming"
      get :advanced, on: :member
      post :suspend, on: :member
      post :unsuspend, on: :member
    end

    resources :ip_pool_rules
    resources :ip_pools, controller: "organization_ip_pools" do
      put :assignments, on: :collection
    end
    root "servers#index"
    get "settings" => "organizations#edit"
    patch "settings" => "organizations#update"
    get "delete" => "organizations#delete"
    delete "delete" => "organizations#destroy"
  end

  resources :organizations, except: [:index]
  resources :users
  resources :ip_pools do
    resources :ip_addresses
  end

  get "settings" => "user#edit"
  patch "settings" => "user#update"
  post "persist" => "sessions#persist"

  get "login" => "sessions#new"
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy"
  match "login/reset" => "sessions#begin_password_reset", :via => [:get, :post]
  match "login/reset/:token" => "sessions#finish_password_reset", :via => [:get, :post]

  if Postal::Config.oidc.enabled?
    get "auth/oidc/callback", to: "sessions#create_from_oidc"
  end

  get ".well-known/jwks.json" => "well_known#jwks"

  get "ip" => "sessions#ip"

  root "organizations#index"
end
