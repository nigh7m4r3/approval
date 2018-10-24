module Approval
  class AccessControlRole < ApplicationRecord
    has_paper_trail
    self.table_name = :approval_access_control_roles

    belongs_to :role
    belongs_to :approval_access_control

    enum access_type: {
        maker: 1,
        checker: 2
    }
  end
end
