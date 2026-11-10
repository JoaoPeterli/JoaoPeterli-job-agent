require "rails_helper"

RSpec.describe JobApplication do
  def application(**attributes)
    described_class.create!({ run_id: SecureRandom.uuid, job_key: "rails|acme", title: "Rails Dev", message: "Rascunho" }.merge(attributes))
  end

  it "approves the exact action (job + message), recording who and when" do
    app = application
    app.approve!(message: "  Mensagem revisada  ", by: "joao")

    expect(app).to have_attributes(status: "approved", message: "Mensagem revisada", decided_by: "joao")
    expect(app.approval_fingerprint).to eq(app.action_fingerprint)
    expect(app.approved_for?(app.action_fingerprint)).to be(true)
  end

  it "stops matching the approval when the message changes afterwards" do
    app = application
    app.approve!(message: "Aprovada", by: "joao")
    app.update_columns(message: "Texto trocado depois")

    expect(app.approved_for?(app.reload.action_fingerprint)).to be(false)
  end

  it "decides only once" do
    app = application
    app.reject!(by: "joao")

    expect(app.status).to eq("rejected")
    expect { app.approve!(message: "x", by: "joao") }.to raise_error(ArgumentError, /já foi decidida/)
  end

  it "does not approve an empty message" do
    expect { application.approve!(message: "  ", by: "joao") }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
