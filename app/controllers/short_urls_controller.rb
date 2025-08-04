class ShortUrlsController < ApplicationController
  # skip_before_action :authenticate_user!, only: [:redirect]
  skip_before_action :verify_authenticity_token, only: [:redirect]

  def redirect
    token = params[:token]

    if token.blank?
      render plain: 'Invalid short URL', status: :bad_request
      return
    end

    shortener = UrlShortenerService.new
    original_url = shortener.resolve_url(token)

    if original_url.present?
      redirect_to original_url, allow_other_host: true
    else
      render plain: 'Short URL not found or expired', status: :not_found
    end
  rescue StandardError => e
    Rails.logger.error "Error resolving short URL #{token}: #{e.message}"
    render plain: 'Internal server error', status: :internal_server_error
  end
end
