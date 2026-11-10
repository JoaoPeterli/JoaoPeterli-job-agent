module JobSearch
  # O harness interrompeu o run num checkpoint (fronteira de span). Não é
  # PlanningError nem TransientError: nenhuma política de retry interna
  # (planejamento, ferramentas) o captura, então ele sobe até o harness.
  class RunInterrupted < StandardError; end
end
