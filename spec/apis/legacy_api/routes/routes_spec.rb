# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy Routes API", type: :request do
  describe "/api/v1/routes" do
    context "when no authentication is provided" do
      it "returns an error" do
        get "/api/v1/routes"
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "AccessDenied"
      end
    end

    context "when the credential does not match anything" do
      it "returns an error" do
        get "/api/v1/routes", headers: { "x-server-api-key" => "invalid" }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "InvalidServerAPIKey"
      end
    end

    context "when the credential belongs to a suspended server" do
      it "returns an error" do
        server = create(:server, :suspended)
        credential = create(:credential, server: server)
        get "/api/v1/routes", headers: { "x-server-api-key" => credential.key }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "ServerSuspended"
      end
    end

    context "when the credential is valid" do
      let(:server) { create(:server) }
      let(:credential) { create(:credential, server: server) }
      let!(:domain) { create(:domain, owner: server, name: "example.com") }
      let!(:http_endpoint) { create(:http_endpoint, server: server, name: "Test HTTP", url: "https://example.com/webhook") }
      let!(:route1) { create(:route, server: server, domain: domain, name: "test", endpoint: http_endpoint) }
      let!(:route2) { create(:route, server: server, domain: domain, name: "info", endpoint: http_endpoint) }

      describe "GET /api/v1/routes" do
        it "returns a list of routes" do
          get "/api/v1/routes", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["routes"]).to be_an(Array)
          expect(parsed_body["data"]["routes"].size).to eq 2
          expect(parsed_body["data"]["meta"]["total"]).to eq 2
        end

        it "supports pagination" do
          get "/api/v1/routes?page=1&per_page=1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["routes"].size).to eq 1
          expect(parsed_body["data"]["meta"]["page"]).to eq 1
          expect(parsed_body["data"]["meta"]["per_page"]).to eq 1
          expect(parsed_body["data"]["meta"]["total_pages"]).to eq 2
        end

        it "supports search filtering" do
          get "/api/v1/routes?search=test", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["routes"].size).to eq 1
          expect(parsed_body["data"]["routes"][0]["name"]).to eq "test"
        end

        it "supports domain filtering" do
          get "/api/v1/routes?domain_id=#{domain.uuid}", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["routes"].size).to eq 2
          expect(parsed_body["data"]["routes"].all? { |r| r["domain"]["id"] == domain.uuid }).to be true
        end
      end

      describe "GET /api/v1/routes/:id" do
        it "returns a specific route" do
          get "/api/v1/routes/#{route1.uuid}", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["route"]["id"]).to eq route1.uuid
          expect(parsed_body["data"]["route"]["name"]).to eq "test"
          expect(parsed_body["data"]["route"]["endpoint"]["type"]).to eq "HTTPEndpoint"
        end

        it "returns error for non-existent route" do
          get "/api/v1/routes/invalid-uuid", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "RouteNotFound"
        end
      end

      describe "POST /api/v1/routes" do
        it "creates a new route with HTTP endpoint" do
          post "/api/v1/routes", 
               params: { 
                 name: "new",
                 domain_id: domain.uuid,
                 endpoint_id: http_endpoint.uuid,
                 endpoint_type: "HTTPEndpoint"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["route"]["name"]).to eq "new"
          expect(parsed_body["data"]["route"]["endpoint"]["type"]).to eq "HTTPEndpoint"
        end

        it "returns error when name is missing" do
          post "/api/v1/routes",
               params: { 
                 domain_id: domain.uuid,
                 endpoint_id: http_endpoint.uuid,
                 endpoint_type: "HTTPEndpoint"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "name"
        end

        it "returns error when domain_id is missing" do
          post "/api/v1/routes",
               params: { 
                 name: "test",
                 endpoint_id: http_endpoint.uuid,
                 endpoint_type: "HTTPEndpoint"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "Domain"
        end

        it "returns error when endpoint_id is missing" do
          post "/api/v1/routes",
               params: { 
                 name: "test",
                 domain_id: domain.uuid,
                 endpoint_type: "HTTPEndpoint"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "Endpoint"
        end
      end

      describe "PUT /api/v1/routes/:id" do
        it "updates a route" do
          put "/api/v1/routes/#{route1.uuid}",
              params: { name: "updated", mode: "Reject" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["route"]["name"]).to eq "updated"
          expect(parsed_body["data"]["route"]["mode"]).to eq "Reject"
        end

        it "returns error for non-existent route" do
          put "/api/v1/routes/invalid-uuid",
              params: { name: "updated" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "RouteNotFound"
        end
      end

      describe "DELETE /api/v1/routes/:id" do
        it "deletes a route" do
          delete "/api/v1/routes/#{route1.uuid}",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "deleted"
          expect(Route.find_by(uuid: route1.uuid)).to be_nil
        end

        it "returns error for non-existent route" do
          delete "/api/v1/routes/invalid-uuid",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "RouteNotFound"
        end
      end
    end
  end
end