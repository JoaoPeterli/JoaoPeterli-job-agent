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

  def status_badge(status)
    tag.span(STATUS_LABELS.fetch(status, status), class: "badge badge--#{status}")
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
