import { Controller } from "@hotwired/stimulus"

// Wholesale application form: formats the phone number as it is typed, and
// replaces the browser's one-at-a-time "please fill in this field" bubble with a
// single summary of everything that is missing.
//
// The form carries novalidate so this controller owns the message. Validation
// itself is still the server's: this only saves a round trip and tells the
// applicant all of it at once.
export default class extends Controller {
  static targets = ["form", "field", "phone", "missingSummary"]

  connect() {
    // Someone arriving with a phone already filled in -- a back button, a
    // re-render after a server error -- should see it formatted too.
    this.phoneTargets.forEach((input) => this.formatPhone(input))
  }

  // (843) 555-1234, built from whatever digits are present so far.
  //
  // Only ever reformats while the caret is at the end. Editing the middle of a
  // number and having the caret jump to the end is worse than seeing the
  // punctuation a moment late.
  phoneInput(event) {
    const input = event.target
    if (input.selectionStart !== input.value.length) return

    this.formatPhone(input)
  }

  formatPhone(input) {
    let digits = input.value.replace(/\D/g, "")
    if (digits.length === 11 && digits.startsWith("1")) digits = digits.slice(1)
    digits = digits.slice(0, 10)
    if (digits.length === 0) return

    let formatted = `(${digits.slice(0, 3)}`
    if (digits.length >= 4) formatted += `) ${digits.slice(3, 6)}`
    if (digits.length >= 7) formatted += `-${digits.slice(6, 10)}`
    // Mid-typing, close the bracket only once the area code is complete so the
    // caret does not sit outside it.
    else if (digits.length === 3) formatted += ") "

    input.value = formatted
  }

  submit(event) {
    const missing = this.fieldTargets.filter(
      (field) => field.required && field.value.trim() === ""
    )

    if (missing.length === 0) {
      this.hideSummary()
      return
    }

    event.preventDefault()
    this.showSummary(missing)
    missing[0].focus()
  }

  showSummary(missing) {
    const summary = this.missingSummaryTarget
    const names = missing.map((field) => this.labelFor(field))

    summary.innerHTML = ""
    const heading = document.createElement("p")
    heading.className = "font-sans-md mb-2"
    heading.textContent =
      names.length === 1
        ? "One required field is still blank:"
        : `${names.length} required fields are still blank:`
    summary.appendChild(heading)

    const list = document.createElement("ul")
    names.forEach((name) => {
      const item = document.createElement("li")
      item.textContent = name
      list.appendChild(item)
    })
    summary.appendChild(list)

    summary.classList.remove("hidden")
    summary.focus()
    summary.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  hideSummary() {
    if (!this.hasMissingSummaryTarget) return
    this.missingSummaryTarget.classList.add("hidden")
  }

  // The visible label, minus the asterisk, so the summary reads the way the form
  // does rather than naming database columns.
  labelFor(field) {
    const label = this.element.querySelector(`label[for="${field.id}"]`)
    return (label ? label.textContent : field.name).replace(/\s*\*\s*$/, "").trim()
  }
}
