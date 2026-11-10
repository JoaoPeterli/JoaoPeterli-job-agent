class JobSearchOperation < ApplicationRecord
  validates :operation_key, presence: true

  validates :status,
  inclusion: {
    in: %w[leased released uncertain completed needs_review]
  }
end
