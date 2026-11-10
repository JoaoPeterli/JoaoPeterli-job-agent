require "rails_helper"

RSpec.describe RunsHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  describe "#job_title_link" do
    it "links to the original posting in a new tab" do
      html = helper.job_title_link("title" => "Ruby Dev", "url" => "https://remoteok.com/remote-jobs/1")

      expect(html).to include('href="https://remoteok.com/remote-jobs/1"', 'target="_blank"', 'rel="noopener"', "Ruby Dev")
    end

    it "never renders a non-http link coming from a source" do
      html = helper.job_title_link("title" => "<b>x</b>", "url" => "javascript:alert(1)")

      expect(html).not_to include("href", "<b>")
      expect(html).to include("&lt;b&gt;x&lt;/b&gt;")
    end
  end

  describe "#job_published" do
    it "shows a short relative time in Portuguese" do
      travel_to Time.zone.parse("2026-11-10 12:00") do
        expect(helper.job_published("published_at" => "2026-11-10T11:30:00-03:00")).to eq("há 30 min")
        expect(helper.job_published("published_at" => "2026-11-10T07:00:00-03:00")).to eq("há 5 h")
        expect(helper.job_published("published_at" => "2026-11-09T10:00:00-03:00")).to eq("há 1 dia")
        expect(helper.job_published("published_at" => "2026-11-01T12:00:00-03:00")).to eq("há 9 dias")
        expect(helper.job_published("published_at" => nil)).to be_nil
        expect(helper.job_published("published_at" => "garbage")).to be_nil
      end
    end
  end
end
