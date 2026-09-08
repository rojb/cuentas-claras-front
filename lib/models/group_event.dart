/// Something happened in a group, according to the server.
///
/// A NUDGE, NOT DATA. This carries no amounts, no names and no ids beyond
/// who caused it — on purpose. If an event carried the new balance, the app
/// would have two sources for the same number and they would eventually
/// disagree; instead the reaction to every one of these is to go and read the
/// ledger, which is the only thing that knows.
///
/// That also makes a missed event harmless. A phone that was asleep for an
/// hour reconnects, reloads once, and is completely caught up, because there
/// is no history here to have missed.
class GroupEvent {
  const GroupEvent({
    required this.kind,
    required this.groupId,
    required this.actorId,
    required this.at,
  });

  /// 'expense.created', 'payment.recorded', 'member.joined', and so on.
  ///
  /// A plain String rather than an enum: a server that learns a new kind
  /// tomorrow should make an older app do nothing, not crash on an unknown
  /// value. [movesTheLedger] is where the meaning is decided.
  final String kind;

  final String groupId;

  /// Who caused it, so the client that already knows can skip its own echo.
  final String actorId;

  final DateTime at;

  /// Whether this changes what people owe.
  ///
  /// Everything except somebody joining or leaving does. Those two move the
  /// member list, which is a different reload.
  bool get movesTheLedger => !kind.startsWith('member.');

  /// True when this is the server telling us about something we just did.
  bool isEchoOf(String? userId) => userId != null && actorId == userId;

  /// Returns null for anything that does not parse, because a malformed line
  /// on a stream is not worth taking the screen down for.
  static GroupEvent? tryParse(Object? source) {
    if (source is! Map<String, dynamic>) return null;

    final kind = source['kind'];
    final groupId = source['groupId'];
    final actorId = source['actorId'];
    final at = source['at'];

    if (kind is! String || groupId is! String || actorId is! String) {
      return null;
    }

    return GroupEvent(
      kind: kind,
      groupId: groupId,
      actorId: actorId,
      at: at is String ? (DateTime.tryParse(at) ?? DateTime.now()) : DateTime.now(),
    );
  }
}
