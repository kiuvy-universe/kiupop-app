/// Mirrors components/schemas/AgentSession and friends.
class QuickReply {
  const QuickReply(this.label, this.value);
  factory QuickReply.fromJson(Map<String, dynamic> j) =>
      QuickReply(j['label'] as String, j['value'] as String);
  final String label, value;

  /// The client turns this into an explicit publish confirmation.
  bool get isPublish => value == '__publish__';
}

class KiuQuestion {
  const KiuQuestion({
    required this.field,
    required this.text,
    required this.reason,
    required this.essential,
    required this.quickReplies,
    this.allowUpload = false,
  });
  factory KiuQuestion.fromJson(Map<String, dynamic> j) => KiuQuestion(
    field: j['field'] as String,
    text: j['text'] as String,
    reason: j['reason'] as String? ?? '',
    essential: j['essential'] as bool? ?? false,
    allowUpload: j['allow_upload'] as bool? ?? false,
    quickReplies: [
      for (final q in (j['quick_replies'] as List? ?? const []))
        QuickReply.fromJson(q as Map<String, dynamic>),
    ],
  );
  final String field, text, reason;
  final bool essential;

  /// Optional catalog upload (Excel/CSV/text); only for the online-store flow.
  final bool allowUpload;
  final List<QuickReply> quickReplies;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromKiu,
    required this.text,
    required this.kind,
    required this.quickReplies,
    this.question,
    this.brainMode,
  });
  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final meta = j['meta'] as Map<String, dynamic>? ?? const {};
    final q = meta['question'] as Map<String, dynamic>?;
    return ChatMessage(
      id: j['id'] as int,
      fromKiu: j['role'] == 'kiu',
      text: j['text'] as String,
      kind: meta['kind'] as String? ?? '',
      question: q == null ? null : KiuQuestion.fromJson(q),
      quickReplies: [
        for (final r in (meta['quick_replies'] as List? ?? const []))
          QuickReply.fromJson(r as Map<String, dynamic>),
      ],
      brainMode: meta['brain_mode'] as String?,
    );
  }
  final int id;
  final bool fromKiu;
  final String text, kind;
  final KiuQuestion? question;
  final List<QuickReply> quickReplies;
  final String? brainMode;
}

class BuildTask {
  const BuildTask(this.key, this.label, this.status);
  factory BuildTask.fromJson(Map<String, dynamic> j) => BuildTask(
    j['key'] as String,
    j['label'] as String,
    j['status'] as String,
  );
  final String key, label, status;
  bool get done =>
      status == 'done' || status == 'skipped' || status == 'failed';
}

class MissingItem {
  const MissingItem(this.field, this.message);
  final String field, message;
}

class PublishResult {
  const PublishResult({
    required this.slug,
    required this.version,
    required this.shareUrl,
  });
  factory PublishResult.fromJson(Map<String, dynamic> j) => PublishResult(
    slug: j['slug'] as String,
    version: j['version'] as int,
    shareUrl: j['share_url'] as String,
  );
  final String slug, shareUrl;
  final int version;
}

/// A file shared with Kiu and what Kiu did with it.
class SharedFile {
  const SharedFile({
    required this.id,
    required this.kind,
    required this.filename,
    required this.status,
    required this.note,
    this.sizeBytes = 0,
  });
  factory SharedFile.fromJson(Map<String, dynamic> j) => SharedFile(
    id: j['id'] as String,
    kind: j['kind'] as String,
    filename: j['filename'] as String,
    status: j['status'] as String,
    note: j['note'] as String? ?? '',
    sizeBytes: j['size_bytes'] as int? ?? 0,
  );
  final String id, kind, filename, status, note;
  final int sizeBytes;
  bool get busy => status == 'received' || status == 'processing';
}

class AgentSession {
  const AgentSession({
    required this.id,
    required this.status,
    required this.revision,
    required this.messages,
    required this.pending,
    required this.percent,
    required this.tasks,
    required this.ready,
    required this.missing,
    required this.businessName,
    required this.template,
    required this.templateReason,
    required this.aiMode,
    required this.aiCostMicros,
    required this.lastEventId,
    required this.toReadyMs,
    required this.slug,
    required this.publication,
    this.files = const [],
    this.maxFiles = 5,
    this.maxFileBytes = 50 << 20,
    this.filesEnabled = false,
    this.paywall = PaywallInfo.off,
  });

