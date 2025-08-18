# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy Credentials API", type: :request do
  describe "/api/v1/credentials" do
    context "when no authentication is provided" do
      it "returns an error" do
        get "/api/v1/credentials"
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "AccessDenied"
      end
    end

    context "when the credential does not match anything" do
      it "returns an error" do
        get "/api/v1/credentials", headers: { "x-server-api-key" => "invalid" }
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
        get "/api/v1/credentials", headers: { "x-server-api-key" => credential.key }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "ServerSuspended"
      end
    end

    context "when the credential is valid" do
      let(:server) { create(:server) }
      let(:credential) { create(:credential, server: server, type: "API") }
      let!(:credential2) { create(:credential, server: server, type: "SMTP", name: "SMTP Credential") }
      let!(:credential3) { create(:credential, server: server, type: "API", name: "Another API") }

      describe "GET /api/v1/credentials" do
        it "returns a list of credentials" do
          get "/api/v1/credentials", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          puts "Credentials response: #{parsed_body}"
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["credentials"]).to be_an(Array)
          expect(parsed_body["data"]["credentials"].size).to eq 3
          expect(parsed_body["data"]["meta"]["total"]).to eq 3
        end

        it "supports pagination" do
          get "/api/v1/credentials?page=1&per_page=2", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["credentials"].size).to eq 2
          expect(parsed_body["data"]["meta"]["page"]).to eq 1
          expect(parsed_body["data"]["meta"]["per_page"]).to eq 2
          expect(parsed_body["data"]["meta"]["total_pages"]).to eq 2
        end

        it "supports type filtering" do
          get "/api/v1/credentials?type=API", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["credentials"].size).to eq 2
          expect(parsed_body["data"]["credentials"].all? { |c| c["type"] == "API" }).to be true
        end
      end

      describe "GET /api/v1/credentials/:id" do
        it "returns a specific credential" do
          get "/api/v1/credentials/#{credential2.uuid}", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["credential"]["id"]).to eq credential2.uuid
          expect(parsed_body["data"]["credential"]["name"]).to eq "SMTP Credential"
          expect(parsed_body["data"]["credential"]["type"]).to eq "SMTP"
        end

        it "returns error for non-existent credential" do
          get "/api/v1/credentials/invalid-uuid", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "CredentialNotFound"
        end

        it "returns error when id is blank" do
          get "/api/v1/credentials/", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
        end
      end

      describe "POST /api/v1/credentials" do
        it "creates a new API credential" do
          post "/api/v1/credentials", 
               params: { name: "New API Key", type: "API" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["credential"]["name"]).to eq "New API Key"
          expect(parsed_body["data"]["credential"]["type"]).to eq "API"
          expect(parsed_body["data"]["credential"]["key"]).to be_present
        end

        it "creates a new SMTP-IP credential" do
          post "/api/v1/credentials", 
               params: { name: "IP Whitelist", type: "SMTP-IP", key: "192.168.1.1" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["credential"]["name"]).to eq "IP Whitelist"
          expect(parsed_body["data"]["credential"]["type"]).to eq "SMTP-IP"
          expect(parsed_body["data"]["credential"]["key"]).to eq "192.168.1.1"
        end

        it "returns error when name is missing" do
          post "/api/v1/credentials",
               params: { type: "API" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "name"
        end

        it "returns error when type is missing" do
          post "/api/v1/credentials",
               params: { name: "Test" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "type"
        end

        it "returns error for invalid IP in SMTP-IP type" do
          post "/api/v1/credentials",
               params: { name: "Bad IP", type: "SMTP-IP", key: "invalid-ip" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "valid"
        end
      end

      describe "PUT /api/v1/credentials/:id" do
        it "updates a credential name" do
          put "/api/v1/credentials/#{credential2.uuid}",
              params: { name: "Updated SMTP" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["credential"]["name"]).to eq "Updated SMTP"
        end

        it "returns error for non-existent credential" do
          put "/api/v1/credentials/invalid-uuid",
              params: { name: "Updated" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "CredentialNotFound"
        end

        it "prevents updating the key for non-SMTP-IP types" do
          put "/api/v1/credentials/#{credential2.uuid}",
              params: { key: "newkey123" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          credential2.reload
          expect(credential2.key).not_to eq "newkey123"
        end
      end

      describe "DELETE /api/v1/credentials/:id" do
        it "deletes a credential" do
          delete "/api/v1/credentials/#{credential2.uuid}",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "deleted"
          expect(Credential.find_by(uuid: credential2.uuid)).to be_nil
        end

        it "returns error for non-existent credential" do
          delete "/api/v1/credentials/invalid-uuid",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "CredentialNotFound"
        end
      end
    end
  end
end