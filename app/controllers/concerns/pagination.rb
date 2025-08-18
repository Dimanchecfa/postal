# frozen_string_literal: true

module Pagination
  extend ActiveSupport::Concern

  def default_per_page
    25
  end

  def max_per_page
    100
  end

  def page_no
    params[:page]&.to_i || 1
  end

  def per_page
    requested = params[:per_page]&.to_i || default_per_page
    [requested, max_per_page].min
  end

  def paginate_offset
    (page_no - 1) * per_page
  end

  def paginate
    ->(it) { it.limit(per_page).offset(paginate_offset) }
  end

  def pagination_meta(total_count)
    {
      total: total_count,
      page: page_no,
      per_page: per_page,
      total_pages: (total_count.to_f / per_page).ceil
    }
  end
end