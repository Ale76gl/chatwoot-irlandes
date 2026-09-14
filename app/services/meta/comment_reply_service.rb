class Meta::CommentReplyService
  def initialize(message:)
    @message = message
  end

  def perform
    return unless message.outgoing? && !message.private?
    return if provider.blank? || source_channel.blank? || comment_id.blank?

    response = provider == 'facebook' ? reply_on_facebook : reply_on_instagram
    raise "Meta comment reply failed: #{response.code} #{response.body}" unless response.success?

    response_id = response.parsed_response.to_h['id']
    message.update!(
      source_id: response_id.presence || message.source_id,
      content_attributes: message.content_attributes.to_h.merge(
        'meta_comment_provider' => provider,
        'meta_comment_id' => response_id,
        'meta_parent_id' => comment_id
      ).compact
    )
  rescue StandardError => e
    Rails.logger.error("Meta comment reply error for message #{message.id}: #{e.message}")
    message.update!(status: :failed, external_error: e.message.truncate(1000))
  end

  private

  attr_reader :message

  def comments_channel
    @comments_channel ||= message.inbox.channel
  end

  def provider
    @provider ||= comments_channel.additional_attributes.to_h['meta_comment_provider']
  end

  def source_channel
    @source_channel ||= begin
      channel_id = comments_channel.additional_attributes.to_h['meta_source_channel_id']
      provider == 'facebook' ? Channel::FacebookPage.find_by(id: channel_id) : Channel::Instagram.find_by(id: channel_id)
    end
  end

  def comment_id
    @comment_id ||= message.conversation.messages.incoming.order(created_at: :desc).find do |candidate|
      candidate.content_attributes.to_h['meta_comment_id'].present?
    end&.content_attributes&.dig('meta_comment_id')
  end

  def reply_on_facebook
    HTTParty.post(
      "https://graph.facebook.com/#{facebook_version}/#{comment_id}/comments",
      query: { message: message.content, access_token: source_channel.page_access_token }
    )
  end

  def reply_on_instagram
    HTTParty.post(
      "https://graph.instagram.com/#{instagram_version}/#{comment_id}/replies",
      query: { message: message.content, access_token: source_channel.access_token }
    )
  end

  def facebook_version
    GlobalConfigService.load('FACEBOOK_API_VERSION', 'v22.0')
  end

  def instagram_version
    GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')
  end
end
