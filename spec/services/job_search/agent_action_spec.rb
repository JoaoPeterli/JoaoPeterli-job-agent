require "rails_helper"

RSpec.describe JobSearch::AgentAction do
  describe "#initialize" do
    it "stores the tool and arguments" do
      action = described_class.new(
        tool: :search_jobs,
        arguments: {
          technology: "Ruby",
          remote: true
        }
      )

      expect(action.tool).to eq(:search_jobs)

      expect(action.arguments).to eq(
        {
          technology: "Ruby",
          remote: true
        }
      )
    end
  end
end
