# frozen_string_literal: true

# == Schema Information
#
# Table name: organizations
#
#  id                :integer          not null, primary key
#  uuid              :string(255)
#  name              :string(255)
#  permalink         :string(255)
#  time_zone         :string(255)
#  created_at        :datetime
#  updated_at        :datetime
#  ip_pool_id        :integer
#  owner_id          :integer
#  deleted_at        :datetime
#  suspended_at      :datetime
#  suspension_reason :string(255)
#
# Indexes
#
#  index_organizations_on_permalink  (permalink)
#  index_organizations_on_uuid       (uuid)
#

FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Acme Inc #{SecureRandom.hex(4)}-#{n}" }
    sequence(:permalink) { |n| "org-#{SecureRandom.hex(8)}-#{n}" }
    association :owner, factory: :user

    trait :suspended do
      suspended_at { 1.day.ago }
      suspension_reason { "test" }
    end
  end
end
