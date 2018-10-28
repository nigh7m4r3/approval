module Approval
  class AccessControl < ApplicationRecord
    has_paper_trail
    self.table_name = :approval_access_controls

    has_many :approval_access_control_roles, class_name: 'Approval::AccessControlRole', foreign_key: :approval_access_control_id
    has_many :approval_maker_access_control_roles, ->{where(access_type: Approval::AccessControlRole::access_types[:maker])}, class_name: 'Approval::AccessControlRole', foreign_key: :approval_access_control_id
    has_many :approval_checker_access_control_roles, ->{where(access_type: Approval::AccessControlRole::access_types[:checker])}, class_name: 'Approval::AccessControlRole', foreign_key: :approval_access_control_id
    has_many :maker_roles, class_name: 'Role', through: :approval_maker_access_control_roles
    has_many :checker_roles, class_name: 'Role', through: :approval_checker_access_control_roles

    has_many :approval_request, class_name: 'Approval::Request', foreign_key: :request_type, primary_key: :request_type
  end
end

