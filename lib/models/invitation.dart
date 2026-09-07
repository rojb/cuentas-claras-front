/// An invitation, as the person who received it sees it.
///
/// It carries the group's name and the inviter's, not just their ids. You
/// cannot read a group you have not joined yet, so if this object did not
/// bring the context with it there would be no way to render the one screen
/// it exists for: an invitation shown as two uuids is not something anybody
/// can say yes or no to.
class Invitation {
  const Invitation({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.currencyCode,
    required this.invitedByName,
    required this.memberCount,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String currencyCode;
  final String invitedByName;
  final int memberCount;
  final DateTime createdAt;

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        groupName: json['groupName'] as String,
        currencyCode: json['currencyCode'] as String,
        invitedByName: json['invitedByName'] as String,
        memberCount: json['memberCount'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Somebody the group has asked and is still waiting on.
///
/// Deliberately not a GroupMember. They are not one — the ledger cannot name
/// them, no expense can be charged to them, and the whole point of the
/// invitation is that this is still an open question.
class PendingGuest {
  const PendingGuest({
    required this.invitationId,
    required this.userId,
    required this.email,
    required this.displayName,
    required this.invitedAt,
  });

  final String invitationId;
  final String userId;
  final String email;
  final String displayName;
  final DateTime invitedAt;

  factory PendingGuest.fromJson(Map<String, dynamic> json) => PendingGuest(
        invitationId: json['invitationId'] as String,
        userId: json['userId'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        invitedAt: DateTime.parse(json['invitedAt'] as String),
      );
}

/// Who an invitation was just sent to, straight from the server's answer.
class InvitedPerson {
  const InvitedPerson({
    required this.userId,
    required this.email,
    required this.displayName,
  });

  final String userId;
  final String email;
  final String displayName;

  factory InvitedPerson.fromJson(Map<String, dynamic> json) => InvitedPerson(
        userId: json['userId'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
      );
}
