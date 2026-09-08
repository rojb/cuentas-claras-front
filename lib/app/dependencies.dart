import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/session.dart';
import '../repositories/auth_repository.dart';
import '../repositories/groups_repository.dart';
import '../repositories/ledger_repository.dart';
import '../repositories/rate_repository.dart';

/// Everything the app needs, built once and handed down the tree.
///
/// An InheritedWidget, not a global singleton and not a service locator. The
/// difference matters: dependencies arrive through the widget tree, so a
/// screen cannot reach for something that was never provided, and pointing
/// the whole app at a different backend is changing one constructor call.
class Dependencies extends InheritedWidget {
  Dependencies({super.key, required super.child, this.baseUrl})
      : session = Session() {
    api = ApiClient(session: session, baseUrl: baseUrl);
    auth = AuthRepository(api, session);
    groups = GroupsRepository(api);
    ledger = LedgerRepository(api);
    rates = RateRepository(api);
  }

  final String? baseUrl;

  final Session session;
  late final ApiClient api;
  late final AuthRepository auth;
  late final GroupsRepository groups;
  late final LedgerRepository ledger;
  late final RateRepository rates;

  /// Looks the dependencies up WITHOUT subscribing to them.
  ///
  /// The obvious call here is dependOnInheritedWidgetOfExactType, and it is
  /// wrong twice over. It registers the widget to rebuild when this changes,
  /// which never happens — [updateShouldNotify] returns false, because these
  /// objects are built once and live as long as the app. And Flutter forbids
  /// registering a dependency from initState, so every screen that grabs a
  /// repository there would throw on its very first frame.
  ///
  /// getInheritedWidgetOfExactType is the read-only version: no subscription,
  /// legal from initState.
  static Dependencies of(BuildContext context) {
    final found = context.getInheritedWidgetOfExactType<Dependencies>();

    // Reaching here means a screen was pushed outside the app's tree. That is
    // a wiring mistake, not something to degrade gracefully around.
    assert(found != null, 'No Dependencies found above this widget');
    return found!;
  }

  @override
  bool updateShouldNotify(Dependencies oldWidget) => false;
}
