/// "Juan Perez" -> "JP". For avatars, before there are avatars.
String initialsOf(String displayName) {
  final words = displayName.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return '?';
  if (words.length == 1) return words.first[0].toUpperCase();
  return (words.first[0] + words.last[0]).toUpperCase();
}

class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
  });

  final String id;
  final String email;
  final String displayName;

  String get initials => initialsOf(displayName);

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
      );
}

/// A user seen through a group: the same person, plus when they joined.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.joinedAt,
  });

  final String userId;
  final String email;
  final String displayName;
  final DateTime joinedAt;

  String get initials => initialsOf(displayName);

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        userId: json['userId'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        joinedAt: DateTime.parse(json['joinedAt'] as String),
      );
}
