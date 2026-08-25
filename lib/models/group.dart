class ExpenseGroup {
  const ExpenseGroup({
    required this.id,
    required this.name,
    required this.currencyCode,
    required this.createdBy,
    required this.createdAt,
    this.memberCount,
  });

  final String id;
  final String name;
  final String currencyCode;
  final String createdBy;
  final DateTime createdAt;

  /// Only present in the list endpoint, which is why it is nullable rather
  /// than defaulted to 0. A group with zero members cannot exist — the
  /// creator is added in the same transaction — so 0 would be a lie.
  final int? memberCount;

  factory ExpenseGroup.fromJson(Map<String, dynamic> json) => ExpenseGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        currencyCode: json['currencyCode'] as String,
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        memberCount: json['memberCount'] as int?,
      );
}
