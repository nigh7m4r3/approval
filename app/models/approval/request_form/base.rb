module Approval
  module RequestForm
    class Base
      include ::ActiveModel::Model
      include ::Approval::FormNotifiable

      attr_accessor :user, :reason, :records, :callback_method

      def initialize(user:, reason:, records:, request_type: nil, access_scope: nil, callback_method: nil, options: {}, full_params: {})
        @user    = user
        @reason  = reason
        @records = records
        @access_scope = access_scope
        @request_type = request_type
        @callback_method = callback_method
        @options = options
        @full_params = full_params
      end

      validates :user,    presence: true
      validates :reason,  presence: true, length: { maximum: Approval.config.comment_maximum }
      validates :records, presence: true

      def save
        return false unless valid?

        prepare(&:save)
      end

      def save!
        raise ::ActiveRecord::RecordInvalid unless valid?

        prepare(&:save!)
      end

      def request
        @request ||= user.approval_requests.new
      end

      def error_full_messages
        [errors, request.errors].flat_map(&:full_messages)
      end

      private

        def prepare
          raise NotImplementedError, "you must implement #{self.class}##{__method__}"
        end
    end
  end
end
