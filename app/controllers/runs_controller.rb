class RunsController < ApplicationController
  MAX_OBJECTIVE_LENGTH = 2_000
  RECENT_RUNS = 20

  def index
    @filter = AgentRun::FILTERS.key?(params[:status]) ? params[:status] : nil
    @runs = AgentRun.recent.filtered(@filter).limit(RECENT_RUNS)
    @stats = AgentRun.dashboard_stats
  end

  def new
    @form = default_form
  end

  def create
    @form = form_params
    error = validation_error(@form)

    if error
      flash.now[:alert] = error
      return render :new, status: :unprocessable_content
    end

    run = harness.submit(objective: @form[:objective], mode: @form[:mode], idempotency_key: @form[:idempotency_key])
    redirect_to run_path(run)
  rescue ArgumentError => e
    redirect_to new_run_path, alert: e.message
  end

  def show
    @run = AgentRun.find(params[:id])
    @jobs = Array(@run.result["output"]).select { |job| job.is_a?(Hash) }.sort_by { |job| -job["score"].to_i }
    @audit_trail = JobSearch::AuditTrail.new
    @audit_events = @audit_trail.events(@run.id)
    @audit_check = @audit_trail.verify(@run.id)
  end

  def cancel
    run = harness.cancel(params[:id])
    notice = run.status == "cancelled" ? "Run cancelado." : "Cancelamento pedido: o run para no próximo checkpoint."
    redirect_to run_path(run), notice: notice
  end

  private

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
