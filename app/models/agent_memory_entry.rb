class AgentMemoryEntry < ApplicationRecord
  validates :run_id, :objective, :seq, :kind, :content, presence: true
end
