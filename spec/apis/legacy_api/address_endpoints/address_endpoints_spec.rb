# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy Address Endpoints API", type: :request do
  describe "/api/v1/address_endpoints" do
    context "when no authentication is provided" do
      it "returns an error" do
        get "/api/v1/address_endpoints"
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "AccessDenied"
      end
    end

    context "when the credential does not match anything" do
      it "returns an error" do
        get "/api/v1/address_endpoints", headers: { "x-server-api-key" => "invalid" }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "InvalidServerAPIKey"
      end
    end

    context "when the credential belongs to a suspended server" do
      it "returns an error" do
        suspended_organization = create(:organization, permalink: "suspended-org-#{SecureRandom.hex(4)}")
        suspended_server = create(:server, :suspended, organization: suspended_organization, permalink: "suspended-server-#{SecureRandom.hex(4)}")
        credential = create(:credential, server: suspended_server)
        get "/api/v1/address_endpoints", headers: { "x-server-api-key" => credential.key }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "ServerSuspended"
      end
    end

    context "when the credential is valid" do
      let(:server) { create(:server) }
      let(:credential) { create(:credential, server: server) }
      let!(:address_endpoint1) { create(:address_endpoint, server: server, address: "admin@example.com") }
      let!(:address_endpoint2) { create(:address_endpoint, server: server, address: "support@example.com") }

      describe "GET /api/v1/address_endpoints" do
        it "returns a list of address endpoints" do
          get "/api/v1/address_endpoints", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["address_endpoints"]).to be_an(Array)
          expect(parsed_body["data"]["address_endpoints"].size).to eq 2
          expect(parsed_body["data"]["meta"]["total"]).to eq 2
        end

        it "supports pagination" do
          get "/api/v1/address_endpoints?page=1&per_page=1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["address_endpoints"].size).to eq 1
          expect(parsed_body["data"]["meta"]["page"]).to eq 1
          expect(parsed_body["data"]["meta"]["per_page"]).to eq 1
          expect(parsed_body["data"]["meta"]["total_pages"]).to eq 2
        end

        it "supports search filtering" do
          get "/api/v1/address_endpoints?search=admin", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["address_endpoints"].size).to eq 1
          expect(parsed_body["data"]["address_endpoints"][0]["address"]).to eq "admin@example.com"
        end

        it "supports address filtering" do
          get "/api/v1/address_endpoints?address=admin@example.com", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["address_endpoints"].size).to eq 1
          expect(parsed_body["data"]["address_endpoints"][0]["address"]).to eq "admin@example.com"
        end
      end

      describe "GET /api/v1/address_endpoints/:id" do
        it "returns a specific address endpoint" do
          get "/api/v1/address_endpoints/#{address_endpoint1.uuid}", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["address_endpoint"]["id"]).to eq address_endpoint1.uuid
          expect(parsed_body["data"]["address_endpoint"]["address"]).to eq "admin@example.com"
        end

        it "returns error for non-existent address endpoint" do
          get "/api/v1/address_endpoints/invalid-uuid", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "AddressEndpointNotFound"
        end
      end

      describe "POST /api/v1/address_endpoints" do
        it "creates a new address endpoint" do
          post "/api/v1/address_endpoints", 
               params: { 
                 address: "dev@example.com"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["address_endpoint"]["address"]).to eq "dev@example.com"
        end

        it "returns error when address is missing" do
          post "/api/v1/address_endpoints",
               params: {}.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "address"
        end

        it "returns error for invalid email address" do
          post "/api/v1/address_endpoints",
               params: { 
                 address: "invalid-email"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "invalid"
        end
      end

      describe "PUT /api/v1/address_endpoints/:id" do
        it "updates an address endpoint" do
          put "/api/v1/address_endpoints/#{address_endpoint1.uuid}",
              params: { 
                address: "newadmin@example.com"
              }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["address_endpoint"]["address"]).to eq "newadmin@example.com"
        end

        it "returns error for non-existent address endpoint" do
          put "/api/v1/address_endpoints/invalid-uuid",
              params: { address: "updated@example.com" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "AddressEndpointNotFound"
        end

        it "returns error for invalid email address" do
          put "/api/v1/address_endpoints/#{address_endpoint1.uuid}",
              params: { address: "invalid-email" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "invalid"
        end
      end

      describe "DELETE /api/v1/address_endpoints/:id" do
        it "deletes an address endpoint" do
          delete "/api/v1/address_endpoints/#{address_endpoint1.uuid}",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "deleted"
          expect(AddressEndpoint.find_by(uuid: address_endpoint1.uuid)).to be_nil
        end

        it "returns error for non-existent address endpoint" do
          delete "/api/v1/address_endpoints/invalid-uuid",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "AddressEndpointNotFound"
        end
      end
    end
  end
end