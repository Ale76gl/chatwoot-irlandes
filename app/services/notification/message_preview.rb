# Preview only: never fetches media, renders templates or dispatches a notification.
class Notification::MessagePreview
  ATTACHMENT_KEYS = {
    'image' => 'image', 'audio' => 'audio', 'video' => 'video', 'file' => 'file'
  }.freeze

  def initialize(message, translate: ->(key) { I18n.t(key, default: I18n.t('notifications.attachment')) })
    @message = message
    @translate = translate
  end

  def content
    return @translate.call('notifications.no_content') unless @message

    # Native WhatsApp ingestion already puts text, button/list titles, rendered
    # templates and media captions in content. Do not substitute raw JSON or IDs.
    text = nonblank(@message.content) || nonblank(@message.processed_message_content)
    return text if text

    attachment = @message.attachments.first
    return @translate.call('notifications.no_content') unless attachment

    attachment_content(attachment)
  end

  private

  def attachment_content(attachment)
    title = nonblank(attachment.fallback_title)
    return title if title
    return attachment.file.filename.to_s if attachment.file.attached?

    type = ATTACHMENT_KEYS[attachment.file_type]
    type ? @translate.call("notifications.attachment_types.#{type}") : @translate.call('notifications.attachment')
  end

  def nonblank(value)
    value if value.is_a?(String) && !value.strip.empty?
  end
end
