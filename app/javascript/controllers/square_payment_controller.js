import { Controller } from "@hotwired/stimulus"

// Drives Square's Web Payments SDK on the checkout payment step.
//
// The card fields live inside an iframe Square controls, so card numbers never
// touch this page's DOM or our server. On submit we exchange them for a
// single-use token and post only that.
//
// Submission rules that matter:
//   * The form is NOT allowed to submit until tokenisation succeeds. If Square
//     rejects the card details we stop the submit and show the message, so the
//     server never sees a payment attempt with no token.
//   * The submit button is disabled while tokenising, so an impatient customer
//     cannot fire a second attempt. (The server-side idempotency key is the real
//     protection; this is just the polite half.)
export default class extends Controller {
  static targets = ["card", "token", "lastDigits", "expMonth", "expYear", "ccType", "error"]
  static values = { applicationId: String, locationId: String, sdkUrl: String }

  async connect() {
    this.submitting = false
    this.form = this.element.closest("form")

    try {
      await this.loadSdk()
      this.payments = window.Square.payments(this.applicationIdValue, this.locationIdValue)
      this.card = await this.payments.card()
      await this.card.attach(this.cardTarget)
    } catch (error) {
      this.showError("Card payment is unavailable right now. Please contact us to place your order.")
      console.error("[square] initialisation failed", error)
      return
    }

    this.onSubmit = this.handleSubmit.bind(this)
    this.form?.addEventListener("submit", this.onSubmit)
  }

  disconnect() {
    if (this.form && this.onSubmit) this.form.removeEventListener("submit", this.onSubmit)
    if (this.card) this.card.destroy()
  }

  // Loads the SDK once, even if several payment methods are on the page.
  loadSdk() {
    if (window.Square) return Promise.resolve()
    if (window.__squareSdkPromise) return window.__squareSdkPromise

    window.__squareSdkPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = this.sdkUrlValue
      script.onload = resolve
      script.onerror = () => reject(new Error("Failed to load Square Web Payments SDK"))
      document.head.appendChild(script)
    })
    return window.__squareSdkPromise
  }

  async handleSubmit(event) {
    // Only intervene when Square is the selected payment method.
    if (!this.isSelected()) return
    // Already tokenised and re-submitting programmatically: let it through.
    if (this.tokenTarget.value) return

    event.preventDefault()
    if (this.submitting) return
    this.submitting = true
    this.setSubmitDisabled(true)
    this.clearError()

    try {
      const result = await this.card.tokenize()

      if (result.status !== "OK") {
        // Square rejected the details. Stay on the page; never submit a payment
        // attempt with no token.
        const detail = result.errors?.map((e) => e.message).join(" ")
        this.showError(detail || "Please check your card details and try again.")
        return
      }

      this.tokenTarget.value = result.token
      const card = result.details?.card
      if (card) {
        this.lastDigitsTarget.value = card.last4 || ""
        this.expMonthTarget.value = card.expMonth || ""
        this.expYearTarget.value = card.expYear || ""
        this.ccTypeTarget.value = (card.brand || "").toLowerCase()
      }

      this.form.submit()
    } catch (error) {
      console.error("[square] tokenisation failed", error)
      this.showError("We couldn't process that card. Please try again, or contact us.")
    } finally {
      this.submitting = false
      // Re-enable only if we did not submit, so the customer can correct and retry.
      if (!this.tokenTarget.value) this.setSubmitDisabled(false)
    }
  }

  isSelected() {
    const fieldset = this.element.closest("fieldset")
    const radio = fieldset?.parentElement?.querySelector("input[type=radio]")
    return radio ? radio.checked : true
  }

  setSubmitDisabled(disabled) {
    const button = this.form?.querySelector("button[name=commit], input[type=submit]")
    if (button) button.disabled = disabled
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }
}
