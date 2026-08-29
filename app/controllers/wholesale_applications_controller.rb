# frozen_string_literal: true

# Applications from businesses that are not customers yet.
#
# Nothing here creates an account. The row waits for the operator to approve it,
# which is the point: wholesale is license-gated, and an unvetted applicant
# should not appear in the customer list or be able to see pricing.
class WholesaleApplicationsController < StoreController
  # Same reasoning as ClaimsController: a public form that emails the operator is
  # worth rate limiting, or one bored person can fill an inbox.
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { rate_limit_exceeded }

  def new
    @application = Nsb::WholesaleApplication.new
  end

  def create
    @application = Nsb::WholesaleApplication.new(application_params)

    # Checked before validation so the message is about the account they already
    # have, rather than a duplicate-application error that means nothing to them.
    if (existing = @application.existing_account)
      flash.now[:notice] = t(
        "nsb.applications.already_a_customer_html",
        email: existing.email,
        claim: view_context.link_to(t("nsb.applications.already_a_customer_link"),
                                    claim_path(email: existing.email), class: "underline")
      ).html_safe
      return render :new, status: :unprocessable_content
    end

    unless @application.valid?
      return render :new, status: :unprocessable_content
    end

    # Advisory only, and only ever asked once. Google flags real addresses --
    # new builds, rural routes, unfamiliar suites -- and losing a licensed
    # retailer over a tidy address field is the worse trade. So the applicant is
    # shown what we found, and submitting again goes through unchanged.
    if !params[:addresses_confirmed] && (@address_warnings = address_warnings).any?
      return render :new, status: :unprocessable_content
    end

    if @application.save
      # Outside any transaction and deferred to a job: the applicant has done
      # their part, and a mail failure must not tell them the form was rejected.
      Nsb::OperatorMailer.application_received(@application).deliver_later
      redirect_to application_received_path
    else
      render :new, status: :unprocessable_content
    end
  end

  def received; end

  private

  # [{ field:, message:, suggestion: }] for any address Google could not confirm.
  def address_warnings
    validator = Nsb::AddressValidator.new

    { address: @application.address, shipping_address: @application.shipping_address }
      .filter_map do |field, value|
        result = validator.call(value)
        next unless result.suspect?

        { field: field, message: result.message, suggestion: result.formatted_address }
      end
  end

  def application_params
    params.require(:wholesale_application).permit(
      :business_name, :contact_name, :email, :phone, :address, :shipping_address,
      :retail_license_state, :retail_license_number,
      :sells, :interested_in, :heard_about_us
    )
  end

  def rate_limit_exceeded
    flash.now[:error] = t("nsb.claims.rate_limited")
    render :new, status: :too_many_requests
  end
end
