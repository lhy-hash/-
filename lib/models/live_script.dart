enum LiveScriptCategory { localLife, ecommerce, knowledge }

class LiveScript {
  LiveScript({
    required this.id,
    required this.title,
    required this.category,
    required this.content,
    required this.durationMinutes,
    this.tags = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String title;
  final LiveScriptCategory category;
  final String content;
  final int durationMinutes;
  final List<String> tags;
  final DateTime updatedAt;

  LiveScript copyWith({
    String? title,
    LiveScriptCategory? category,
    String? content,
    int? durationMinutes,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return LiveScript(
      id: id,
      title: title ?? this.title,
      category: category ?? this.category,
      content: content ?? this.content,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get categoryLabel => switch (category) {
        LiveScriptCategory.localLife => '本地生活',
        LiveScriptCategory.ecommerce => '电商带货',
        LiveScriptCategory.knowledge => '知识口播',
      };
}
