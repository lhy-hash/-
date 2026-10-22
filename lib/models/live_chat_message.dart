enum ChatRole { user, ai, system }

enum ChatInputType { text, voice }

class LiveChatMessage {
  LiveChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.inputType,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final ChatRole role;
  final String text;
  final ChatInputType inputType;
  final DateTime createdAt;

  bool get isAi => role == ChatRole.ai;
  bool get isUser => role == ChatRole.user;
}
