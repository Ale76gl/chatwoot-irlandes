class Conversations::TypingStatusManager
  include Events::Types

  attr_reader :conversation, :user, :params

  def initialize(conversation, user, params)
    @conversation = conversation
    @user = user
    @params = params
  end

  def trigger_typing_event(event, is_private)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, conversation: @conversation, user: @user, is_private: is_private)
  end

  def toggle_typing_status
    case params[:typing_status]
    when 'on'
      trigger_typing_event(CONVERSATION_TYPING_ON, params[:is_private])
      send_whatsapp_typing_indicator
    when 'off'
      trigger_typing_event(CONVERSATION_TYPING_OFF, params[:is_private])
    end
    # Return the head :ok response from the controller
  end
  def send_whatsapp_typing_indicator
    channel = conversation.inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'

    incoming = conversation.messages.incoming.where.not(source_id: [nil, '']).order(created_at: :desc).first
    return if incoming&.source_id.blank?

    channel.provider_service.send_typing_indicator(incoming.source_id)
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP] typing indicator error conversation=#{conversation.id}: #{e.message}")
  end

end
