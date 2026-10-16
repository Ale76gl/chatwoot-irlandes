class Whatsapp::HistorySyncChunk < ApplicationRecord
  self.table_name = 'whatsapp_history_sync_chunks'

  belongs_to :account
  belongs_to :inbox

  validates :phone_number_id, :payload_sha256, :status, presence: true
end
