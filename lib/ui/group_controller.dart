import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/expense.dart';
import '../models/group_event.dart';
import '../models/ledger.dart';
import '../repositories/group_events_repository.dart';
import '../repositories/groups_repository.dart';
import '../repositories/ledger_repository.dart';
import 'load_state.dart';

/// Everything one group screen needs, refreshed together.
///
/// The five things this holds are not independent: recording a payment moves
/// the balances AND the settlement AND the history, adding an expense moves
/// the rest. Giving each tab its own loader would guarantee that sooner or
/// later somebody sees a fresh expense list next to a stale balance — and in
/// an app about money, a stale balance is a lie.
///
/// So the rule is simple: anything that writes calls [refresh], and they all
/// go together.
class GroupController extends ChangeNotifier {
  GroupController({
    required GroupsRepository groups,
    required LedgerRepository ledger,
    required GroupEventsRepository events,
    required this.groupId,
    this.myUserId,
  }) {
    detail = Loader(() => groups.detail(groupId));
    expenses = Loader(() => ledger.expenses(groupId));
    balances = Loader(() => ledger.balances(groupId));
    settlement = Loader(() => ledger.settlement(groupId));
    payments = Loader(() => ledger.payments(groupId));

    _events = events.forGroup(groupId).listen(_onEvent);
  }

  final String groupId;

  /// Who is looking, so the server telling us about our own write can be
  /// ignored: we already reloaded when it succeeded.
  final String? myUserId;

  StreamSubscription<GroupEvent>? _events;

  /// The last thing somebody ELSE did here, for the screen to mention.
  ///
  /// Separate from the loaders on purpose. Reloading is what keeps the
  /// numbers honest; this is only so the change does not happen in silence,
  /// and a balance that moved while you were looking at it does not read as
  /// a glitch.
  final ValueNotifier<GroupEvent?> incoming = ValueNotifier(null);

  void _onEvent(GroupEvent event) {
    // Our own echo. The write already refreshed everything it touched.
    if (event.isEchoOf(myUserId)) return;

    incoming.value = event;

    // Somebody joining or leaving moves the member list, which the ledger
    // reload does not cover: their name has to appear in the split editor.
    if (event.movesTheLedger) {
      refreshLedger();
    } else {
      refresh();
    }
  }

  late final Loader<GroupDetail> detail;
  late final Loader<List<Expense>> expenses;
  late final Loader<List<Balance>> balances;
  late final Loader<List<Transfer>> settlement;

  /// Every payment already made in this group.
  ///
  /// Loaded with the rest and never on its own. It is the only place the
  /// ledger's second kind of fact is visible: the balances say what is left,
  /// and this says what was handed over to get there. A payments list that
  /// lagged behind the balances it explains would be worse than not having
  /// one.
  late final Loader<List<Payment>> payments;

  /// Reloads everything at once. The four requests go out together rather
  /// than one after another: they do not depend on each other, so waiting in
  /// sequence would only make the screen slower for no reason.
  Future<void> refresh() => Future.wait([
        detail.load(),
        expenses.load(),
        balances.load(),
        settlement.load(),
        payments.load(),
      ]);

  /// Members alone, for the pickers on the expense and payment forms.
  Future<void> refreshMembers() => detail.load();

  /// After writing an expense or a payment: the ledger moved, so the derived
  /// numbers moved with it. Members did not, so they are left alone.
  Future<void> refreshLedger() => Future.wait([
        expenses.load(),
        balances.load(),
        settlement.load(),
        payments.load(),
      ]);

  @override
  void dispose() {
    // First: a late event arriving into disposed loaders would be a crash on
    // a screen nobody is looking at any more.
    _events?.cancel();
    incoming.dispose();
    detail.dispose();
    expenses.dispose();
    balances.dispose();
    settlement.dispose();
    payments.dispose();
    super.dispose();
  }
}
