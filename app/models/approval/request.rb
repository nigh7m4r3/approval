module Approval
  class Request < ApplicationRecord
    has_paper_trail

    self.table_name = :approval_requests

    def self.define_user_association
      belongs_to :request_user, class_name: Approval.config.user_class_name
      belongs_to :respond_user, class_name: Approval.config.user_class_name, optional: true
    end

    belongs_to :parent_request, class_name: 'Approval::Request'
    has_many :child_requests, class_name: 'Approval::Request', foreign_key: :parent_request_id

    has_many :comments, class_name: :"Approval::Comment", inverse_of: :request, dependent: :destroy
    has_many :items,    class_name: :"Approval::Item",    inverse_of: :request, dependent: :destroy

    belongs_to :approval_access_control, class_name: 'Approval::AccessControl', foreign_key: :request_type, primary_key: :request_type

    enum state: { pending: 0, cancelled: 1, approved: 2, rejected: 3, executed: 4 }
    enum display_status: { displayed: 1, hidden: 2 }
    enum request_type: {
        'Lock User' => 'lock_user',
        'Unlock User' => 'unlock_user',
        'Create User' => 'create_user',
        'Update User Information' => 'update_user_information',
        'Create Terminal' => 'create_terminal',
        'Update Terminal' => 'update_terminal',
        'Update Merchant' => 'update_merchant',
        'Create Merchant' => 'create_merchant',
        'Create Merchant User' => 'create_merchant_user',
        'Create Parent Merchant' => 'create_parent_merchant',
        'Update Parent Merchant' => 'update_parent_merchant',
        'Create Parent Merchant User' => 'create_parent_merchant_user',
        'Update Parent Merchant User' => 'update_parent_merchant_user',
    }

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

    after_create :hide_related_rejected_requests

    def as_json(options = {})
      h = super(options)
      if respond_user
        h[:respond_user] = respond_user.as_json(include: [:user_information])
      end
      if request_user
        h[:request_user] = request_user.as_json(include: [:user_information])
      end
      if items
        h[:items] = items.as_json(include: [:user, :user_information])
      end

      h
    end

    def as_json_for_checker(options={})
      h = as_json(options)

      if items
        h[:items] = items.map(&:as_json_for_checker)
      end

      h
    end

    def all_related_comments
      if self.parent_request_id.present?
        parent = parent_request
        children = parent.child_requests
        Approval::Comment.where(request_id: [self.id, parent.id, children.map(&:id)].flatten)
      else
        comments
      end
    end

    def execute
      self.state = :executed
      self.executed_at = Time.current
      self.request_type = @request_type if @request_type.present?
      items.each(&:apply)
    end

    def hide_related_rejected_requests
      if self.parent_request_id.present?
        parent = self.parent_request
        children = parent.child_requests.where.not(id: self.id)
        Approval::Request
            .where(id: [parent.id, children.map(&:id)].flatten!)
            .displayed
            .update_all(display_status: Approval::Request::display_statuses[:hidden])
      end
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
