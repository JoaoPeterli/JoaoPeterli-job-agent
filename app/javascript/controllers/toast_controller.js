import { Controller } from "@hotwired/stimulus"

// Aviso flutuante que some sozinho. Erros ficam mais tempo na tela.
export default class extends Controller {
  connect() {
    const delay = this.element.getAttribute("role") === "alert" ? 8000 : 4000
    this.timer = setTimeout(() => this.dismiss(), delay)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.classList.add("toast--leaving")
    setTimeout(() => this.element.remove(), 200)
  }
}
