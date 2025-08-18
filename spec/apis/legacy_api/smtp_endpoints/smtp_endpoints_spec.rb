# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy SMTP Endpoints API", type: :request do
  describe "/api/v1/smtp_endpoints" do
    context "when no authentication is provided" do
      it "returns an error" do
        get "/api/v1/smtp_endpoints"
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "AccessDenied"
      end
    end

    context "when the credential does not match anything" do
      it "returns an error" do
        get "/api/v1/smtp_endpoints", headers: { "x-server-api-key" => "invalid" }
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
        get "/api/v1/smtp_endpoints", headers: { "x-server-api-key" => credential.key }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "ServerSuspended"
      end
    end

    context "when the credential is valid" do
      let(:server) { create(:server) }
      let(:credential) { create(:credential, server: server) }
      let!(:smtp_endpoint1) { create(:smtp_endpoint, server: server, name: "SMTP Server 1", hostname: "smtp1.example.com", port: 587) }
      let!(:smtp_endpoint2) { create(:smtp_endpoint, server: server, name: "SMTP Server 2", hostname: "smtp2.example.com", port: 25) }

      describe "GET /api/v1/smtp_endpoints" do
        it "returns a list of SMTP endpoints" do
          get "/api/v1/smtp_endpoints", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["smtp_endpoints"]).to be_an(Array)
          expect(parsed_body["data"]["smtp_endpoints"].size).to eq 2
          expect(parsed_body["data"]["meta"]["total"]).to eq 2
        end

        it "supports pagination" do
          get "/api/v1/smtp_endpoints?page=1&per_page=1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["smtp_endpoints"].size).to eq 1
          expect(parsed_body["data"]["meta"]["page"]).to eq 1
          expect(parsed_body["data"]["meta"]["per_page"]).to eq 1
          expect(parsed_body["data"]["meta"]["total_pages"]).to eq 2
        end

        it "supports search filtering" do
          get "/api/v1/smtp_endpoints?search=SMTP Server 1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["smtp_endpoints"].size).to eq 1
          expect(parsed_body["data"]["smtp_endpoints"][0]["name"]).to eq "SMTP Server 1"
        end

        it "supports SSL mode filtering" do
          smtp_endpoint1.update(ssl_mode: "TLS")
          get "/api/v1/smtp_endpoints?ssl_mode=TLS", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["smtp_endpoints"].size).to eq 1
          expect(parsed_body["data"]["smtp_endpoints"][0]["ssl_mode"]).to eq "TLS"
        end
      end

      describe "GET /api/v1/smtp_endpoints/:id" do
        it "returns a specific SMTP endpoint" do
          get "/api/v1/smtp_endpoints/#{smtp_endpoint1.uuid}", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["smtp_endpoint"]["id"]).to eq smtp_endpoint1.uuid
          expect(parsed_body["data"]["smtp_endpoint"]["name"]).to eq "SMTP Server 1"
          expect(parsed_body["data"]["smtp_endpoint"]["hostname"]).to eq "smtp1.example.com"
          expect(parsed_body["data"]["smtp_endpoint"]["port"]).to eq 587
        end

        it "returns error for non-existent SMTP endpoint" do
          get "/api/v1/smtp_endpoints/invalid-uuid", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "SMTPEndpointNotFound"
        end
      end

      describe "POST /api/v1/smtp_endpoints" do
        it "creates a new SMTP endpoint" do
          post "/api/v1/smtp_endpoints", 
               params: { 
                 name: "New SMTP Server",
                 hostname: "smtp.newserver.com",
                 port: 465,
                 ssl_mode: "SSL"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["smtp_endpoint"]["name"]).to eq "New SMTP Server"
          expect(parsed_body["data"]["smtp_endpoint"]["hostname"]).to eq "smtp.newserver.com"
          expect(parsed_body["data"]["smtp_endpoint"]["port"]).to eq 465
          expect(parsed_body["data"]["smtp_endpoint"]["ssl_mode"]).to eq "SSL"
        end

        it "creates SMTP endpoint with authentication" do
          post "/api/v1/smtp_endpoints", 
               params: { 
                 name: "Auth SMTP",
                 hostname: "smtp.auth.com",
                 port: 587,
                 ssl_mode: "TLS",
                 username: "testuser",
                 password: "testpass"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["smtp_endpoint"]["username"]).to eq "testuser"
          expect(parsed_body["data"]["smtp_endpoint"]["password"]).to eq "testpass"
        end

        it "returns error when name is missing" do
          post "/api/v1/smtp_endpoints",
               params: { hostname: "smtp.example.com", port: 25 }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "name"
        end

        it "returns error when hostname is missing" do
          post "/api/v1/smtp_endpoints",
               params: { name: "Test SMTP", port: 25 }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "hostname"
        end

        it "returns error for invalid port" do
          post "/api/v1/smtp_endpoints",
               params: { 
                 name: "Bad Port",
                 hostname: "smtp.example.com",
                 port: 70000
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "port"
        end
      end

      describe "PUT /api/v1/smtp_endpoints/:id" do
        it "updates an SMTP endpoint" do
          put "/api/v1/smtp_endpoints/#{smtp_endpoint1.uuid}",
              params: { 
                name: "Updated SMTP Server",
                port: 465,
                ssl_mode: "SSL"
              }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["smtp_endpoint"]["name"]).to eq "Updated SMTP Server"
          expect(parsed_body["data"]["smtp_endpoint"]["port"]).to eq 465
          expect(parsed_body["data"]["smtp_endpoint"]["ssl_mode"]).to eq "SSL"
        end

        it "returns error for non-existent SMTP endpoint" do
          put "/api/v1/smtp_endpoints/invalid-uuid",
              params: { name: "Updated" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "SMTPEndpointNotFound"
        end
      end

      describe "DELETE /api/v1/smtp_endpoints/:id" do
        it "deletes an SMTP endpoint" do
          delete "/api/v1/smtp_endpoints/#{smtp_endpoint1.uuid}",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "deleted"
          expect(SMTPEndpoint.find_by(uuid: smtp_endpoint1.uuid)).to be_nil
        end

        it "returns error for non-existent SMTP endpoint" do
          delete "/api/v1/smtp_endpoints/invalid-uuid",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "SMTPEndpointNotFound"
        end
      end
    end
  end
end