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
    "failed" => "Com problema",
    "deleted" => "Excluídos"
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

  # Link para o anúncio original. A URL vem de fonte externa: só http(s)
  # passa (de novo aqui, mesmo já validada na coleta).
  def job_title_link(job)
    url = JobSearch::JobListing.safe_url(job["url"])
    return tag.span(job["title"]) unless url

    link_to(url, target: "_blank", rel: "noopener", class: "row-link") do
      safe_join([ job["title"], icon("external-link", class_name: "row-link__icon") ])
    end
  end

  def job_published(job)
    time = Time.zone.parse(job["published_at"].to_s) if job["published_at"].present?
    time && "há #{short_distance(time)}"
  rescue ArgumentError
    nil
  end

  def short_distance(time)
    seconds = [ Time.current - time, 0 ].max

    if seconds < 1.hour then "#{(seconds / 60).floor.clamp(1, 59)} min"
    elsif seconds < 1.day then "#{(seconds / 3600).floor} h"
    elsif seconds < 2.days then "1 dia"
    else "#{(seconds / 86_400).floor} dias"
    end
  end

  # Botões 👍/👎 de uma vaga. O ativo fica marcado; clicar de novo desfaz.
  def feedback_buttons(run, job_key, feedback)
    buttons = { "like" => [ "thumbs-up", "Gostei" ], "dislike" => [ "thumbs-down", "Descartar" ] }.map do |verdict, (icon_name, label)|
      active = feedback&.verdict == verdict
      button_to(job_feedbacks_path, params: { run_id: run.id, job_key: job_key, verdict: verdict },
                class: "icon-button feedback-button feedback-button--#{verdict}",
                aria: { pressed: active, label: active ? "#{label} (desfazer)" : label },
                title: active ? "#{label} (clique para desfazer)" : label, form_class: "feedback-form") do
        icon(icon_name)
      end
    end

    tag.div(safe_join(buttons), class: "feedback")
  end

  # Distância de cosseno (0 a 2) -> similaridade em % (100% = mesmo sentido).
  def similarity_percent(distance)
    "#{((1 - distance.to_f) * 100).round.clamp(0, 100)}%"
  end

  APPLICATION_STATUSES = {
    "proposed" => [ "Esperando você", "warning" ],
    "approved" => [ "Aprovada, registrando…", "info" ],
    "applied" => [ "Registrada", "success" ],
    "rejected" => [ "Rejeitada", "neutral" ],
    "failed" => [ "Falhou", "danger" ]
  }.freeze

  def application_status_badge(status)
    label, tone = APPLICATION_STATUSES.fetch(status, [ status, "neutral" ])
    tag.span(label, class: "badge badge--#{tone}")
  end

  def score_width(score)
    "width: #{score.to_i.clamp(0, 100)}%"
  end
end
