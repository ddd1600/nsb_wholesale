# frozen_string_literal: true

class ProductCardComponent < ViewComponent::Base
  def initialize(
    product,
    locale: I18n.locale,
    price: product.master.default_price,
    price_range: nil,
    additional_classes: '',
    home_collection: false
  )
    @product = product
    @locale = locale
    @price = price
    # [min, max] Spree::Money from ApplicationHelper#nsb_price_range. Wins over
    # `price` so products with differently priced pack sizes show the range.
    @price_range = price_range
    @additional_classes = additional_classes
    @home_collection = home_collection
  end

  attr_reader :product, :locale, :price, :additional_classes

  def main_image
    product.gallery.images.first
  end

  def display_price
    @display_price ||= @price_range&.first || price&.money
  end

  def display_price_html
    @price_range ? helpers.nsb_price_range_html(@price_range) : display_price.to_html
  end
end
