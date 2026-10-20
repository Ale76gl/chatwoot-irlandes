# Dependency-free contract checks; Rails/RSpec integration remains separate.
class Notification; end
require_relative '../../app/services/notification/message_preview'

Message = Struct.new(:content, :processed_message_content, :attachments)
Attachment = Struct.new(:fallback_title, :file_type, :file)
FileReference = Struct.new(:filename, :is_attached) do
  def attached?
    is_attached
  end
end

TRANSLATIONS = {
  'notifications.no_content' => 'No content', 'notifications.attachment' => 'Attachment',
  'notifications.attachment_types.image' => 'Image', 'notifications.attachment_types.audio' => 'Voice message',
  'notifications.attachment_types.video' => 'Video', 'notifications.attachment_types.file' => 'Document'
}.freeze

CASES = [
  ['text over processed text', Message.new('Customer text', 'Processed', []), 'Customer text'],
  ['native interactive title', Message.new('Selected product', nil, []), 'Selected product'],
  ['native rendered template', Message.new('Hello synthetic contact', nil, []), 'Hello synthetic contact'],
  ['native media caption', Message.new('Caption', nil, [Attachment.new(nil, 'image', FileReference.new(nil, false))]), 'Caption'],
  ['processed content', Message.new(nil, 'Rendered message', []), 'Rendered message'],
  ['whitespace content', Message.new(" \n", 'Rendered message', []), 'Rendered message'],
  ['attachment title', Message.new(nil, nil, [Attachment.new('Product brochure', 'file', FileReference.new(nil, false))]), 'Product brochure'],
  ['filename', Message.new(nil, nil, [Attachment.new(nil, 'file', FileReference.new('brochure.pdf', true))]), 'brochure.pdf'],
  ['image fallback', Message.new(nil, nil, [Attachment.new(nil, 'image', FileReference.new(nil, false))]), 'Image'],
  ['audio fallback', Message.new(nil, nil, [Attachment.new(nil, 'audio', FileReference.new(nil, false))]), 'Voice message'],
  ['video fallback', Message.new(nil, nil, [Attachment.new(nil, 'video', FileReference.new(nil, false))]), 'Video'],
  ['document fallback', Message.new(nil, nil, [Attachment.new(nil, 'file', FileReference.new(nil, false))]), 'Document'],
  ['unknown attachment', Message.new(nil, nil, [Attachment.new(nil, 'location', FileReference.new(nil, false))]), 'Attachment'],
  ['empty message', Message.new(nil, nil, []), 'No content'],
  ['missing actor', nil, 'No content']
].freeze

CASES.each do |name, message, expected|
  actual = Notification::MessagePreview.new(message, translate: ->(key) { TRANSLATIONS.fetch(key) }).content
  raise "#{name}: preview differs" unless actual == expected
end
puts "#{CASES.length} synthetic preview contracts passed; no Rails, FCM or Android execution"
