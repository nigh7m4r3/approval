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
    has_many :items, class_name: :"Approval::Item", inverse_of: :request, dependent: :destroy

    # belongs_to :approval_access_control, class_name: 'Approval::AccessControl', foreign_key: :request_type, primary_key: :request_type
    belongs_to :approval_access_control, class_name: 'Approval::AccessControl', foreign_key: [:request_type, :access_scope], primary_key: [:request_type, :access_scope]

    enum state: {pending: 0, cancelled: 1, approved: 2, rejected: 3, executed: 4}
    enum display_status: {displayed: 1, hidden: 2}
    enum request_type: {
        'Lock User' => 'lock_user',
        'Unlock User' => 'unlock_user',
        'Create User' => 'create_user',
        'Update User Information' => 'update_user_information',
        'Create Terminal' => 'create_terminal',
        'Update Terminal' => 'update_terminal',
        'Lock Terminal' => 'lock_terminal',
        'Unlock Terminal' => 'unlock_terminal',
        'Lock Merchant' => 'lock_merchant',
        'Unlock Merchant' => 'unlock_merchant',
        'Lock Parent Merchant' => 'lock_parent_merchant',
        'Unlock Parent Merchant' => 'unlock_parent_merchant',
        'Update Merchant' => 'update_merchant',
        'Create Merchant' => 'create_merchant',
        'Create Merchant User' => 'create_merchant_user',
        'Create Parent Merchant' => 'create_parent_merchant',
        'Update Parent Merchant' => 'update_parent_merchant',
        'Create Parent Merchant User' => 'create_parent_merchant_user',
        'Update Parent Merchant User' => 'update_parent_merchant_user',
        'Customer Change Request' => 'customer_change_request'
    }

    # Dictionary of available access scopes
    ACCESS_SCOPE = ['customer', 'bank_user', 'merchant_user', 'merchant', 'terminal', 'customer_lock_unlock']

    scope :recently, -> {order(id: :desc)}

    validates :state, presence: true
    validates :respond_user, presence: true, unless: :pending?
    validates :comments, presence: true
    validates :items, presence: true
    validates :access_scope, presence: true

    validates_associated :comments
    validates_associated :items

    validate :ensure_state_was_pending
    validate :same_resource_is_not_pending, on: :create

    before_validation do
      if parent_request
        self.access_scope = parent_request.access_scope
      end
    end

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

    def as_json_for_checker(options = {})
      h = as_json(options)

      if items
        h[:items] = items.map(&:as_json_for_checker)
      end

      h
    end

    def self.existing_record(request_type:, state: 'pending', record:)
      joins(:items)
          .where(request_type: request_type, state: state)
          .where('approval_items.resource_type = ? AND approval_items.resource_id = ?', record.class.to_s, record.id)
    end

    def all_related_comments
      if self.parent_request_id.present?
        parent = parent_request
        children = parent.child_requests
        all_comments =  Approval::Comment.where(request_id: [self.id, parent.id, children.map(&:id)].flatten)
      else
        all_comments = comments
      end

      all_comments.includes(request: [:respond_user, :request_user, :approval_access_control], user: :user_information)
    end

    def get_access_scope
      return self.access_scope unless self.parent_request.present?

      self.parent_request.access_scope
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

    def access_control
      AccessControl.includes(:approval_access_control_roles).find_by(request_type: Approval::Request::request_types[self.request_type], access_scope: self.access_scope)
    end

    def valid_makers
      makers = access_control.approval_access_control_roles.maker
      user_klass = 'User'.safe_constantize
      if user_klass.present?
        user_klass.joins(:roles).where(roles: {id: makers.map(&:role_id)})
      end
    end

    def valid_checkers
      checkers = access_control.approval_access_control_roles.checker
      user_klass = 'User'.safe_constantize
      if user_klass.present?
        user_klass.joins(:roles).where(roles: {id: checkers.map(&:role_id)})
      end
    end

    def action
      return 'approved' if self.state == 'executed'
      self.state
    end

    def user_can_check?(current_user_id: User.current.id)
      permitted_user_ids = Approval::AccessControl
                               .find_by(request_type: Approval::Request::request_types[self.request_type])
                               .approval_access_control_roles
                               .where(access_type: Approval::AccessControlRole::access_types[:checker])
                               .map(&:approval_access_control_id)

      permitted_user_ids.include?(current_user_id)
    end

    private

    def ensure_state_was_pending
      return unless persisted?

      if %w[pending approved].exclude?(state_was)
        errors.add(:base, :already_performed)
      end
    end

    def same_resource_is_not_pending
      item = self.items.first
      resource_type = item.resource_type
      resource_id = item.resource_id

      return true unless resource_id

      if (['create_parent_merchant_user', 'create_merchant_user'].include?(Request::request_types[self.request_type])) && (['ParentMerchant', 'Merchant'].include?(resource_type))
        return true
      end
      existing_requests = Request.joins(:items).where(request_type: Request::request_types[self.request_type], approval_items: {resource_type: resource_type, resource_id: resource_id}).pending

      return true unless existing_requests.count > 0

      errors.add(:base, "A pending request (ID: #{existing_requests.map(&:id).join(', ')}) for this #{resource_type} already exist. Please Approve/Reject that first.")

      false
    end
  end
end
