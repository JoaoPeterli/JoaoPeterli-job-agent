require "rails_helper"

RSpec.describe "Meu perfil", type: :request do
  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("joao", "s3cret") } }

  around do |example|
    previous = %w[JOB_AGENT_WEB_USER JOB_AGENT_WEB_PASSWORD].to_h { |key| [ key, ENV[key] ] }
    ENV["JOB_AGENT_WEB_USER"] = "joao"
    ENV["JOB_AGENT_WEB_PASSWORD"] = "s3cret"
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it "shows the default profile before one is saved" do
    get edit_profile_path, headers: auth

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Meu perfil", 'value="Ruby, Rails, AWS"', "Como a nota é calculada")
  end

  it "saves the profile used by the next searches" do
    patch profile_path, headers: auth, params: {
      candidate_profile: { skills_text: "Elixir, Phoenix, PostgreSQL", seniority: "pleno", remote: "0", location: "Recife" }
    }

    expect(response).to redirect_to(edit_profile_path)
    expect(CandidateProfile.count).to eq(1)
    expect(JobSearch::CandidateProfileTool.new.call)
      .to eq(skills: %w[Elixir Phoenix PostgreSQL], seniority: "pleno", remote: false, location: "Recife")

    patch profile_path, headers: auth, params: { candidate_profile: { skills_text: "Elixir", seniority: "senior", remote: "1" } }
    expect(CandidateProfile.count).to eq(1)
  end

  it "shows the errors and keeps the input when invalid" do
    patch profile_path, headers: auth, params: { candidate_profile: { skills_text: " , ", seniority: "senior" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("pelo menos uma skill")
    expect(CandidateProfile.count).to eq(0)
  end

  it "requires authentication" do
    get edit_profile_path

    expect(response).to have_http_status(:unauthorized)
  end
end
