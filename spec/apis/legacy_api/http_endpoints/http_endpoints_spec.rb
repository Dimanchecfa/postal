# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy HTTP Endpoints API", type: :request do
  describe "/api/v1/http_endpoints" do
    context "when no authentication is provided" do
      it "returns an error" do
        get "/api/v1/http_endpoints"
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "AccessDenied"
      end
    end

    context "when the credential does not match anything" do
      it "returns an error" do
        get "/api/v1/http_endpoints", headers: { "x-server-api-key" => "invalid" }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "InvalidServerAPIKey"
      end
    end

    context "when the credential belongs to a suspended server" do
      it "returns an error" do
        organization = create(:organization, permalink: "suspended-org-#{SecureRandom.hex(4)}")
        server = create(:server, :suspended, organization: organization, name: "Suspended Server #{SecureRandom.hex(4)}", permalink: "suspended-server-#{SecureRandom.hex(4)}")
        credential = create(:credential, server: server)
        get "/api/v1/http_endpoints", headers: { "x-server-api-key" => credential.key }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "ServerSuspended"
      end
    end

    context "when the credential is valid" do
      let(:organization) { create(:organization, permalink: "test-org-#{SecureRandom.hex(4)}") }
      let(:server) { create(:server, organization: organization, name: "Test Server #{SecureRandom.hex(4)}", permalink: "test-server-#{SecureRandom.hex(4)}") }
      let(:credential) { create(:credential, server: server) }
      let!(:http_endpoint1) { create(:http_endpoint, server: server, name: "Webhook 1", url: "https://example.com/webhook1") }
      let!(:http_endpoint2) { create(:http_endpoint, server: server, name: "Webhook 2", url: "https://example.com/webhook2") }

      describe "GET /api/v1/http_endpoints" do
        it "returns a list of HTTP endpoints" do
          puts "Before request - HTTP Endpoint 1: server_id=#{http_endpoint1.server_id}, server=#{http_endpoint1.server&.id}"
          puts "Before request - HTTP Endpoint 2: server_id=#{http_endpoint2.server_id}, server=#{http_endpoint2.server&.id}"
          puts "Before request - Test Server ID: #{server.id}"
          puts "Before request - Credential Server ID: #{credential.server_id}"
          puts "Before request - HTTPEndpoint.where(server_id: #{server.id}).count: #{HTTPEndpoint.where(server_id: server.id).count}"
          
          get "/api/v1/http_endpoints", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          puts "Response body: #{parsed_body}"
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["http_endpoints"]).to be_an(Array)
          expect(parsed_body["data"]["http_endpoints"].size).to eq 2
          expect(parsed_body["data"]["meta"]["total"]).to eq 2
        end

        it "supports pagination" do
          get "/api/v1/http_endpoints?page=1&per_page=1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["http_endpoints"].size).to eq 1
          expect(parsed_body["data"]["meta"]["page"]).to eq 1
          expect(parsed_body["data"]["meta"]["per_page"]).to eq 1
          expect(parsed_body["data"]["meta"]["total_pages"]).to eq 2
        end

        it "supports search filtering" do
          get "/api/v1/http_endpoints?search=Webhook 1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["http_endpoints"].size).to eq 1
          expect(parsed_body["data"]["http_endpoints"][0]["name"]).to eq "Webhook 1"
        end

        it "supports format filtering" do
          http_endpoint1.update(format: "BodyAsJSON")
          get "/api/v1/http_endpoints?format=BodyAsJSON", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["http_endpoints"].size).to eq 1
          expect(parsed_body["data"]["http_endpoints"][0]["format"]).to eq "BodyAsJSON"
        end
      end

      describe "GET /api/v1/http_endpoints/:id" do
        it "returns a specific HTTP endpoint" do
          get "/api/v1/http_endpoints/#{http_endpoint1.uuid}", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["http_endpoint"]["id"]).to eq http_endpoint1.uuid
          expect(parsed_body["data"]["http_endpoint"]["name"]).to eq "Webhook 1"
          expect(parsed_body["data"]["http_endpoint"]["url"]).to eq "https://example.com/webhook1"
        end

        it "returns error for non-existent HTTP endpoint" do
          get "/api/v1/http_endpoints/invalid-uuid", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "HTTPEndpointNotFound"
        end
      end

      describe "POST /api/v1/http_endpoints" do
        it "creates a new HTTP endpoint" do
          post "/api/v1/http_endpoints", 
               params: { 
                 name: "New Webhook",
                 url: "https://newsite.com/webhook",
                 format: "Hash"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["http_endpoint"]["name"]).to eq "New Webhook"
          expect(parsed_body["data"]["http_endpoint"]["url"]).to eq "https://newsite.com/webhook"
          expect(parsed_body["data"]["http_endpoint"]["format"]).to eq "Hash"
        end

        it "creates HTTP endpoint with BodyAsJSON format" do
          post "/api/v1/http_endpoints", 
               params: { 
                 name: "JSON Webhook",
                 url: "https://api.example.com/webhook",
                 format: "BodyAsJSON",
                 encoding: "base64"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["http_endpoint"]["format"]).to eq "BodyAsJSON"
          expect(parsed_body["data"]["http_endpoint"]["encoding"]).to eq "base64"
        end

        it "returns error when name is missing" do
          post "/api/v1/http_endpoints",
               params: { url: "https://example.com/webhook" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "name"
        end

        it "returns error when url is missing" do
          post "/api/v1/http_endpoints",
               params: { name: "Test Webhook" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "url"
        end

        it "returns error for invalid format" do
          post "/api/v1/http_endpoints",
               params: { 
                 name: "Bad Format",
                 url: "https://example.com/webhook",
                 format: "InvalidFormat"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "Format"
        end
      end

      describe "PUT /api/v1/http_endpoints/:id" do
        it "updates an HTTP endpoint" do
          put "/api/v1/http_endpoints/#{http_endpoint1.uuid}",
              params: { 
                name: "Updated Webhook",
                url: "https://updated.com/webhook",
                timeout: 60
              }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["http_endpoint"]["name"]).to eq "Updated Webhook"
          expect(parsed_body["data"]["http_endpoint"]["url"]).to eq "https://updated.com/webhook"
          expect(parsed_body["data"]["http_endpoint"]["timeout"]).to eq 60
        end

        it "returns error for non-existent HTTP endpoint" do
          put "/api/v1/http_endpoints/invalid-uuid",
              params: { name: "Updated" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "HTTPEndpointNotFound"
        end
      end

      describe "DELETE /api/v1/http_endpoints/:id" do
        it "deletes an HTTP endpoint" do
          delete "/api/v1/http_endpoints/#{http_endpoint1.uuid}",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "deleted"
          expect(HTTPEndpoint.find_by(uuid: http_endpoint1.uuid)).to be_nil
        end

        it "returns error for non-existent HTTP endpoint" do
          delete "/api/v1/http_endpoints/invalid-uuid",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "HTTPEndpointNotFound"
        end
      end
    end
  end
end