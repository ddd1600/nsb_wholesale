# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Square's single-use card token arrives as
  # payment_source[<id>][gateway_payment_profile_id]. It matches none of the
  # patterns above -- not "token", not "secret" -- so without this it lands in
  # the logs in clear text. Single-use and short-lived, but it is card-adjacent
  # data and has no business being written down.
  :gateway_payment_profile_id,
  # Square/ShipStation/Gmail credentials, if one ever reaches a param.
  :api_key, :access_token, :refresh_token, :client_secret
]
