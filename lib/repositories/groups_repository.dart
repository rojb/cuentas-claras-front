import '../api/api_client.dart';
import '../models/group.dart';
import '../models/invitation.dart';
import '../models/user.dart';

class GroupDetail {
  const GroupDetail({required this.group, required this.members});

  final ExpenseGroup group;
  final List<GroupMember> members;

  /// Names by id, which is what almost every screen actually needs: the API
  /// speaks in uuids and people do not.
  Map<String, GroupMember> get byId => {
        for (final member in members) member.userId: member,
      };

  String nameOf(String userId) => byId[userId]?.displayName ?? 'alguien';
}

class GroupsRepository {
  const GroupsRepository(this._api);

  final ApiClient _api;

  Future<List<ExpenseGroup>> myGroups() async {
    final response = await _api.get('/groups') as Map<String, dynamic>;
    final groups = response['groups'] as List<dynamic>;

    return groups
        .whereType<Map<String, dynamic>>()
        .map(ExpenseGroup.fromJson)
        .toList();
  }

  Future<ExpenseGroup> create({
    required String name,
    required String currencyCode,
  }) async {
    final response = await _api.post('/groups', body: {
      'name': name,
      'currencyCode': currencyCode,
    }) as Map<String, dynamic>;

    return ExpenseGroup.fromJson(response['group'] as Map<String, dynamic>);
  }

  Future<GroupDetail> detail(String groupId) async {
    final response = await _api.get('/groups/$groupId') as Map<String, dynamic>;
    final members = response['members'] as List<dynamic>;

    return GroupDetail(
      group: ExpenseGroup.fromJson(response['group'] as Map<String, dynamic>),
      members: members
          .whereType<Map<String, dynamic>>()
          .map(GroupMember.fromJson)
          .toList(),
    );
  }

  /// Invites a friend by email. It does NOT add them: nobody joins a group
  /// without saying yes, so what comes back is a question, not a member.
  ///
  /// The server is idempotent about this: asking twice answers 200 instead of
  /// 201 and reuses the invitation that is already open, so a retry over a
  /// bad connection cannot turn into two of them.
  Future<InvitedPerson> invite({
    required String groupId,
    required String email,
  }) async {
    final response = await _api.post(
      '/groups/$groupId/invitations',
      body: {'email': email},
    ) as Map<String, dynamic>;

    return InvitedPerson.fromJson(response['invitee'] as Map<String, dynamic>);
  }

  /// Who this group has asked and is still waiting on.
  Future<List<PendingGuest>> pendingGuests(String groupId) async {
    final response =
        await _api.get('/groups/$groupId/invitations') as Map<String, dynamic>;

    return (response['invitations'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(PendingGuest.fromJson)
        .toList();
  }

  /// Everything waiting for MY answer.
  ///
  /// Not under /groups: you cannot read a group you have not joined, and the
  /// whole point of an invitation is that it reaches you before that.
  Future<List<Invitation>> myInvitations() async {
    final response = await _api.get('/invitations') as Map<String, dynamic>;

    return (response['invitations'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Invitation.fromJson)
        .toList();
  }

  /// Says yes, and comes back with the group that was just joined.
  Future<ExpenseGroup> acceptInvitation(String invitationId) async {
    final response = await _api.post('/invitations/$invitationId/accept')
        as Map<String, dynamic>;

    return ExpenseGroup.fromJson(response['group'] as Map<String, dynamic>);
  }

  /// Says no. 204, so there is nothing to hand back.
  Future<void> rejectInvitation(String invitationId) =>
      _api.post('/invitations/$invitationId/reject');

  /// Leaves the group.
  ///
  /// Answers 204 with no body, so there is nothing to return and nothing to
  /// decode — [ApiClient] already knows that a successful DELETE says nothing.
  ///
  /// The one answer worth knowing about is 409 `balance_not_settled`. The
  /// server refuses to let anybody leave with an open balance, because the
  /// debt would not disappear with them: it would stay in the group with
  /// nobody attached to it. That is a rule, not a failure, and the screen
  /// treats it as one.
  Future<void> leave(String groupId) =>
      _api.delete('/groups/$groupId/members/me');
}
