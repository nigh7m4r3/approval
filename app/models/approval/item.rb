module Approval
  class Item < ApplicationRecord
    class UnexistResource < StandardError; end

    has_paper_trail

    self.table_name = :approval_items
    EVENTS = %w[create update destroy perform].freeze

    belongs_to :request, class_name: :"Approval::Request", inverse_of: :items
    belongs_to :resource, polymorphic: true, optional: true

    serialize :params, Hash
    serialize :options, Hash

    validates :resource_type, presence: true
    validates :resource_id,   presence: true, if: ->(item) { item.update_event? || item.destroy_event? }
    validates :event,         presence: true, inclusion: { in: EVENTS }
    validates :params,        presence: true, if: :update_event?

    # validate :ensure_resource_be_valid, if: ->(item) { item.create_event? || item.update_event? }
    validate :resource_custom_validation, on: :create

    EVENTS.each do |event_name|
      define_method "#{event_name}_event?" do
        event_name.to_s == event.to_s
      end
    end

    def as_json(options={})
      h = super(options)

      h
    end

    def as_json_for_checker(options={})
      h = as_json(options)

      if resource && resource.respond_to?(:as_json_for_checker)
        h[self.resource_type.downcase.to_sym] = resource.as_json_for_checker
      end

      h
    end

    def apply
      send("exec_#{event}")
    end

    def user
      if resource_type == 'User' && resource_id.present?
        return User.includes(:user_information).find_by(id: resource_id)
      end
    end

    def user_information
      if user
        user.user_information
      end
    end

    def resource_model
      return @resource_model if @resource_model.present?

      if resource_id.present?
        @resource_model = resource_type.to_s.safe_constantize.find(resource_id)
      else
        @resource_model = resource_type.to_s.safe_constantize.new
      end

      changes = {}
      params.map{|k, v| changes[k] = v.last}
      @resource_model.assign_attributes(changes)

      @resource_model
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
          raise NotImplementedError
        end
        # raise NotImplementedError unless resource_model.respond_to?(:perform)

        arg_count = resource_model.method(callback_method.to_sym).arity
        if arg_count != 0
          # resource_model.perform(params)
          result = resource_model.public_send(callback_method, options)
        else
          # resource_model.perform
          result = resource_model.public_send(callback_method)
        end
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

      def resource_custom_validation
        return unless resource_model

        callback_method = self.callback_method
        validation_method = callback_method.gsub('callback', 'validation_callback')
        if resource_model.respond_to?(validation_method)
          validation_status, validation_errors = resource_model.public_send(validation_method, options)
          unless validation_status
            request.errors.add(:base, validation_errors)
            return false
          end
        else
          return  true
        end
      end
  end
end