  factory AgentSession.fromJson(Map<String, dynamic> j) {
    final progress = j['progress'] as Map<String, dynamic>;
    final readiness = j['readiness'] as Map<String, dynamic>;
    final summary = j['summary'] as Map<String, dynamic>;
    final ai = j['ai'] as Map<String, dynamic>;
    final pending = j['pending_question'] as Map<String, dynamic>?;
    final pub = j['publication'] as Map<String, dynamic>?;
    final store = j['store'] as Map<String, dynamic>?;
    return AgentSession(
      id: j['id'] as String,
      status: j['status'] as String,
      revision: j['revision'] as int,
      messages: [
        for (final m in j['messages'] as List)
          ChatMessage.fromJson(m as Map<String, dynamic>),
      ],
      pending: pending == null ? null : KiuQuestion.fromJson(pending),
      percent: progress['percent'] as int,
      tasks: [
        for (final t in progress['tasks'] as List)
          BuildTask.fromJson(t as Map<String, dynamic>),
      ],
      ready: readiness['ready'] as bool && progress['ready'] as bool,
      missing: [
        for (final m in readiness['missing'] as List)
          MissingItem(
            (m as Map<String, dynamic>)['field'] as String,
            m['message'] as String,
          ),
      ],
      businessName: summary['business_name'] as String? ?? '',
      template: summary['template'] as String? ?? '',
      templateReason: summary['template_reason'] as String? ?? '',
      aiMode: ai['mode'] as String? ?? 'local',
      aiCostMicros: ai['cost_micros'] as int? ?? 0,
      lastEventId: j['last_event_id'] as int? ?? 0,
      toReadyMs:
          (j['timing'] as Map<String, dynamic>?)?['first_message_to_ready_ms']
              as int?,
      slug: store?['slug'] as String?,
      publication: pub == null ? null : PublishResult.fromJson(pub),
      files: [
        for (final a in (j['attachments'] as List? ?? const []))
          SharedFile.fromJson(a as Map<String, dynamic>),
      ],
      maxFiles:
          (j['limits'] as Map<String, dynamic>?)?['max_attachments'] as int? ??
          5,
      maxFileBytes:
          (j['limits'] as Map<String, dynamic>?)?['max_attachments_bytes']
              as int? ??
          50 << 20,
      filesEnabled:
          (j['limits'] as Map<String, dynamic>?)?['attachments_enabled']
              as bool? ??
          false,
      paywall: j['paywall'] == null
          ? PaywallInfo.off
          : PaywallInfo.fromJson(j['paywall'] as Map<String, dynamic>),
    );
  }

  /// Quiz-funnel paywall state (the server enforces it on publish).
  final PaywallInfo paywall;

  /// True when publishing must first go through the paywall.
  bool get needsPlan => paywall.required && !paywall.active;

  final String id, status, businessName, template, templateReason, aiMode;
  final int revision, percent, aiCostMicros, lastEventId;
  final List<ChatMessage> messages;
  final KiuQuestion? pending;
  final List<BuildTask> tasks;
  final bool ready;
  final List<MissingItem> missing;
  final int? toReadyMs;
  final String? slug;
  final PublishResult? publication;
  final List<SharedFile> files;
  final int maxFiles, maxFileBytes;
  final bool filesEnabled;

  bool get published => status == 'published';
  bool get started => messages.any((m) => !m.fromKiu);
}

class AgentEvent {
  const AgentEvent(this.id, this.type);
  factory AgentEvent.fromJson(Map<String, dynamic> j) =>
      AgentEvent(j['id'] as int, j['type'] as String);
  final int id;
  final String type;
}

/// Paywall of the quiz funnel: seeing the store is free; publishing it needs
/// the US\$5/month plan per active store. Test mode only: no real money.
class PaywallInfo {
  const PaywallInfo({
    required this.required,
    required this.active,
    required this.priceMinor,
    required this.currency,
    required this.mode,
    required this.notice,
  });

  factory PaywallInfo.fromJson(Map<String, dynamic> j) => PaywallInfo(
    required: j['required'] as bool? ?? false,
    active: j['active'] as bool? ?? false,
    priceMinor: j['price_minor'] as int? ?? 500,
    currency: j['currency'] as String? ?? 'USD',
    mode: j['mode'] as String? ?? 'test',
    notice: j['notice'] as String? ?? '',
  );

  static const off = PaywallInfo(
    required: false,
    active: false,
    priceMinor: 500,
    currency: 'USD',
    mode: 'test',
    notice: '',
  );

  final bool required, active;
  final int priceMinor;
  final String currency, mode, notice;

  bool get isTest => mode == 'test';

  /// "US\$5" for 500 USD minor units (whole dollars shown without decimals).
  String get priceLabel {
    final whole = priceMinor ~/ 100, cents = priceMinor % 100;
    final amount = cents == 0
        ? '$whole'
        : '$whole.${cents.toString().padLeft(2, '0')}';
    return currency == 'USD' ? 'US\$$amount' : '$amount $currency';
  }
}
