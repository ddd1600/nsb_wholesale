# frozen_string_literal: true

# Entry point for wholesale customers migrated from B2BWave to claim the account
# we created for them: they enter their email, we send a verification link, and
# the existing Devise flow (user_passwords#edit) lets them set a password.
class ClaimsController < StoreController
  # This page tells the visitor whether an email is on file. That is a
  # deliberate product decision -- it lets a customer who mistyped, or who used a
  # different address for their business, correct course instead of waiting for
  # an email that will never arrive.
  #
  # The cost is that the form can confirm whether a given address is a customer
  # of ours. Rate limiting keeps that to a human-scale mistake rather than a way
  # to test a list of company addresses in bulk.
  rate_limit to: 10, within: 5.minutes, only: :create, with: -> { rate_limit_exceeded }

  def new
    @email = params[:email]
  end

  def create
    @email = params.dig(:claim, :email).to_s.strip.downcase

    if @email.blank?
      flash.now[:error] = t("nsb.claims.blank_email")
      return render :new, status: :unprocessable_content
    end

    user = Spree.user_class.find_by("lower(email) = ?", @email)

    if user.nil?
      # Explicit "not on file" response, per the decision above.
      flash.now[:error] = t("nsb.claims.not_found", email: @email)
      return render :new, status: :unprocessable_content
    end

    user.send_claim_instructions
    redirect_to claim_sent_path(email: @email)
  end

  # Separate page rather than a flash, so a customer can leave and come back to
  # the "check your email" instructions without re-submitting the form.
  def sent
    @email = params[:email]
  end

  private

  def rate_limit_exceeded
    flash.now[:error] = t("nsb.claims.rate_limited")
    render :new, status: :too_many_requests
  end
end
