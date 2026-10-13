require 'digest'
require 'set'

class Whatsapp::HistorySyncService
  SUPPORTED_MESSAGE_TYPES = %w[text image video audio document sticker location contacts button interactive unsupported].freeze
  STATUS_MAP = {
    'sent' => :sent,
    'delivered' => :delivered,
    'read' => :read,
    'failed' => :failed
  }.freeze

  pattr_initialize [:inbox!, :params!]

  def perform
    history_changes.each do |change|
      value = change[:value] || {}
      Array(value[:history]).each { |history_item| process_history_item(value, history_item) }
    end
  end

  private

  def history_changes
    Array(params[:entry]).flat_map { |entry| Array(entry[:changes]) }.select { |change| change[:field] == 'history' }
  end

  def process_history_item(value, history_item)
    metadata = history_item[:metadata] || {}
    chunk = find_or_create_chunk(value, history_item, metadata)
    return if chunk.status == 'processed'

    if history_item[:errors].present?
      chunk.update!(status: 'error', error: history_item[:errors].to_json, processed_at: Time.current)
      Rails.logger.warn("[WHATSAPP HISTORY] inbox_id=#{inbox.id} sync error=#{history_item[:errors].to_json}")
      return
    end

    chunk.update!(status: 'processing', error: nil)
    conversation_ids = Set.new
    imported = 0
    skipped = 0

    Array(history_item[:threads]).each do |thread|
      Array(thread[:messages]).sort_by { |message| message[:timestamp].to_i }.each do |message|
        result = import_message(value, thread, message, metadata)
        if result
          imported += 1
          conversation_ids << result.conversation_id
        else
          skipped += 1
        end
      end
    end

    normalize_conversation_timestamps(conversation_ids)
    chunk.update!(status: 'processed', processed_at: Time.current)
    Rails.logger.info(
      "[WHATSAPP HISTORY] inbox_id=#{inbox.id} phase=#{metadata[:phase]} chunk=#{metadata[:chunk_order]} " \
      "progress=#{metadata[:progress]} imported=#{imported} skipped=#{skipped}"
    )
  rescue StandardError => e
    chunk&.update_columns(status: 'failed', error: "#{e.class}: #{e.message}", updated_at: Time.current)
    Rails.logger.error("[WHATSAPP HISTORY] inbox_id=#{inbox.id} import failed: #{e.class}: #{e.message}")
    raise
  end

  def find_or_create_chunk(value, history_item, metadata)
    raw_payload = history_item.deep_stringify_keys
    digest = Digest::SHA256.hexdigest(JSON.generate(raw_payload))
    phone_number_id = value.dig(:metadata, :phone_number_id).to_s.presence || inbox.channel.provider_config['phone_number_id'].to_s

    Whatsapp::HistorySyncChunk.find_or_create_by!(inbox_id: inbox.id, payload_sha256: digest) do |record|
      record.account_id = inbox.account_id
      record.phone_number_id = phone_number_id
      record.phase = metadata[:phase]
      record.chunk_order = metadata[:chunk_order]
      record.progress = metadata[:progress]
      record.payload = raw_payload
      record.status = 'pending'
    end
  end

  def import_message(value, thread, raw_message, metadata)
    message = raw_message.deep_symbolize_keys
    source_id = message[:id].to_s
    return if source_id.blank?

    existing = Message.find_by(inbox_id: inbox.id, source_id: source_id)
    return existing if existing&.content_attributes&.dig('whatsapp_history_import')
    return existing if existing

    thread_id = thread[:id].to_s
    outgoing = outgoing_message?(value, thread_id, message)
    normalized_message, original_type = normalize_message(message, thread_id, outgoing)
    payload = build_message_payload(value, thread_id, normalized_message, outgoing)

    Whatsapp::IncomingMessageWhatsappCloudService.new(
      inbox: inbox,
      params: payload.with_indifferent_access,
      outgoing_echo: outgoing,
      history_import: true
    ).perform

    imported_message = Message.find_by(inbox_id: inbox.id, source_id: source_id)
    return unless imported_message

    apply_history_metadata(imported_message, message, metadata, original_type, outgoing)
    imported_message
  end

  def outgoing_message?(value, thread_id, message)
    sender = digits(message[:from])
    recipient = digits(message[:to])
    thread_phone = digits(thread_id)
    business_phone = digits(value.dig(:metadata, :display_phone_number).presence || inbox.channel.phone_number)

    return true if sender.present? && sender == business_phone
    return false if sender.present? && sender == thread_phone

    recipient.present? && recipient == thread_phone
  end

  def build_message_payload(value, thread_id, message, outgoing)
    contact = { wa_id: thread_id, profile: { name: "+#{digits(thread_id)}" } }
    message = message.merge(to: thread_id) if outgoing && message[:to].blank?
    message = message.merge(from: thread_id) if !outgoing && message[:from].blank?

    webhook_value = {
      messaging_product: 'whatsapp',
      metadata: value[:metadata] || {},
      contacts: [contact]
    }
    webhook_value[outgoing ? :message_echoes : :messages] = [message]

    {
      object: 'whatsapp_business_account',
      entry: [{
        id: inbox.channel.provider_config['business_account_id'],
        changes: [{ field: outgoing ? 'smb_message_echoes' : 'messages', value: webhook_value }]
      }]
    }
  end

  def normalize_message(message, thread_id, outgoing)
    original_type = message[:type].to_s
    return [message, original_type] if SUPPORTED_MESSAGE_TYPES.include?(original_type)
    return [message, original_type] if %w[reaction ephemeral request_welcome].include?(original_type)

    direction = outgoing ? 'enviado' : 'recibido'
    placeholder = {
      from: message[:from],
      to: message[:to] || thread_id,
      id: message[:id],
      timestamp: message[:timestamp],
      type: 'text',
      text: { body: "[Mensaje histórico #{direction}: #{original_type.presence || 'tipo no disponible'}]" },
      history_context: message[:history_context]
    }.compact
    [placeholder, original_type]
  end

  def apply_history_metadata(imported_message, raw_message, metadata, original_type, outgoing)
    timestamp = parse_timestamp(raw_message[:timestamp]) || imported_message.created_at
    status_name = raw_message.dig(:history_context, :status).to_s.downcase
    status = STATUS_MAP[status_name] || (outgoing ? :delivered : :sent)
    attrs = (imported_message.content_attributes || {}).merge(
      'whatsapp_history_import' => true,
      'whatsapp_history_phase' => metadata[:phase],
      'whatsapp_history_chunk_order' => metadata[:chunk_order],
      'whatsapp_history_progress' => metadata[:progress],
      'whatsapp_history_status' => status_name.presence,
      'whatsapp_history_original_type' => original_type,
      'external_created_at' => timestamp.to_i
    ).compact

    imported_message.update_columns(
      created_at: timestamp,
      updated_at: timestamp,
      status: Message.statuses.fetch(status.to_s),
      content_attributes: attrs
    )
  end

  def normalize_conversation_timestamps(conversation_ids)
    conversation_ids.each do |conversation_id|
      conversation = Conversation.find_by(id: conversation_id)
      next unless conversation

      times = Message.unscoped.where(conversation_id: conversation_id).pick(Arel.sql('MIN(created_at)'), Arel.sql('MAX(created_at)'))
      min_time, max_time = times
      next unless max_time

      updates = { last_activity_at: max_time, updated_at: [conversation.updated_at, max_time].compact.max }
      updates[:created_at] = min_time if min_time && min_time < conversation.created_at
      conversation.update_columns(updates)
    end
  end

  def parse_timestamp(value)
    timestamp = value.to_i
    return if timestamp <= 0

    Time.at(timestamp).utc
  rescue ArgumentError, RangeError
    nil
  end

  def digits(value)
    value.to_s.gsub(/\D/, '')
  end
end
