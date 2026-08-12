# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::GmailOauthToken do
  include ActiveSupport::Testing::TimeHelpers

  def stub_env
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("GMAIL_OAUTH_CLIENT_ID").and_return("client-id")
    allow(ENV).to receive(:fetch).with("GMAIL_OAUTH_CLIENT_SECRET").and_return("client-secret")
    allow(ENV).to receive(:fetch).with("GMAIL_OAUTH_REFRESH_TOKEN").and_return("refresh-token")
  end

  def stub_response(code:, body:)
    response = instance_double(
      code == "200" ? Net::HTTPOK : Net::HTTPBadRequest,
      code: code,
      body: body
    )
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(code == "200")
    allow(Net::HTTP).to receive(:post_form).and_return(response)
    response
  end

  before do
    described_class.reset!
    stub_env
  end

  after { described_class.reset! }

  it "returns the access token Google issues" do
    stub_response(code: "200", body: { access_token: "ya29.abc", expires_in: 3599 }.to_json)

    expect(described_class.access_token).to eq("ya29.abc")
  end

  it "caches the token instead of refreshing on every delivery" do
    stub_response(code: "200", body: { access_token: "ya29.abc", expires_in: 3599 }.to_json)

    3.times { described_class.access_token }

    expect(Net::HTTP).to have_received(:post_form).once
  end

  it "refreshes once the token has expired" do
    stub_response(code: "200", body: { access_token: "first", expires_in: 3599 }.to_json)
    expect(described_class.access_token).to eq("first")

    stub_response(code: "200", body: { access_token: "second", expires_in: 3599 }.to_json)
    travel_to 2.hours.from_now do
      expect(described_class.access_token).to eq("second")
    end
  end

  it "refreshes early, before the token actually lapses" do
    # expires_in 3599 minus the 60s margin: at 3550s the cached token must be gone.
    stub_response(code: "200", body: { access_token: "first", expires_in: 3599 }.to_json)
    described_class.access_token

    stub_response(code: "200", body: { access_token: "second", expires_in: 3599 }.to_json)
    travel_to 3550.seconds.from_now do
      expect(described_class.access_token).to eq("second")
    end
  end

  describe "when the refresh token has been revoked" do
    it "raises an actionable error rather than returning nil" do
      stub_response(code: "400", body: { error: "invalid_grant" }.to_json)

      # A nil password would surface as a baffling SMTP auth failure instead of
      # naming the real cause.
      expect { described_class.access_token }
        .to raise_error(described_class::RefreshError, /invalid_grant/)
    end

    it "points at the fix in the message" do
      stub_response(code: "400", body: { error: "invalid_grant" }.to_json)

      expect { described_class.access_token }
        .to raise_error(described_class::RefreshError, /nsb:mail:authorize/)
    end
  end

  it "raises rather than caching garbage when Google returns something unexpected" do
    stub_response(code: "200", body: "<html>502 Bad Gateway</html>")

    expect { described_class.access_token }.to raise_error(described_class::RefreshError)
  end
end
