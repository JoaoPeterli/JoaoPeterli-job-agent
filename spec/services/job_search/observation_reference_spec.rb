require "rails_helper"

RSpec.describe JobSearch::ObservationReference do
  describe "#step_name" do
    it "returns the referenced step" do
      reference = described_class.new(
        step_name: :search
      )

      expect(reference.step_name).to eq(:search)
    end
  end
end
