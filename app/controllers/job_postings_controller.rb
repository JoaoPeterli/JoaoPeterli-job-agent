# Histórico de vagas (todas as vistas em algum run), com busca semântica
# (pgvector) e "vagas parecidas com esta".
class JobPostingsController < ApplicationController
  MAX_QUERY_LENGTH = 200
  RESULTS = 20

  def index
    @query = params[:q].to_s.squish.first(MAX_QUERY_LENGTH)
    @total = JobPosting.count

    @postings =
      if @query.present? && rag_enabled?
        semantic_search(@query)
      else
        JobPosting.order(last_seen_at: :desc).limit(RESULTS)
      end
  end

  def similar
    @posting = JobPosting.find_by!(job_key: params.require(:key))
    @postings = rag_enabled? ? job_index.similar(@posting, limit: RESULTS) : []
  end

  private

  def semantic_search(query)
    job_index.search(query, limit: RESULTS)
  rescue JobSearch::EmbeddingError => error
    flash.now[:alert] = "A busca semântica está indisponível agora (#{error.message}). Mostrando as vagas mais recentes."
    JobPosting.order(last_seen_at: :desc).limit(RESULTS)
  end

  def rag_enabled?
    Rails.configuration.x.rag_enabled
  end

  def job_index
    JobSearch::JobIndex.default
  end
end
