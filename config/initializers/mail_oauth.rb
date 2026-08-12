# frozen_string_literal: true

require_relative "../mail_delivery"

# Registers the interceptor that swaps a fresh OAuth access token into the SMTP
# password before every delivery. See config/mail_delivery.rb for why the token
# cannot simply be part of smtp_settings.
#
# MailDelivery::TokenInterceptor is a plain (non-autoloaded) constant, so it is
# safe to reference here and registering it once cannot leave a stale copy
# behind on reload.
if MailDelivery.configured?
  ActiveSupport.on_load(:action_mailer) do
    register_interceptor(MailDelivery::TokenInterceptor)
  end
end
