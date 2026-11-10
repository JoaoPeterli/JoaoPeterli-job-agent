require "rails_helper"

RSpec.describe JobSearch::JobSources do
  it "builds the named sources sharing one fetcher" do
    sources = described_class.build(%w[remote_ok github_br])

    expect(sources.map(&:class)).to eq([ JobSearch::JobSources::RemoteOk, JobSearch::JobSources::GithubIssues ])
  end

  it "fails loudly on an unknown or empty source list instead of returning no jobs" do
    expect { described_class.build(%w[linkedin]) }.to raise_error(ArgumentError, /Unknown job source: linkedin/)
    expect { described_class.build([]) }.to raise_error(ArgumentError, /No job sources/)
  end

  it "lists the real sources to credit in the interface" do
    expect(described_class.attributions(%w[remote_ok sample we_work_remotely])).to eq([
      { name: "Remote OK", url: "https://remoteok.com" },
      { name: "We Work Remotely", url: "https://weworkremotely.com" }
    ])
  end
end
