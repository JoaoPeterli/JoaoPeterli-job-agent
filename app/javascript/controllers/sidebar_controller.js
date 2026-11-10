import { Controller } from "@hotwired/stimulus"

// No celular a sidebar é uma gaveta sobreposta; no desktop ela é fixa
// e este controller não faz nada visível (o CSS ignora o estado).
export default class extends Controller {
  static targets = ["panel", "trigger"]

  open() {
    this.element.classList.add("app--sidebar-open")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.panelTarget.querySelector("a, button")?.focus()
  }

  close() {
    if (!this.element.classList.contains("app--sidebar-open")) return

    this.element.classList.remove("app--sidebar-open")
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.focus()
  }

  // Ao navegar, a gaveta fecha sozinha (a página nova não fica escondida atrás dela).
  disconnect() {
    this.element.classList.remove("app--sidebar-open")
  }
}
