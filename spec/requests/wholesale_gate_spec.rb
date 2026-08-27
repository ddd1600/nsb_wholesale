# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The storefront is half-open: a prospect can see what we sell, so they can
# decide whether applying is worth their time, but wholesale pricing and the
# ability to order require an account.
#
# The price assertions scan rendered HTML for currency rather than checking a
# helper, because that is the failure that matters. Prices reach the page
# through several partials and a Solidus filter facet, and a guard added to
# four of five leaks nothing visible until a competitor reads the fifth.
RSpec.describe "The wholesale gate", type: :request do
  let(:password) { "Password123!" }
  let(:customer) { create(:user, email: "buyer@example.test", password: password) }

  # Any money-shaped string. Deliberately broad: it should catch a price
  # rendered by a partial nobody remembered existed.
  CURRENCY = /\$\s?[0-9][0-9,]*\.[0-9]{2}/

  # Matched against the text a person sees, not the markup. Solidus renders
  # money as separate spans -- <span>$</span><span>42</span><span>.</span>
  # <span>50</span> -- so a regex run over raw HTML silently matches nothing and
  # a leak assertion passes for the wrong reason. This caught exactly that.
  # Tags are removed WITHOUT a separator, so Solidus's split money spans
  # reassemble into "$42.50" rather than "$ 42 . 50". Joining unrelated
  # neighbours is the right trade here: a false positive costs one look, a false
  # negative publishes the wholesale sheet.
  def visible_text
    response.body.gsub(/<[^>]*>/, "").gsub("&nbsp;", " ")
  end

  before { create(:product, name: "Test Tincture", price: 42.5) }

  describe "a visitor who is not signed in" do
    it "is sent to the welcome page from the root, not the catalog" do
      get "/"

      expect(response).to redirect_to(welcome_path)
    end

    it "can reach the welcome page and both ways in from it" do
      get "/welcome"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(claim_path)
      expect(response.body).to include(apply_path)
    end

    it "can browse the catalog" do
      get "/products"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Test Tincture")
    end

    it "sees no price anywhere on the catalog listing" do
      get "/products"

      expect(visible_text).not_to match(CURRENCY)
    end

    it "sees no price on a product page" do
      get "/products/#{Spree::Product.first.slug}"

      expect(visible_text).not_to match(CURRENCY)
    end

    # Regression: the catalog hid every price while Solidus's own price-range
    # facet printed the wholesale bands in the sidebar next to it.
    it "is not shown the price-range filter, whose labels are also prices" do
      get "/products"

      expect(visible_text).not_to include("Under $")
    end

    it "is invited to sign in instead of being shown an add-to-cart button" do
      get "/products/#{Spree::Product.first.slug}"

      expect(response.body).to include(I18n.t("nsb.pricing.sign_in_to_order"))
    end

    it "cannot reach checkout" do
      get "/checkout"

      expect(response).to redirect_to(welcome_path)
    end

    # The cart page itself is deliberately NOT gated: with adding to it blocked,
    # an anonymous cart is necessarily empty, and gating it would have meant
    # gating orders too -- which would break the token order links customers
    # follow from their own confirmation emails.
    it "can reach the cart, but it is empty" do
      get "/cart"

      expect(response).to have_http_status(:ok)
      expect(visible_text).not_to match(CURRENCY)
    end

    it "cannot add to the cart" do
      variant = Spree::Product.first.master

      post "/cart_line_items", params: { variant_id: variant.id, quantity: 1 }

      expect(response).to redirect_to(welcome_path)
      expect(Spree::LineItem.count).to eq(0)
    end
  end

  describe "a signed-in wholesale customer" do
    before { sign_in customer }

    it "gets the catalog at the root rather than the welcome page" do
      get "/"

      expect(response).to have_http_status(:ok)
    end

    it "sees prices on the catalog listing" do
      get "/products"

      expect(visible_text).to match(CURRENCY)
    end

    it "sees a price on the product page" do
      get "/products/#{Spree::Product.first.slug}"

      expect(visible_text).to match(CURRENCY)
    end

    it "can reach the cart" do
      get "/cart"

      expect(response).to have_http_status(:ok)
    end
  end
end
