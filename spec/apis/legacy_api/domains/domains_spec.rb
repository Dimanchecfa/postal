# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy Domains API", type: :request do
  describe "/api/v1/domains" do
    context "when no authentication is provided" do
      it "returns an error" do
        get "/api/v1/domains"
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "AccessDenied"
      end
    end

    context "when the credential does not match anything" do
      it "returns an error" do
        get "/api/v1/domains", headers: { "x-server-api-key" => "invalid" }
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
        get "/api/v1/domains", headers: { "x-server-api-key" => credential.key }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "ServerSuspended"
      end
    end

    context "when the credential is valid" do
      let(:server) { create(:server) }
      let(:credential) { create(:credential, server: server) }
      let!(:domain1) { create(:domain, owner: server, name: "example1.com") }
      let!(:domain2) { create(:domain, owner: server, name: "example2.com") }

      describe "GET /api/v1/domains" do
        it "returns a list of domains" do
          get "/api/v1/domains", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["domains"]).to be_an(Array)
          expect(parsed_body["data"]["domains"].size).to eq 2
          expect(parsed_body["data"]["meta"]["total"]).to eq 2
        end

        it "supports pagination" do
          get "/api/v1/domains?page=1&per_page=1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["domains"].size).to eq 1
          expect(parsed_body["data"]["meta"]["page"]).to eq 1
          expect(parsed_body["data"]["meta"]["per_page"]).to eq 1
          expect(parsed_body["data"]["meta"]["total_pages"]).to eq 2
        end

        it "supports search filtering" do
          get "/api/v1/domains?search=example1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["domains"].size).to eq 1
          expect(parsed_body["data"]["domains"][0]["name"]).to eq "example1.com"
        end

        it "supports verified filtering" do
          domain1.update(verified_at: Time.now)
          get "/api/v1/domains?verified=true", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["domains"].size).to eq 1
          expect(parsed_body["data"]["domains"][0]["name"]).to eq "example1.com"
        end
      end

      describe "GET /api/v1/domains/:id" do
        it "returns a specific domain" do
          get "/api/v1/domains/#{domain1.uuid}", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["domain"]["id"]).to eq domain1.uuid
          expect(parsed_body["data"]["domain"]["name"]).to eq "example1.com"
        end

        it "returns error for non-existent domain" do
          get "/api/v1/domains/invalid-uuid", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "DomainNotFound"
        end

        it "returns error when id is blank" do
          get "/api/v1/domains/", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
        end
      end

      describe "POST /api/v1/domains" do
        it "creates a new domain" do
          post "/api/v1/domains", 
               params: { name: "newdomain.com", verification_method: "DNS" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["domain"]["name"]).to eq "newdomain.com"
          expect(parsed_body["data"]["domain"]["verified_at"]).to be_present # Auto-verified for API
        end

        it "returns error when name is missing" do
          post "/api/v1/domains",
               params: { verification_method: "DNS" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "name"
        end

        it "returns error for duplicate domain" do
          post "/api/v1/domains",
               params: { name: "example1.com", verification_method: "DNS" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "already"
        end
      end

      describe "PUT /api/v1/domains/:id" do
        it "updates a domain" do
          put "/api/v1/domains/#{domain1.uuid}",
              params: { verification_method: "Email" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["domain"]["verification_method"]).to eq "Email"
        end

        it "returns error for non-existent domain" do
          put "/api/v1/domains/invalid-uuid",
              params: { verification_method: "Email" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "DomainNotFound"
        end
      end

      describe "DELETE /api/v1/domains/:id" do
        it "deletes a domain" do
          delete "/api/v1/domains/#{domain1.uuid}",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "deleted"
          expect(Domain.find_by(uuid: domain1.uuid)).to be_nil
        end

        it "returns error for non-existent domain" do
          delete "/api/v1/domains/invalid-uuid",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "DomainNotFound"
        end
      end

      describe "POST /api/v1/domains/:id/verify" do
        it "verifies a domain with DNS" do
          domain1.update(verified_at: nil, verification_method: "DNS")
          allow_any_instance_of(Domain).to receive(:verify_with_dns).and_return(true)
          
          post "/api/v1/domains/#{domain1.uuid}/verify",
               headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "verified successfully"
        end

        it "returns already verified for verified domain" do
          domain1.update(verified_at: Time.now)
          
          post "/api/v1/domains/#{domain1.uuid}/verify",
               headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "already verified"
        end
      end

      describe "POST /api/v1/domains/:id/check_dns" do
        it "checks DNS configuration" do
          allow_any_instance_of(Domain).to receive(:check_dns).and_return(true)
          allow_any_instance_of(Domain).to receive(:dns_ok?).and_return(true)
          
          post "/api/v1/domains/#{domain1.uuid}/check_dns",
               headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["dns_ok"]).to eq true
          expect(parsed_body["data"]["message"]).to include "correctly configured"
        end

        it "returns error for non-existent domain" do
          post "/api/v1/domains/invalid-uuid/check_dns",
               headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "DomainNotFound"
        end
      end
    end
  end
end