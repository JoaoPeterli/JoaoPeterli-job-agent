class RunsController < ApplicationController
  MAX_OBJECTIVE_LENGTH = 2_000
  RECENT_RUNS = 20

  def index
    @filter = valid_filter(params[:status])
    @runs = AgentRun.recent.filtered(@filter).limit(RECENT_RUNS)
    @stats = AgentRun.dashboard_stats
  end

  def new
    # Sem cache (Turbo e botão Voltar): cada formulário nasce com uma chave
    # de idempotência nova. Reaproveitar a chave antiga devolvia o run antigo.
    response.headers["Cache-Control"] = "no-store"
    @form = default_form
  end

  def create
    @form = form_params
    error = validation_error(@form)

    if error
      flash.now[:alert] = error
      return render :new, status: :unprocessable_content
    end

    redirect_to run_path(submit(@form))
  rescue ArgumentError => e
    redirect_to new_run_path, alert: e.message
  end

  def show
    @run = AgentRun.find(params[:id])
    jobs = Array(@run.result["output"]).select { |job| job.is_a?(Hash) }
    keys = jobs.map { |job| JobFeedback.key_for(job) }
    @feedbacks = JobFeedback.where(job_key: keys).index_by(&:job_key)
    @indexed_keys = JobPosting.embedded.where(job_key: keys).pluck(:job_key).to_set
    # Descartadas vão para o fim; o resto, pela nota.
    @jobs = jobs.each_with_index.sort_by do |job, index|
      [ @feedbacks[JobFeedback.key_for(job)]&.verdict == "dislike" ? 1 : 0, -job["score"].to_i, index ]
    end.map(&:first)
    @applications = JobApplication.where(run_id: @run.id).order(score: :desc)
    @audit_trail = JobSearch::AuditTrail.new
    @audit_events = @audit_trail.events(@run.id)
    @audit_check = @audit_trail.verify(@run.id)
  end

  # Novo run com o mesmo objetivo e modo (chave de idempotência nova).
  def redo
    original = AgentRun.find(params[:id])
    run = harness.submit(objective: original.objective, mode: original.mode)
    redirect_to run_path(run), notice: "Busca refeita: este é um run novo."
  end

  def destroy
    harness.delete(params[:id])
    redirect_to runs_path, notice: "Run movido para a lixeira. Dá para restaurar na aba Excluídos."
  rescue ArgumentError => e
    redirect_to run_path(params[:id]), alert: e.message
  end

  def restore
    run = harness.restore(params[:id])
    redirect_to run_path(run), notice: "Run restaurado."
  end

  def cancel
    run = harness.cancel(params[:id])
    notice = run.status == "cancelled" ? "Run cancelado." : "Cancelamento pedido: o run para no próximo checkpoint."
    redirect_to run_path(run), notice: notice
  end

  private

  def valid_filter(value)
    value if AgentRun::FILTERS.key?(value) || value == AgentRun::DELETED_FILTER
  end

  # Mesma chave com outro pedido = formulário antigo reaproveitado (aba
  # duplicada, Voltar): é uma busca nova, então ganha uma chave nova.
  def submit(form)
    harness.submit(objective: form[:objective], mode: form[:mode], idempotency_key: form[:idempotency_key])
  rescue JobSearch::IdempotencyKeyConflict
    harness.submit(objective: form[:objective], mode: form[:mode], idempotency_key: SecureRandom.uuid)
  end

  def harness
    JobSearch::Harness.new
  end

  # A chave de idempotência nasce com o formulário: clique duplo ou
  # reenvio do mesmo formulário viram o mesmo run.
  def default_form
    { objective: "", mode: "agent", idempotency_key: SecureRandom.uuid }
  end

  def form_params
    permitted = params.require(:run).permit(:objective, :mode, :idempotency_key)

    {
      objective: permitted[:objective].to_s.strip,
      mode: permitted[:mode].presence || "agent",
      idempotency_key: permitted[:idempotency_key].presence || SecureRandom.uuid
    }
  end

  def validation_error(form)
    return "Descreva o objetivo da busca." if form[:objective].empty?
    return "O objetivo pode ter no máximo #{MAX_OBJECTIVE_LENGTH} caracteres." if form[:objective].length > MAX_OBJECTIVE_LENGTH

    "Modo inválido." unless AgentRun::MODES.include?(form[:mode])
  end
end
