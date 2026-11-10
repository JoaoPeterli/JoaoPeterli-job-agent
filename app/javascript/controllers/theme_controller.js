import { Controller } from "@hotwired/stimulus"

// Tema claro (padrão), escuro ou do sistema, salvo neste navegador.
// A mesma chave é lida pelo script inline do <head>, que aplica o tema
// antes da primeira pintura.
const STORAGE_KEY = "job-agent-theme"
const media = window.matchMedia("(prefers-color-scheme: dark)")

export default class extends Controller {
  static targets = ["option"]

  connect() {
    this.onSystemChange = () => this.apply()
    media.addEventListener("change", this.onSystemChange)
    this.apply()
  }

  disconnect() {
    media.removeEventListener("change", this.onSystemChange)
  }

  choose({ params: { value } }) {
    try { localStorage.setItem(STORAGE_KEY, value) } catch (_) { /* modo privado: vale só para esta página */ }
    this.current = value
    this.apply()
  }

  apply() {
    const theme = this.current || this.stored()
    const dark = theme === "dark" || (theme === "system" && media.matches)

    document.documentElement.classList.toggle("dark", dark)
    this.optionTargets.forEach((option) => {
      option.setAttribute("aria-checked", String(option.dataset.value === theme))
    })
  }

  stored() {
    try { return localStorage.getItem(STORAGE_KEY) || "light" } catch (_) { return "light" }
  }
}
