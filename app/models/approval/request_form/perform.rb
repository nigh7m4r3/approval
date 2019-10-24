module Approval
  module RequestForm
    class Perform < Base
      private

        def prepare
          request.request_type = @request_type
          request.access_scope = @access_scope
          if @full_params[:parent_request_id].present?
            request.parent_request_id = @full_params[:parent_request_id].to_i
          end
          instrument "request" do |payload|
            ::Approval::Request.transaction do
              payload[:comment] = request.comments.new(user_id: user.id, content: reason)
              Array(records).each do |record|
                item = request.items.new(
                  event: "perform",
                  resource_type: record.class.to_s,
                  resource_id: record.id,
                  params: extract_params_from(record),
                  callback_method: @callback_method,
                  options: @options,
                  full_params: @full_params
                )
                item.paper_trail_event = request.paper_trail_event if request.paper_trail_event.present?
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
