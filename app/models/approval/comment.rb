module Approval
  class Comment < ApplicationRecord
    self.table_name = :approval_comments

    def self.define_user_association
      belongs_to :user, class_name: Approval.config.user_class_name
    end

    belongs_to :request, class_name: :"Approval::Request", inverse_of: :comments
    validates :content, presence: true, length: { maximum: Approval.config.comment_maximum }

    def request_action
      request.action
    end

    def user_role
      return 'maker' if request.valid_makers.map(&:id).include? user.id
      return 'checker' if request.valid_checkers.map(&:id).include? user.id
    end
  end
end
