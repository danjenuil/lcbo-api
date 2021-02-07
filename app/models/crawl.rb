class Crawl < ApplicationRecord
  include RedisAbuse::Model

  class StateError < StandardError; end

  SERIALIZED_FIELDS = [
    :store_ids,
    :product_ids,
    :added_product_ids,
    :added_store_ids,
    :removed_product_ids,
    :removed_store_ids]

  STATES = %w[
    init
    running
    paused
    cancelled
    finished
  ]

  list :crawled_store_ids,   :integer
  list :crawled_product_ids, :integer

  after_save :check_if_cancelled

  validates :state, inclusion: { in: STATES }

  SERIALIZED_FIELDS.each do |f|
    serialize(f)
  end

  scope :is, ->(*states) { where(state: states.map(&:to_s)) }

  belongs_to :crawl_event, optional: true
  has_many :crawl_events

  def self.latest
    order(id: :desc).first
  end

  def self.any_active?
    is(:init, :running, :paused).count != 0
  end

  def self.init
    raise 'Crawl is already running' if any_active?
    create(
      state: 'init',
      store_ids: [],
      product_ids: [],
      added_product_ids: [],
      added_store_ids: [],
      removed_product_ids: [],
      removed_store_ids: []
    )
  end

  def previous
    @previous ||= begin
      Crawl.
        where("id != ? AND state = 'finished'", id).
        order(id: :desc).
        first
    end
  end

  def state=(val)
    write_attribute :state, val ? val.to_s : val
  end

  def diff!
    self.store_ids   = crawled_store_ids.all
    self.product_ids = crawled_product_ids.all

    if previous
      self.added_product_ids   = (product_ids - previous.product_ids)
      self.removed_product_ids = (previous.product_ids - product_ids)
      self.added_store_ids     = (store_ids - previous.store_ids)
      self.removed_store_ids   = (previous.store_ids - store_ids)
    else
      self.added_product_ids   = []
      self.removed_product_ids = []
      self.added_store_ids     = []
      self.removed_store_ids   = []
    end

    save!
  end

  def is?(*states)
    states.map(&:to_s).include?(self.state)
  end

  def is_locked?
    is? :finished, :cancelled
  end

  def is_active?
    is? :init, :running, :paused
  end

  def log(message, level = :info, payload = {})
    verify_unlocked!

    ce = CrawlEvent.create!(
      crawl_id:   id,
      level:      level.to_s,
      message:    message.to_s,
      payload:    JSON.dump(payload))

    self.crawl_event_id = ce.id

    save!
  end

  protected

  def check_if_cancelled
    return true unless state == 'cancelled'
    # AdminMailer.crawl_cancelled_message(self.id).deliver
  end

  def verify_unlocked!
    raise StateError, "Crawl is #{state}" if is_locked?
  end
end
