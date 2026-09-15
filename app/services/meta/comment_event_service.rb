class Meta::CommentEventService
  INBOX_NAMES = {
    'facebook' => 'Comentarios Facebook – Irlandes_ok',
    'instagram' => 'Comentarios Instagram – irlandes.oficial'
  }.freeze

  COMMENT_FIELDS = %w[comments live_comments].freeze

  def initialize(provider:, payload:)
    @provider = provider
    @payload = payload.with_indifferent_access
  end

  def perform
    comment_events.each { |event| process_event(event) }
  end

  private

  attr_reader :provider, :payload

  def comment_events
    Array(payload[:entry]).flat_map do |entry|
      Array(entry[:changes]).filter_map { |change| normalize(entry.with_indifferent_access, change.with_indifferent_access) }
    end
  end

  def normalize(entry, change)
    value = change[:value].to_h.with_indifferent_access
    return normalize_instagram(entry, value) if provider == 'instagram' && COMMENT_FIELDS.include?(change[:field])
    return normalize_facebook(entry, value) if provider == 'facebook' && facebook_comment?(change[:field], value)
  end

  def facebook_comment?(field, value)
    field == 'feed' && value[:item] == 'comment' && %w[add edited].include?(value[:verb])
  end

  def normalize_instagram(entry, value)
    author = value[:from].to_h.with_indifferent_access
    {
      account_id: entry[:id].to_s,
      comment_id: value[:id].to_s,
      author_id: author[:id].presence || value[:user_id].presence,
      author_name: author[:username].presence || value[:username].presence,
      text: value[:text].to_s,
      thread_id: value.dig(:media, :id).presence || value[:media_id].presence,
      parent_id: value[:parent_id],
      created_at: value[:timestamp].presence || entry[:time]
    }
  end

  def normalize_facebook(entry, value)
    author = value[:from].to_h.with_indifferent_access
    {
      account_id: entry[:id].to_s,
      comment_id: value[:comment_id].to_s,
      author_id: author[:id].presence || value[:sender_id],
      author_name: author[:name].presence || value[:sender_name],
      text: value[:message].to_s,
      thread_id: value[:post_id].presence || value.dig(:post, :id),
      parent_id: value[:parent_id],
      created_at: value[:created_time].presence || entry[:time]
    }
  end

  def process_event(event)
    return if event.values_at(:comment_id, :author_id, :thread_id).any?(&:blank?)
    return if event[:author_id].to_s == event[:account_id]

    source_channel = find_source_channel(event[:account_id])
    return if source_channel.blank?

    inbox = comments_inbox(source_channel)
    contact_inbox = find_or_create_contact_inbox(inbox, event)
    conversation = find_or_create_conversation(contact_inbox, event)
    event[:creative] = creative_details(source_channel, event) if conversation.messages.none?
    upsert_message(conversation, event)
  end

  def find_source_channel(account_id)
    if provider == 'facebook'
      Channel::FacebookPage.find_by(page_id: account_id)
    else
      Channel::Instagram.find_by(instagram_id: account_id) || Channel::FacebookPage.find_by(instagram_id: account_id)
    end
  end

  def comments_inbox(source_channel)
    account = source_channel.account
    channel = find_comments_channel(account, source_channel)
    if channel.present?
      channel.inbox.update!(enable_auto_assignment: false) if channel.inbox.enable_auto_assignment?
      return channel.inbox
    end

    source_channel.with_lock do
      find_comments_channel(account, source_channel)&.inbox || create_comments_inbox(account, source_channel)
    end
  end

  def find_comments_channel(account, source_channel)
    account.api_channels.reload.detect do |candidate|
      attributes = candidate.additional_attributes.to_h
      attributes['meta_comment_provider'] == provider && attributes['meta_source_channel_id'].to_i == source_channel.id
    end
  end

  def create_comments_inbox(account, source_channel)
    ActiveRecord::Base.transaction do
      channel = account.api_channels.create!(
        additional_attributes: {
          'meta_comment_provider' => provider,
          'meta_source_channel_id' => source_channel.id
        }
      )
      inbox = account.inboxes.create!(name: INBOX_NAMES.fetch(provider), channel: channel, enable_auto_assignment: false)
      member_ids = source_channel.inbox.member_ids
      inbox.add_members(member_ids) if member_ids.present?
      inbox
    end
  end

  def find_or_create_contact_inbox(inbox, event)
    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox,
      source_id: event[:author_id].to_s,
      contact_attributes: {
        name: event[:author_name].presence || "#{provider.capitalize} #{event[:author_id]}",
        identifier: "meta-comment:#{provider}:#{event[:author_id]}",
        additional_attributes: { 'social_profile_source' => provider }
      }
    ).perform
    update_contact_name(contact_inbox.contact, event[:author_name])
    contact_inbox
  end

  def update_contact_name(contact, author_name)
    return if author_name.blank? || contact.name == author_name

    contact.update!(name: author_name)
  end

  def find_or_create_conversation(contact_inbox, event)
    conversation = contact_inbox.conversations
                                .where("additional_attributes ->> 'meta_comment_thread_id' = ?", event[:thread_id].to_s)
                                .where.not(status: :resolved)
                                .last
    return conversation if conversation.present?

    ConversationBuilder.new(
      contact_inbox: contact_inbox,
      params: ActionController::Parameters.new(
        additional_attributes: {
          meta_comment_provider: provider,
          meta_comment_thread_id: event[:thread_id].to_s
        }
      )
    ).perform
  end

  def upsert_message(conversation, event)
    existing = conversation.messages.find_by(source_id: event[:comment_id])
    if existing.present?
      existing.update!(content: event[:text]) if existing.content != event[:text]
      return
    end

    Messages::MessageBuilder.new(nil, conversation, message_params(event)).perform
  end

  def message_params(event)
    {
      message_type: 'incoming',
      content: message_content(event),
      source_id: event[:comment_id],
      external_created_at: external_created_at(event[:created_at]),
      attachments: creative_attachment(event[:creative]),
      content_attributes: {
        meta_comment_provider: provider,
        meta_comment_id: event[:comment_id],
        meta_parent_id: event[:parent_id],
        meta_thread_id: event[:thread_id]
      }.compact
    }
  end

  def message_content(event)
    creative = event[:creative].to_h.with_indifferent_access
    return event[:text] if creative.blank?

    context = ['📌 Publicación original']
    context << creative[:caption].to_s.truncate(500) if creative[:caption].present?
    context << creative[:permalink] if creative[:permalink].present?
    context << "\n💬 Comentario\n#{event[:text]}"
    context.join("\n")
  end

  def creative_attachment(creative)
    media_url = creative.to_h.with_indifferent_access[:media_url]
    return if media_url.blank?

    downloaded = Down.download(media_url)
    filename = downloaded.respond_to?(:original_filename) ? downloaded.original_filename : nil
    filename = File.basename(URI.parse(media_url).path) if filename.blank?
    filename = 'meta-creative' if filename.blank?
    content_type = if downloaded.respond_to?(:content_type)
                     downloaded.content_type
                   else
                     Marcel::MimeType.for(downloaded, name: filename)
                   end

    [
      ActionDispatch::Http::UploadedFile.new(
        tempfile: downloaded,
        filename: filename,
        type: content_type
      )
    ]
  rescue StandardError => e
    Rails.logger.warn("Meta creative download failed: #{e.message}")
    nil
  end

  def creative_details(source_channel, event)
    provider == 'facebook' ? facebook_creative(source_channel, event) : instagram_creative(source_channel, event)
  rescue StandardError => e
    Rails.logger.warn("Meta creative lookup failed: #{e.message}")
    {}
  end

  def facebook_creative(channel, event)
    response = HTTParty.get(
      "https://graph.facebook.com/#{GlobalConfigService.load('FACEBOOK_API_VERSION', 'v22.0')}/#{event[:thread_id]}",
      query: { fields: 'message,permalink_url,full_picture', access_token: channel.page_access_token }
    )
    body = response.parsed_response.to_h.with_indifferent_access
    { caption: body[:message], permalink: body[:permalink_url], media_url: body[:full_picture] }.compact
  end

  def instagram_creative(channel, event)
    response = HTTParty.get(
      "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}/#{event[:thread_id]}",
      query: { fields: 'caption,media_type,media_url,thumbnail_url,permalink', access_token: channel.access_token }
    )
    body = response.parsed_response.to_h.with_indifferent_access
    { caption: body[:caption], permalink: body[:permalink], media_url: body[:thumbnail_url].presence || body[:media_url] }.compact
  end

  def external_created_at(value)
    return if value.blank?

    Time.zone.at(value.to_i)
  end
end
