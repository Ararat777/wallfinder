require 'yaml'
require_relative 'database'

$pairs = YAML.load_file('./pairs.yml')

class Wall < ActiveRecord::Base
  enum status: { created: 0, in_progress: 1, finish: 2 }
  enum side: { bid: 0, ask: 1 }

  has_many :orders, -> { order(created_at: :desc) }
  belongs_to :book_order
end

class Order < ActiveRecord::Base
  belongs_to :wall
end

class BookOrder < ActiveRecord::Base
  enum status: { normal: 0, wall: 1 }

  has_many :walls

  before_save :check_wall

  private

  def check_wall
    vol = price * quantity
    if vol >= $pairs[symbol]["volume"]
      return if wall?

      self[:status] = :wall
      self[:status_changed_at] = Time.now.utc
    else
      return if normal?

      self[:status] = :normal
      self[:status_changed_at] = Time.now.utc
    end
  end
end