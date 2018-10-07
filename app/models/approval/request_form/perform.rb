module Approval
  module RequestForm
    class Perform < Base
      private

        def prepare
          request.request_type = @request_type
          instrument "request" do |payload|
            ::Approval::Request.transaction do
              payload[:comment] = request.comments.new(user_id: user.id, content: reason)
              Array(records).each do |record|
                request.items.new(
                  event: "perform",
                  resource_type: record.class.to_s,
                  resource_id: record.id,
                  params: extract_params_from(record),
                  callback_method: @callback_method,
                  options: @options,
                  full_changes: @full_changes
                )
              end
              yield(request)
            end
          end
        end

        def extract_params_from(record)
          record.changes || {}
        end
    end
  end
end
