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

    # Advisory only. Google cannot tell us an address is fake, only that it
    # could not confirm one, and plenty of real addresses -- rural routes, new
    # builds, unfamiliar suites -- cannot be confirmed. Blocking those would
    # cost licensed retailers, so the applicant can always proceed.
    #
    # What they cannot do is proceed by accident. The confirmation is a checkbox
    # they have to tick, not a hidden field that rides along with a second
    # submit, and the verdict is recorded either way so the operator sees it
    # when deciding.
    results = address_results
    @address_warnings = results.values.select(&:suspect?)

    @application.address_verdict = verdict_for(results[:address])
    @application.shipping_address_verdict = verdict_for(results[:shipping_address])

    if @address_warnings.any? && params[:addresses_confirmed].blank?
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

  # { field => Result } for both addresses on the form.
  def address_results
    validator = Nsb::AddressValidator.new

    { address: @application.address, shipping_address: @application.shipping_address }
      .to_h { |field, value| [ field, validator.call(value) ] }
  end

  # Blank shipping address and an unreachable Google both record "unchecked",
  # so a blank verdict in the admin always means the row predates this and never
  # "we checked and it was fine".
  def verdict_for(result)
    return "unchecked" if result.nil? || result.skipped?

    result.confirmed? ? "confirmed" : "unverified"
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
