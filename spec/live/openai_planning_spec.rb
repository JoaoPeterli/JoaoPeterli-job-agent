require "rails_helper"

# Teste contra a API real da OpenAI. Gasta tokens e depende de rede,
# por isso fica fora da suíte padrão. Para rodar:
#
#   LIVE_LLM=1 OPENAI_API_KEY=... bundle exec rspec spec/live
#
# Não verifica o plano exato (o LLM não é determinístico), e sim o
# contrato: a resposta passa por todas as validações e vira um Plan
# executável com as ferramentas reais.
RSpec.describe "OpenAI planning (live)", :live_llm do
  it "produces a valid executable plan for a typical objective" do
    container = JobSearch::Container.new
    agent = container.agent(objective: "Find remote Ruby on Rails jobs that match my profile")

    state = agent.run

    expect(state.status).to eq(:completed)
    expect(state.actions.map(&:tool)).to include(:search_jobs)
  end
end
