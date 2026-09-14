class Webhooks::MetaCommentsJob < ApplicationJob
  queue_as :default

  def perform(provider, payload)
    Meta::CommentEventService.new(provider: provider, payload: payload).perform
  end
end
