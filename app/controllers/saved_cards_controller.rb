# frozen_string_literal: true

# Lets a customer remove a card they saved with Square, from My Account.
#
# Square is told first. If Square can't confirm (network trouble, an outage),
# the card stays and the customer is asked to try again -- removing it only on
# our side would leave Square still holding a card the customer believes is
# gone.
class SavedCardsController < StoreController
  def destroy
    user = spree_current_user
    return redirect_to(login_path) unless user

    # Scoped to the signed-in customer's own wallet: an id belonging to someone
    # else is simply not found.
    wallet_payment_source = user.wallet.find(params[:id])
    raise ActiveRecord::RecordNotFound unless wallet_payment_source

    card = wallet_payment_source.payment_source

    if Nsb::Square::CardsOnFile.new.disable(card)
      user.wallet.remove(card)
      flash[:notice] = t("nsb.saved_cards.removed")
    else
      flash[:error] = t("nsb.saved_cards.remove_failed")
    end

    redirect_to account_path
  rescue ::Square::Errors::ApiError, Nsb::Square::Configuration::MissingCredentials => error
    Rails.logger.error("[square] could not disable saved card #{card&.id}: #{error.class}: #{error.message.to_s.first(300)}")
    flash[:error] = t("nsb.saved_cards.remove_failed")
    redirect_to account_path
  end
end
