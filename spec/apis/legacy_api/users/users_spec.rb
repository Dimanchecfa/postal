# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy Users API", type: :request do
  describe "/api/v1/users" do
    context "when no authentication is provided" do
      it "returns an error" do
        get "/api/v1/users"
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "AccessDenied"
      end
    end

    context "when the credential does not match anything" do
      it "returns an error" do
        get "/api/v1/users", headers: { "x-server-api-key" => "invalid" }
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
        get "/api/v1/users", headers: { "x-server-api-key" => credential.key }
        expect(response.status).to eq 200
        parsed_body = JSON.parse(response.body)
        expect(parsed_body["status"]).to eq "error"
        expect(parsed_body["data"]["code"]).to eq "ServerSuspended"
      end
    end

    context "when the credential is valid" do
      let(:organization) { create(:organization) }
      let(:server) { create(:server, organization: organization) }
      let(:credential) { create(:credential, server: server) }
      let!(:user1) { create(:user, email_address: "user1@test.com", first_name: "John", last_name: "Doe") }
      let!(:user2) { create(:user, email_address: "user2@test.com", first_name: "Jane", last_name: "Smith") }
      
      before do
        organization.users << user1
        organization.users << user2
      end

      describe "GET /api/v1/users" do
        it "returns a list of users" do
          get "/api/v1/users", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["users"]).to be_an(Array)
          expect(parsed_body["data"]["users"].size).to eq 2
          expect(parsed_body["data"]["meta"]["total"]).to eq 2
        end

        it "supports pagination" do
          get "/api/v1/users?page=1&per_page=1", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["users"].size).to eq 1
          expect(parsed_body["data"]["meta"]["page"]).to eq 1
          expect(parsed_body["data"]["meta"]["per_page"]).to eq 1
          expect(parsed_body["data"]["meta"]["total_pages"]).to eq 2
        end

        it "supports search filtering" do
          get "/api/v1/users?search=John", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["users"].size).to eq 1
          expect(parsed_body["data"]["users"][0]["first_name"]).to eq "John"
        end

        it "supports admin filtering" do
          organization.organization_users.find_by(user: user1).update(admin: true)
          get "/api/v1/users?admin=true", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["data"]["users"].size).to eq 1
          expect(parsed_body["data"]["users"][0]["admin"]).to eq true
        end
      end

      describe "GET /api/v1/users/:id" do
        it "returns a specific user" do
          get "/api/v1/users/#{user1.uuid}", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["user"]["id"]).to eq user1.uuid
          expect(parsed_body["data"]["user"]["email_address"]).to eq "user1@test.com"
        end

        it "returns error for non-existent user" do
          get "/api/v1/users/invalid-uuid", headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "UserNotFound"
        end
      end

      describe "POST /api/v1/users" do
        it "creates a new user" do
          post "/api/v1/users", 
               params: { 
                 first_name: "New",
                 last_name: "User",
                 email_address: "newuser@test.com",
                 password: "password123"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["user"]["email_address"]).to eq "newuser@test.com"
          expect(parsed_body["data"]["user"]["first_name"]).to eq "New"
        end

        it "adds existing user to organization" do
          existing_user = create(:user, email_address: "existing@test.com", first_name: "Existing", last_name: "User")
          
          post "/api/v1/users", 
               params: { 
                 first_name: "Existing",
                 last_name: "User",
                 email_address: "existing@test.com"
               }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "added to organization"
        end

        it "returns error when email_address is missing" do
          post "/api/v1/users",
               params: { first_name: "Test", last_name: "User" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "email_address"
        end

        it "returns error when first_name is missing" do
          post "/api/v1/users",
               params: { email_address: "test@test.com", last_name: "User" }.to_json,
               headers: { 
                 "x-server-api-key" => credential.key,
                 "content-type" => "application/json"
               }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "parameter-error"
          expect(parsed_body["data"]["message"]).to include "first_name"
        end
      end

      describe "PUT /api/v1/users/:id" do
        it "updates a user" do
          put "/api/v1/users/#{user1.uuid}",
              params: { first_name: "Updated", admin: true }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["user"]["first_name"]).to eq "Updated"
          expect(parsed_body["data"]["user"]["admin"]).to eq true
        end

        it "returns error for non-existent user" do
          put "/api/v1/users/invalid-uuid",
              params: { first_name: "Updated" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "UserNotFound"
        end

        it "prevents changing email address" do
          put "/api/v1/users/#{user1.uuid}",
              params: { email_address: "newemail@test.com" }.to_json,
              headers: { 
                "x-server-api-key" => credential.key,
                "content-type" => "application/json"
              }
          expect(response.status).to eq 200
          user1.reload
          expect(user1.email_address).to eq "user1@test.com"
        end
      end

      describe "DELETE /api/v1/users/:id" do
        it "removes a user from organization" do
          delete "/api/v1/users/#{user1.uuid}",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "success"
          expect(parsed_body["data"]["message"]).to include "removed"
          expect(organization.users.include?(user1)).to be false
        end

        it "returns error for non-existent user" do
          delete "/api/v1/users/invalid-uuid",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "UserNotFound"
        end

        it "prevents deleting organization owner" do
          organization.update(owner: user1)
          delete "/api/v1/users/#{user1.uuid}",
                 headers: { "x-server-api-key" => credential.key }
          expect(response.status).to eq 200
          parsed_body = JSON.parse(response.body)
          expect(parsed_body["status"]).to eq "error"
          expect(parsed_body["data"]["code"]).to eq "CannotDeleteOwner"
        end
      end
    end
  end
end