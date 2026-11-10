class ApplicationController < ActionController::Base
  # Cada envio de objetivo gasta tokens da OpenAI: a interface nunca fica
  # aberta. Sem credenciais configuradas, ela se recusa a funcionar
  # (fail closed) em vez de liberar acesso.
  before_action :authenticate!
  helper_method :current_user_name

  private

  def current_user_name
    ENV["JOB_AGENT_WEB_USER"].to_s
  end

  def authenticate!
    user = ENV["JOB_AGENT_WEB_USER"].to_s
    password = ENV["JOB_AGENT_WEB_PASSWORD"].to_s

    if user.empty? || password.empty?
      return render plain: "Interface desativada: defina JOB_AGENT_WEB_USER e JOB_AGENT_WEB_PASSWORD.",
                    status: :service_unavailable
    end

    authenticate_or_request_with_http_basic("job_agent") do |given_user, given_password|
      ActiveSupport::SecurityUtils.secure_compare(given_user, user) &
        ActiveSupport::SecurityUtils.secure_compare(given_password, password)
    end
  end
end
