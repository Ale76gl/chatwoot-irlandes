# ref: https://github.com/jgorset/facebook-messenger#make-a-configuration-provider
class ChatwootFbProvider < Facebook::Messenger::Configuration::Providers::Base
  CHANNEL_APP_SECRET_KEYS = %w[app_secret app_secret_key client_secret api_secret].freeze

  def valid_verify_token?(_verify_token)
    GlobalConfigService.load('FB_VERIFY_TOKEN', '')
  end

  def app_secret_for(page_id)
    channel_app_secret_for(page_id).presence || GlobalConfigService.load('FB_APP_SECRET', '')
  end

  def access_token_for(page_id)
    Channel::FacebookPage.where(page_id: page_id).last.page_access_token
  end

  private

  def channel_app_secret_for(page_id)
    channel = Channel::FacebookPage.where(page_id: page_id).last
    return if channel.blank?

    channel_app_secret_candidates(channel).first
  end

  def channel_app_secret_candidates(channel)
    secrets = []
    secrets << channel.app_secret if channel.respond_to?(:app_secret)
    secrets.concat(provider_config_app_secrets(channel))
    secrets.compact_blank.uniq
  end

  def provider_config_app_secrets(channel)
    return [] unless channel.respond_to?(:provider_config)

    provider_config = channel.provider_config.to_h.with_indifferent_access
    CHANNEL_APP_SECRET_KEYS.filter_map { |key| provider_config[key].presence }
  end

  def bot
    Chatwoot::Bot
  end
end

# The facebook-messenger gem intentionally ignores Page webhook entries that do
# not contain a `messaging` payload. Capture Page feed comment events before the
# gem continues processing Messenger events as usual.
module IrlandesFacebookCommentWebhook
  def trigger(events)
    if Array(events['entry']).any? { |entry| entry['changes'].present? }
      Webhooks::MetaCommentsJob.perform_later('facebook', events)
    end

    super
  end
end

Facebook::Messenger::Server.prepend(IrlandesFacebookCommentWebhook) unless
  Facebook::Messenger::Server.ancestors.include?(IrlandesFacebookCommentWebhook)

Rails.application.reloader.to_prepare do
  Facebook::Messenger.configure do |config|
    config.provider = ChatwootFbProvider.new
  end

  Facebook::Messenger::Bot.on :message do |message|
    Webhooks::FacebookEventsJob.perform_later(message.to_json)
  end

  Facebook::Messenger::Bot.on :delivery do |delivery|
    Rails.logger.info "Recieved delivery status #{delivery.to_json}"
    Webhooks::FacebookDeliveryJob.perform_later(delivery.to_json)
  end

  Facebook::Messenger::Bot.on :read do |read|
    Rails.logger.info "Recieved read status  #{read.to_json}"
    Webhooks::FacebookDeliveryJob.perform_later(read.to_json)
  end

  Facebook::Messenger::Bot.on :message_echo do |message|
    # Add delay to prevent race condition where echo arrives before send message API completes
    # This avoids duplicate messages when echo comes early during API processing
    Webhooks::FacebookEventsJob.set(wait: 2.seconds).perform_later(message.to_json)
  end
end
