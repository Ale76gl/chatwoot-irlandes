class CreateWhatsappHistorySyncChunks < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_history_sync_chunks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.string :phone_number_id, null: false
      t.integer :phase
      t.integer :chunk_order
      t.integer :progress
      t.string :payload_sha256, null: false
      t.string :status, null: false, default: 'pending'
      t.jsonb :payload, null: false, default: {}
      t.text :error
      t.datetime :processed_at
      t.timestamps
    end

    add_index :whatsapp_history_sync_chunks, [:inbox_id, :payload_sha256], unique: true,
              name: 'idx_wa_history_chunks_inbox_sha'
    add_index :whatsapp_history_sync_chunks, [:inbox_id, :phase, :chunk_order],
              name: 'idx_wa_history_chunks_phase_order'
  end
end
