module Approval
  class Request < ApplicationRecord
    self.table_name = :approval_requests

    def self.define_user_association
      belongs_to :request_user, class_name: Approval.config.user_class_name
      belongs_to :respond_user, class_name: Approval.config.user_class_name, optional: true
    end

    has_many :comments, class_name: :"Approval::Comment", inverse_of: :request, dependent: :destroy
    has_many :items,    class_name: :"Approval::Item",    inverse_of: :request, dependent: :destroy

    enum state: { pending: 0, cancelled: 1, approved: 2, rejected: 3, executed: 4 }

    scope :recently, -> { order(id: :desc) }

    validates :state,        presence: true
    validates :respond_user, presence: true, unless: :pending?
    validates :comments,     presence: true
    validates :items,        presence: true

    validates_associated :comments
    validates_associated :items

    validate :ensure_state_was_pending

    before_create do
      self.requested_at = Time.current
    end

    def as_json(options = {})
      h = super(options)
      if respond_user
        h[:respond_user] = respond_user.as_json(include: [:user_information])
      end
      if request_user
        h[:request_user] = request_user.as_json(include: [:user_information])
      end
      if items
        h[:items] = items.as_json
      end

      h
    end

    def execute
      self.state = :executed
      self.executed_at = Time.current
      self.request_type = @request_type if @request_type.present?
      items.each(&:apply)
    end

    private

      def ensure_state_was_pending
        return unless persisted?

        if %w[pending approved].exclude?(state_was)
          errors.add(:base, :already_performed)
        end
      end
  end
end
