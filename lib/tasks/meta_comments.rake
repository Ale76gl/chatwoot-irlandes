namespace :meta_comments do
  desc 'Subscribe existing Facebook and Instagram channels to comment webhooks'
  task subscribe: :environment do
    channels = Channel::FacebookPage.find_each.to_a + Channel::Instagram.find_each.to_a
    channels.each do |channel|
      channel.subscribe
      puts "Subscribed #{channel.class.name} ##{channel.id}"
    end
  end
end
