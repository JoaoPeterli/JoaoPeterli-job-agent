require "rails_helper"

RSpec.describe JobSearch::EmbeddingClient do
  let(:embeddings_api) { double("EmbeddingsAPI") }
  let(:openai) { double("OpenAI::Client", embeddings: embeddings_api) }
  let(:event_logger) { instance_double(JobSearch::Observability::EventLogger, info: nil) }
  let(:client) { described_class.new(client: openai, event_logger: event_logger) }

  def response(vectors)
    data = vectors.each_with_index.map { |vector, index| double(embedding: vector, index: index) }.reverse
    double(data: data, usage: double(total_tokens: 7))
  end

  it "returns one vector per text, in order, and logs the usage" do
    allow(embeddings_api).to receive(:create).and_return(response([ [ 0.1 ], [ 0.2 ] ]))

    expect(client.embed([ "a", "b" ])).to eq([ [ 0.1 ], [ 0.2 ] ])
    expect(embeddings_api).to have_received(:create).with(model: "text-embedding-3-small", input: [ "a", "b" ])
    expect(event_logger).to have_received(:info).with(hash_including(event: "embedding.call", inputs: 2, total_tokens: 7))
  end

  it "sends big inputs in batches and never an empty string" do
    allow(embeddings_api).to receive(:create) { |input:, **| response(input.map { [ 1.0 ] }) }

    expect(client.embed(Array.new(150) { "" }).size).to eq(150)
    expect(embeddings_api).to have_received(:create).twice
    expect(embeddings_api).to have_received(:create).with(hash_including(input: array_including("-"))).at_least(:once)
  end

  it "turns provider errors and short answers into EmbeddingError" do
    allow(embeddings_api).to receive(:create)
      .and_raise(OpenAI::Errors::APIConnectionError.new(url: URI("https://api.openai.com")))
    expect { client.embed([ "a" ]) }.to raise_error(JobSearch::EmbeddingError, /APIConnectionError/)

    allow(embeddings_api).to receive(:create).and_return(response([]))
    expect { client.embed([ "a" ]) }.to raise_error(JobSearch::EmbeddingError, /expected 1 embeddings/)
  end
end
