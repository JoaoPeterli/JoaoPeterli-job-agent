import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Enquanto houver run ativo, recarrega a página a cada `interval` ms.
// Com turbo_refreshes_with :morph, só o que mudou é trocado no DOM e a
// rolagem é preservada. Para sozinho quando nada mais está ativo.
export default class extends Controller {
  static values = { active: Boolean, interval: { type: Number, default: 2000 } }

  connect() {
    if (this.activeValue) {
      this.timer = setTimeout(() => Turbo.visit(window.location.href, { action: "replace" }), this.intervalValue)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
