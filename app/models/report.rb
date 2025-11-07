class Report < ApplicationRecord
  validates :date, presence: true

  scope :today, -> { where(date: Date.today) }
end
