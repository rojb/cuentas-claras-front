import '../api/api_client.dart';
import '../models/group.dart';
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

  /// Adds a friend by email. The server is idempotent about this: adding
  /// somebody twice answers 200 instead of 201 and changes nothing, so a
  /// retry over a bad connection is safe.
  Future<GroupMember> addMember({
    required String groupId,
    required String email,
  }) async {
    final response = await _api.post(
      '/groups/$groupId/members',
      body: {'email': email},
    ) as Map<String, dynamic>;

    return GroupMember.fromJson(response['member'] as Map<String, dynamic>);
  }
}
