class Webhooks::MetaCommentReplyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    Meta::CommentReplyService.new(message: message).perform if message.present?
  end
end
