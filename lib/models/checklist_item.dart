enum ChecklistKind { required, recommended }

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    this.checked = false,
  });

  final String id;
  final String title;
  final String description;
  final ChecklistKind kind;
  final bool checked;

  ChecklistItem copyWith({bool? checked}) {
    return ChecklistItem(
      id: id,
      title: title,
      description: description,
      kind: kind,
      checked: checked ?? this.checked,
    );
  }
}
