import '../api/api_client.dart';
import '../api/group_event_stream.dart';
import '../api/session.dart';
import '../models/group_event.dart';

/// The live stream of things happening in a group.
///
/// It exists to save the other person from pulling down to find out. Nothing
/// depends on it: every event's meaning is "go and read the ledger again",
/// and the ledger is where it always was. Turn this off and the app is the
/// one from last week, not a broken one.
class GroupEventsRepository {
  const GroupEventsRepository(this._api, this._session);

  final ApiClient _api;
  final Session _session;

  /// Events for one group, or an empty stream when nobody is signed in.
  ///
  /// THE TOKEN GOES IN THE QUERY STRING, and only here. EventSource has no
  /// way to set an Authorization header — the browser API simply does not
  /// take one — so the choice is this or an unauthenticated stream of a
  /// group's private activity. The server accepts a query token on this one
  /// route and nowhere else, for exactly that reason.
  Stream<GroupEvent> forGroup(String groupId) {
    final token = _session.token;
    if (token == null) return const Stream.empty();

    final url = Uri.parse('${_api.baseUrl}/groups/$groupId/events')
        .replace(queryParameters: {'access_token': token});

    return openGroupEvents(url);
  }
}
