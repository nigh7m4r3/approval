module Approval
  class Item < ApplicationRecord
    class UnexistResource < StandardError; end

    self.table_name = :approval_items
    EVENTS = %w[create update destroy perform].freeze

    belongs_to :request, class_name: :"Approval::Request", inverse_of: :items
    belongs_to :resource, polymorphic: true, optional: true

    serialize :params, Hash

    validates :resource_type, presence: true
    validates :resource_id,   presence: true, if: ->(item) { item.update_event? || item.destroy_event? }
    validates :event,         presence: true, inclusion: { in: EVENTS }
    validates :params,        presence: true, if: :update_event?

    validate :ensure_resource_be_valid, if: ->(item) { item.create_event? || item.update_event? }

    EVENTS.each do |event_name|
      define_method "#{event_name}_event?" do
        event_name.to_s == event.to_s
      end
    end

    def apply
      send("exec_#{event}")
    end

    private

      def exec_create
        resource_model.create!(params).tap do |created_resource|
          update!(resource_id: created_resource.id)
        end
      end

      def exec_update
        raise UnexistResource unless resource

        resource.update!(params)
      end

      def exec_destroy
        raise UnexistResource unless resource

        resource.destroy
      end

      def exec_perform
        callback_method = self.callback_method

        raise NotImplementedError unless callback_method.present?

        unless resource_model.respond_to?(callback_method)
          @resource_model = resource_model.find_by(id: resource_id)
          unless @resource_model.respond_to?(callback_method)
            raise NotImplementedError
          end
        end
        # raise NotImplementedError unless resource_model.respond_to?(:perform)

        arg_count = resource_model.method(callback_method.to_sym).arity
        if arg_count != 0
          # resource_model.perform(params)
          byebug
          resource_model.public_send(callback_method, params)
        else
          # resource_model.perform
          resource_model.public_send(callback_method)
        end
      end

      def resource_model
        @resource_model ||= resource_type.to_s.safe_constantize
      end

      def ensure_resource_be_valid
        return unless resource_model

        record = if resource_id.present?
                   resource_model.find(resource_id).tap {|m| m.assign_attributes(params) }
                 else
                   resource_model.new(params || {})
                 end

        unless record.valid?
          errors.add(:base, :invalid)
          record.errors.full_messages.each do |message|
            request.errors.add(:base, message)
          end
        end
      end
  end
end
