module RunsHelper
  STATUS_LABELS = {
    "queued" => "Na fila",
    "running" => "Executando",
    "completed" => "Concluído",
    "stopped_early" => "Sem resultados",
    "failed" => "Falhou",
    "cancelled" => "Cancelado"
  }.freeze

  MODE_LABELS = {
    "agent" => "Agente único",
    "pipeline" => "Pipeline",
    "supervisor" => "Supervisor"
  }.freeze

  MODE_DESCRIPTIONS = {
    "agent" => "Um agente planeja e executa tudo. Mais barato.",
    "pipeline" => "Pesquisador → analista, em ordem fixa.",
    "supervisor" => "Um LLM divide o objetivo e delega aos especialistas."
  }.freeze

  MODE_ICONS = {
    "agent" => "bot",
    "pipeline" => "workflow",
    "supervisor" => "users"
  }.freeze

  FILTER_LABELS = {
    nil => "Todos",
    "active" => "Em andamento",
    "completed" => "Concluídos",
    "failed" => "Com problema"
  }.freeze

  # Tom visual de cada status (cores do tema em application.css).
  STATUS_TONES = {
    "queued" => "neutral",
    "running" => "info",
    "completed" => "success",
    "stopped_early" => "warning",
    "failed" => "danger",
    "cancelled" => "neutral"
  }.freeze

  def status_badge(status)
    tone = STATUS_TONES.fetch(status, "neutral")

    tag.span(class: "badge badge--#{tone}", data: { status: status }) do
      safe_join([ tag.span(class: "badge__dot", "aria-hidden": "true"), STATUS_LABELS.fetch(status, status) ])
    end
  end

  def mode_icon(mode, class_name: nil)
    icon(MODE_ICONS.fetch(mode, "bot"), class_name: class_name)
  end

  def format_percent(value)
    value.nil? ? "—" : "#{value}%"
  end

  def mode_label(mode)
    MODE_LABELS.fetch(mode, mode)
  end

  def run_active?(run)
    !run.finished?
  end

  def format_duration(ms)
    return "—" if ms.nil?

    ms.to_f >= 1_000 ? "#{(ms.to_f / 1_000).round(1)} s" : "#{ms.to_f.round} ms"
  end

  def format_cost(cost)
    cost.nil? ? "sem preço" : "US$ #{format('%.4f', cost)}"
  end

  def format_count(value)
    value.nil? ? "—" : number_with_delimiter(value, delimiter: ".")
  end

  def score_width(score)
    "width: #{score.to_i.clamp(0, 100)}%"
  end
end
