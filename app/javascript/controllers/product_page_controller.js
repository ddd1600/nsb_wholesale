import { Controller } from "@hotwired/stimulus"

// Drives the product page: the option buttons (e.g. Pack Size), which variant
// goes into the cart, the price in the header and on the Add To Cart button,
// and which photo is shown.
//
// Replaces the starter frontend's product.js and product_selection_component.js.
// Those never updated the Add To Cart price, and only ran on DOMContentLoaded,
// which Turbo does not fire when a customer clicks through to a product.
//
// Each option type is a radio group. The chosen combination is matched against
// the hidden variant radios' data-option-value-ids, which is what the form
// actually submits as variant_id.
export default class extends Controller {
  static targets = ["option", "variant", "price", "ctaPrice", "quantity",
                    "submit", "mainImage", "variantThumbnail"]
  static values = { currency: String }

  connect() {
    this.update()
  }

  update() {
    if (this.variantTargets.length === 0) return

    this.optionTargets.forEach((input) => {
      if (input.checked) {
        const label = document.getElementById(`selected-${input.name}`)
        if (label) label.textContent = input.dataset.presentation
      }
    })

    const variant = this.matchingVariant()
    if (this.hasSubmitTarget) this.submitTarget.disabled = !variant
    if (!variant) {
      this.ctaPriceTargets.forEach((el) => { el.textContent = "not available" })
      return
    }

    variant.checked = true
    this.showPrice(variant)
    this.showVariantImages(variant.value)
  }

  showThumbnail(event) {
    event.preventDefault()
    if (this.hasMainImageTarget) this.mainImageTarget.src = event.currentTarget.href
  }

  // private

  matchingVariant() {
    const groups = [...new Set(this.optionTargets.map((input) => input.name))]
    const chosen = groups.map((name) => {
      const checked = this.optionTargets.find((input) => input.name === name && input.checked)
      return checked ? parseInt(checked.value, 10) : null
    })
    if (groups.length === 0) return this.variantTargets[0]

    return this.variantTargets.find((radio) =>
      JSON.stringify(JSON.parse(radio.dataset.optionValueIds)) === JSON.stringify(chosen)
    )
  }

  showPrice(variant) {
    const unit = parseFloat(variant.dataset.priceAmount)
    if (Number.isNaN(unit)) return

    const quantity = this.hasQuantityTarget ? Math.max(parseInt(this.quantityTarget.value, 10) || 1, 1) : 1
    this.priceTargets.forEach((el) => { el.textContent = this.format(unit) })
    this.ctaPriceTargets.forEach((el) => { el.textContent = this.format(unit * quantity) })
  }

  // Show the chosen variant's own photos (e.g. a 10ct bag), and lead with the
  // first of them. A variant with no photos of its own leaves the product's
  // shared photos in place rather than blanking the page.
  showVariantImages(variantId) {
    let first = null
    this.variantThumbnailTargets.forEach((li) => {
      const mine = li.dataset.variantId === variantId
      li.hidden = !mine
      if (mine && !first) first = li.querySelector("a")
    })
    if (first && this.hasMainImageTarget) this.mainImageTarget.src = first.href
  }

  format(amount) {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: this.currencyValue || "USD" }).format(amount)
  }
}
