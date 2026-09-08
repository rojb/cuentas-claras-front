import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../app/dependencies.dart';
import '../../models/expense.dart';
import '../../models/group.dart';
import '../../models/invitation.dart';
import '../../models/ledger.dart';
import '../../models/money.dart';
import '../../models/user.dart';
import '../../repositories/groups_repository.dart';
import '../group_controller.dart';
import '../widgets/failure_view.dart';
import '../widgets/load_state_view.dart';
import '../widgets/person_avatar.dart';
import 'add_expense_screen.dart';
import 'record_payment_sheet.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.group});

  final ExpenseGroup group;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late final GroupController _controller;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    _controller = GroupController(
      groups: dependencies.groups,
      ledger: dependencies.ledger,
      groupId: widget.group.id,
    );
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// What the group has been spending in lately, so the expense form opens on
  /// the common case instead of a blank one. Read off the ledger rather than
  /// remembered anywhere: whatever these people actually used last is the
  /// best guess available.
  ///
  /// The rate is NOT carried across any more — the form fetches a live one
  /// from Binance instead of reusing whatever was last typed.
  String? get _recentCurrency {
    final expenses = _controller.expenses.state.valueOrNull ?? const <Expense>[];
    return expenses.isEmpty ? null : expenses.first.currencyCode;
  }

  /// The signed-in user, and whether they created this group.
  ///
  /// "Anfitrión" is not a role in the schema and does not need to be: the
  /// group already records who made it, and that is the person with a reason
  /// to fix the ledger on everybody's behalf.
  String? get _me => Dependencies.of(context).session.userId;
  bool get _iAmTheHost => _me != null && _me == widget.group.createdBy;

  /// Opens the expense form, blank to add one or filled in to correct one.
  Future<void> _editExpense([Expense? existing]) async {
    final members = _controller.detail.state.valueOrNull?.members;
    if (members == null || members.isEmpty) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          groupId: widget.group.id,
          members: members,
          editing: existing,
          recentCurrency: _recentCurrency,
        ),
      ),
    );

    if (saved ?? false) await _controller.refreshLedger();
  }

  /// Deletes an expense, after asking.
  ///
  /// Returns whether it is gone, because Dismissible needs to know: a swipe
  /// that gets cancelled has to put the row back.
  Future<bool> _deleteExpense(Expense expense) async {
    final ledger = Dependencies.of(context).ledger;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar el gasto?'),
        content: Text(
          '"${expense.description}" deja de contar y los saldos se '
          'recalculan sin él.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await ledger.deleteExpense(
        groupId: widget.group.id,
        expenseId: expense.id,
      );
      await _controller.refreshLedger();
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
      return false;
    }
  }

  /// Takes a payment back out of the ledger.
  ///
  /// The button that leads here is only drawn for people allowed to use it,
  /// but that is a courtesy, not the rule: the server checks again and
  /// answers 403 either way. A UI check is a hint, never a lock.
  Future<void> _deletePayment(Payment payment) async {
    final ledger = Dependencies.of(context).ledger;
    final names = _controller.detail.state.valueOrNull;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar el pago?'),
        content: Text(
          'El pago de ${names?.nameOf(payment.fromUserId) ?? 'alguien'} a '
          '${names?.nameOf(payment.toUserId) ?? 'alguien'} por '
          '${payment.inUsdt.format()} deja de contar, y los saldos vuelven a '
          'incluir esa deuda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ledger.deletePayment(
        groupId: widget.group.id,
        paymentId: payment.id,
      );
      await _controller.refreshLedger();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
    }
  }

  /// Invites somebody. Nobody is added by this: what it sends is a question.
  ///
  /// So the confirmation says "se le envió la invitación" and not "se sumó al
  /// grupo" — the second would be a lie until the other person answers, and
  /// the member list deliberately will not have changed.
  Future<void> _invitePerson() async {
    // Captured BEFORE the await: after it, this State may no longer be in the
    // tree and its context would be dead.
    final groups = Dependencies.of(context).groups;

    final email = await showDialog<String>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );

    if (email == null) return;

    try {
      final invitee = await groups.invite(
        groupId: widget.group.id,
        email: email,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se le envió la invitación a ${invitee.displayName}'),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
    }
  }

  /// Who is in the group, and who was asked and has not answered yet.
  ///
  /// This exists because inviting is now invisible: the member list does not
  /// move, and a snackbar that disappears in four seconds is not somewhere to
  /// check whether the invitation is still out there. Without this, "¿le
  /// llegó?" has no answer inside the app.
  Future<void> _showMembers() async {
    final groups = Dependencies.of(context).groups;
    final members = _controller.detail.state.valueOrNull?.members;

    final pending = await groups
        .pendingGuests(widget.group.id)
        // A group that cannot report its pending guests is not a reason to
        // refuse to show its members.
        .catchError((_) => <PendingGuest>[]);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Integrantes'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final member in members ?? const <GroupMember>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PersonAvatar(
                    userId: member.userId,
                    initials: member.initials,
                  ),
                  title: Text(member.displayName),
                  subtitle: Text(member.email),
                ),
              if (pending.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Invitaciones sin responder',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                for (final guest in pending)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.hourglass_empty, size: 18),
                    ),
                    title: Text(guest.displayName),
                    subtitle: Text(guest.email),
                    trailing: const Text('Pendiente'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Leaves the group, after asking, and goes back to the list.
  ///
  /// The happy path is the boring one. What this method really exists for is
  /// the refusal: the server does not let anybody leave with an open balance,
  /// and that answer needs to be explained, not reported. A red snackbar
  /// saying "algo salió mal" would be a lie — nothing went wrong, the person
  /// simply owes money.
  ///
  /// Which is why it branches on `code` and not on the message. The server's
  /// text is English and counts in cents; the wording a person reads belongs
  /// on this side, exactly like describeFailure() argues.
  Future<void> _leaveGroup(TabController tabs) async {
    // All captured BEFORE the first await: this State may be gone by the time
    // the dialog closes, and a dead context cannot look anything up.
    final groups = Dependencies.of(context).groups;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir del grupo?'),
        content: Text(
          'Vas a dejar de ver "${widget.group.name}" y sus gastos. Lo que ya '
          'pagaste y lo que ya te cobraron sigue en el historial del grupo: '
          'salir no borra nada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await groups.leave(widget.group.id);
      // true so the list behind knows it is stale: the group is not ours any
      // more and has to stop being drawn.
      navigator.pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == 'balance_not_settled') {
        await _explainOpenBalance(tabs);
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
    }
  }

  /// The signed-in user's own balance in this group, if it is loaded.
  ///
  /// Null covers two different things on purpose — nobody signed in, and a
  /// ledger that has not come back — because the caller reacts to both the
  /// same way: say the rule without naming a figure. An amount that might be
  /// wrong is worth less here than no amount at all.
  Balance? _myBalance() {
    final me = Dependencies.of(context).session.userId;
    if (me == null) return null;

    final balances = _controller.balances.state.valueOrNull;
    if (balances == null) return null;

    for (final balance in balances) {
      if (balance.userId == me) return balance;
    }
    return null;
  }

  /// The 409, told as what it is: a rule, with the number and the way out.
  ///
  /// The balances are reloaded before anything is drawn. The server refused
  /// based on what the ledger says at this instant, and explaining that
  /// refusal with a figure this screen happened to be holding from a minute
  /// ago would be worse than showing no figure — it would be an explanation
  /// that does not match its own reason.
  ///
  /// Sending somebody to the Liquidar tab is the other half. An explanation
  /// that ends in a dead end is only half an answer, and that tab already
  /// knows exactly who has to pay whom.
  Future<void> _explainOpenBalance(TabController tabs) async {
    await _controller.refreshLedger();
    if (!mounted) return;

    final mine = _myBalance();

    final settleUp = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.account_balance_wallet_outlined),
        title: Text(_openBalanceTitle(mine)),
        content: Text(_openBalanceBody(mine)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Entendido'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ver cómo saldar'),
          ),
        ],
      ),
    );

    if (settleUp ?? false) tabs.animateTo(2);
  }

  String _openBalanceTitle(Balance? mine) {
    if (mine == null || mine.isSettled) return 'Todavía hay cuentas pendientes';

    final amount = mine.amount.absolute.format();

    // The direction changes what the person has to DO, so it changes the
    // sentence. "Tenés un saldo abierto" would make somebody who is owed
    // money go looking for their wallet.
    return mine.owes ? 'Todavía debés $amount' : 'Todavía te deben $amount';
  }

  String _openBalanceBody(Balance? mine) {
    const rule =
        'No se puede salir de un grupo con saldo abierto. La deuda no se iría '
        'con vos: quedaría en el grupo sin nadie a quien cobrarle o a quien '
        'pagarle.';

    if (mine == null || mine.isSettled) {
      return '$rule\n\nSaldá lo que falte y volvé a intentarlo.';
    }

    return mine.owes
        ? '$rule\n\nPagá lo que debés y volvé a intentarlo.'
        : '$rule\n\nCobrá lo que te deben y volvé a intentarlo.';
  }

  Future<void> _recordPayment({Transfer? suggestion}) async {
    final detail = _controller.detail.state.valueOrNull;
    if (detail == null) return;

    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordPaymentSheet(
        groupId: widget.group.id,
        members: detail.members,
        suggestion: suggestion,
        me: _me,
        // The host can write down a payment between any two people. Everybody
        // else has to be one of the two, and the form says so rather than
        // letting them fill it in and collect a 403.
        isHost: _iAmTheHost,
      ),
    );

    if (recorded ?? false) await _controller.refreshLedger();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.group.name),
          actions: [
            IconButton(
              tooltip: 'Invitar a alguien',
              icon: const Icon(Icons.person_add_alt),
              onPressed: _invitePerson,
            ),
            // A Builder so this sits BELOW the DefaultTabController and can
            // read it. That is what lets the "cuentas pendientes" dialog send
            // somebody straight to the Liquidar tab instead of leaving them to
            // find it. Leaving is also destructive and irreversible-ish, so it
            // lives behind a menu: an icon next to "Agregar a alguien" is one
            // mis-tap away from a goodbye nobody meant.
            Builder(
              builder: (context) {
                final tabs = DefaultTabController.of(context);
                final colors = Theme.of(context).colorScheme;

                return PopupMenuButton<void>(
                  tooltip: 'Más opciones',
                  itemBuilder: (context) => [
                    PopupMenuItem<void>(
                      onTap: _showMembers,
                      child: const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.group_outlined),
                        title: Text('Ver integrantes'),
                      ),
                    ),
                    PopupMenuItem<void>(
                      onTap: () => _leaveGroup(tabs),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.logout, color: colors.error),
                        title: Text(
                          'Salir del grupo',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Gastos'),
              Tab(text: 'Saldos'),
              Tab(text: 'Liquidar'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _editExpense,
          icon: const Icon(Icons.add),
          label: const Text('Gasto'),
        ),
        body: ListenableBuilder(
          listenable: _controller.detail,
          builder: (context, _) {
            final detail = _controller.detail.state.valueOrNull;

            return TabBarView(
              children: [
                _ExpensesTab(
                  controller: _controller,
                  detail: detail,
                  onEdit: _editExpense,
                  onDelete: _deleteExpense,
                ),
                // No currency passed to either of these on purpose. A
                // balance and a transfer are ALWAYS in USDT — that is the
                // unit the ledger settles in, and the only one in which
                // three currencies of spending can add up to zero.
                _BalancesTab(
                  controller: _controller,
                  detail: detail,
                ),
                _SettleTab(
                  controller: _controller,
                  detail: detail,
                  onPay: (transfer) => _recordPayment(suggestion: transfer),
                  // Offering "Registrar" on a transfer this person is not
                  // allowed to write down would be handing them a button
                  // that answers 403. Both ends of it count: the one who owes
                  // it and the one waiting to be paid.
                  canRecord: (transfer) =>
                      _iAmTheHost ||
                      transfer.fromUserId == _me ||
                      transfer.toUserId == _me,
                ),
                // The ledger's second kind of fact. The other three tabs are
                // all derived from expenses; this is the only place the
                // payments that moved them are visible on their own.
                _HistoryTab(
                  controller: _controller,
                  detail: detail,
                  me: _me,
                  groupCreatedBy: widget.group.createdBy,
                  onDelete: _deletePayment,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExpensesTab extends StatelessWidget {
  const _ExpensesTab({
    required this.controller,
    required this.detail,
    required this.onEdit,
    required this.onDelete,
  });

  final GroupController controller;
  final GroupDetail? detail;
  final void Function(Expense expense) onEdit;
  final Future<bool> Function(Expense expense) onDelete;

  @override
  Widget build(BuildContext context) {
    return LoadStateView<List<Expense>>(
      loader: controller.expenses,
      builder: (context, expenses) {
        if (expenses.isEmpty) {
          return const EmptyView(
            icon: Icons.receipt_long_outlined,
            title: 'Todavía no hay gastos',
            subtitle: 'Cargá el primero y los saldos salen solos.',
          );
        }

        return RefreshIndicator(
          onRefresh: controller.refreshLedger,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: expenses.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final expense = expenses[index];
              final payer = detail?.nameOf(expense.paidBy) ?? '...';
              final count = expense.shares.length;

              // Keyed by expense id, not by index: after a delete the list
              // shifts, and an index key would make Flutter animate away the
              // wrong row.
              return Dismissible(
                key: ValueKey(expense.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => onDelete(expense),
                background: ColoredBox(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: const Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: 24),
                      child: Icon(Icons.delete_outline),
                    ),
                  ),
                ),
                child: ListTile(
                  leading: Icon(_iconFor(expense.splitStrategy)),
                  title: Text(expense.description),
                  subtitle: Text(
                    'Pagó $payer · ${_labelFor(expense.splitStrategy)} · '
                    '${count == 1 ? '1 persona' : '$count personas'}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        expense.total.format(
                          currencyCode: expense.currencyCode,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      // What it weighs in the ledger. Only when it is not
                      // already the same number, because "USDT 10,00" twice
                      // is noise.
                      ?(expense.isAlreadySettlementCurrency
                          ? null
                          : Text(
                              expense.totalInUsdt.format(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            )),
                    ],
                  ),
                  onTap: () => _showExpenseDetail(
                    context,
                    expense: expense,
                    detail: detail,
                    onEdit: onEdit,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  static IconData _iconFor(String strategy) => switch (strategy) {
        'equally' => Icons.balance,
        'exact_amounts' => Icons.tag,
        'percentages' => Icons.percent,
        'shares' => Icons.pie_chart_outline,
        'mixed' => Icons.call_split,
        'items' => Icons.list_alt,
        _ => Icons.receipt,
      };

  /// The strategy arrives as the snake_case string the database stores. It is
  /// an identifier, not text: it stays in English on the wire and gets its
  /// wording here, the same way error codes do.
  static String _labelFor(String strategy) => switch (strategy) {
        'equally' => 'partes iguales',
        'exact_amounts' => 'montos exactos',
        'percentages' => 'por porcentaje',
        'shares' => 'por partes',
        'mixed' => 'mixta',
        'items' => 'por ítems',
        _ => strategy,
      };
}

class _BalancesTab extends StatelessWidget {
  const _BalancesTab({
    required this.controller,
    required this.detail,
  });

  final GroupController controller;
  final GroupDetail? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoadStateView<List<Balance>>(
      loader: controller.balances,
      builder: (context, balances) {
        // Everybody square, or nothing spent yet. Either way there is nothing
        // to show but the good news.
        if (balances.every((balance) => balance.isSettled)) {
          return const EmptyView(
            icon: Icons.check_circle_outline,
            title: 'Todo saldado',
            subtitle: 'Nadie le debe nada a nadie.',
          );
        }

        final sorted = [...balances]
          ..sort((a, b) => b.amount.cents.compareTo(a.amount.cents));

        return RefreshIndicator(
          onRefresh: controller.refreshLedger,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final balance = sorted[index];
              final member = detail?.byId[balance.userId];

              final colour = balance.isSettled
                  ? theme.colorScheme.outline
                  : balance.isOwed
                      ? Colors.green.shade700
                      : theme.colorScheme.error;

              return ListTile(
                leading: PersonAvatar(
                  userId: balance.userId,
                  initials: member?.initials ?? '?',
                ),
                title: Text(member?.displayName ?? 'Alguien'),
                subtitle: Text(
                  balance.isSettled
                      ? 'está a mano'
                      : balance.isOwed
                          ? 'le deben'
                          : 'debe',
                ),
                trailing: Text(
                  balance.amount.absolute.format(),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: colour, fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SettleTab extends StatelessWidget {
  const _SettleTab({
    required this.controller,
    required this.detail,
    required this.onPay,
    required this.canRecord,
  });

  final GroupController controller;
  final GroupDetail? detail;
  final void Function(Transfer transfer) onPay;

  /// Whether the person looking at this may write down that this particular
  /// transfer happened.
  final bool Function(Transfer transfer) canRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoadStateView<List<Transfer>>(
      loader: controller.settlement,
      builder: (context, transfers) {
        if (transfers.isEmpty) {
          return const EmptyView(
            icon: Icons.done_all,
            title: 'Nada para liquidar',
            subtitle: 'Están todos en cero.',
          );
        }

        return RefreshIndicator(
          onRefresh: controller.refreshLedger,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  transfers.length == 1
                      ? 'Con una sola transferencia queda todo saldado.'
                      : 'Con ${transfers.length} transferencias queda todo '
                          'saldado.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              for (final transfer in transfers)
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: PersonAvatar(
                      userId: transfer.fromUserId,
                      initials:
                          detail?.byId[transfer.fromUserId]?.initials ?? '?',
                    ),
                    title: Text(
                      '${detail?.nameOf(transfer.fromUserId) ?? '...'}  →  '
                      '${detail?.nameOf(transfer.toUserId) ?? '...'}',
                    ),
                    subtitle: Text(
                      transfer.amount.format(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    trailing: canRecord(transfer)
                        ? FilledButton.tonal(
                            onPressed: () => onPay(transfer),
                            child: const Text('Registrar'),
                          )
                        : null,
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Podés pagar menos de lo sugerido: registrá lo que '
                  'realmente se entregó y los saldos van a mostrar lo que '
                  'falta.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invitar a alguien'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Le va a llegar una invitación que puede aceptar o rechazar. '
            'Tiene que tener cuenta creada.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email'),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_email.text.trim()),
          child: const Text('Invitar'),
        ),
      ],
    );
  }
}

/// What one expense did to the ledger: who owes what because of it.
///
/// This is the "historial de deudas por gasto". The list row can only show a
/// total and a strategy label; the debt an expense CREATED lives in its
/// shares, and until now there was nowhere in the app to read them. Tapping a
/// row used to jump straight into the editor, which meant the only way to see
/// who owed what was to open the form that could change it.
///
/// Both amounts are shown for every person. The one in the expense's own
/// currency is what they agreed to and can check against the receipt; the one
/// in USDT is what the ledger actually charged them, and it is the number the
/// balances are built from.
Future<void> _showExpenseDetail(
  BuildContext context, {
  required Expense expense,
  required GroupDetail? detail,
  required void Function(Expense expense) onEdit,
}) {
  final theme = Theme.of(context);
  final converted = !expense.isAlreadySettlementCurrency;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(expense.description, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Pagó ${detail?.nameOf(expense.paidBy) ?? '...'} · '
              '${_formatDate(expense.spentAt)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  expense.total.format(currencyCode: expense.currencyCode),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (converted) ...[
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '= ${expense.totalInUsdt.format()}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                ],
              ],
            ),
            // The rate is shown because it is FROZEN here, not looked up. The
            // amount above will still read the same next month, and this is
            // the line that explains why.
            if (converted) ...[
              const SizedBox(height: 4),
              Text(
                'Al cambio de ese día: 1 $settlementCurrency = '
                '${expense.rate.format()} '
                '${currencies[expense.currencyCode]?.symbol ?? expense.currencyCode}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            const SizedBox(height: 20),
            Text('Le toca a cada uno', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final share in expense.shares)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: PersonAvatar(
                        userId: share.userId,
                        initials: detail?.byId[share.userId]?.initials ?? '?',
                      ),
                      title: Text(detail?.nameOf(share.userId) ?? '...'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            share.amount
                                .format(currencyCode: expense.currencyCode),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          ?(converted
                              ? Text(
                                  share.inUsdt.format(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                )
                              : null),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onEdit(expense);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Every payment already made in this group, newest first.
///
/// The other three tabs are all DERIVED — balances and settlement are
/// recomputed from scratch on every read, and they only ever say where things
/// stand now. This is the other half: the record of what was actually handed
/// over to get there. Without it, a balance that dropped by 50 USDT is a
/// number nobody can account for.
class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.controller,
    required this.detail,
    required this.me,
    required this.groupCreatedBy,
    required this.onDelete,
  });

  final GroupController controller;
  final GroupDetail? detail;
  final String? me;
  final String groupCreatedBy;
  final void Function(Payment payment) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoadStateView<List<Payment>>(
      loader: controller.payments,
      builder: (context, payments) {
        if (payments.isEmpty) {
          return const EmptyView(
            icon: Icons.history,
            title: 'Todavía no se pagó nada',
            subtitle: 'Cuando alguien salde una deuda, va a quedar acá.',
          );
        }

        return RefreshIndicator(
          onRefresh: controller.refreshLedger,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: payments.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final payment = payments[index];
              final converted = payment.currencyCode != settlementCurrency;

              // Somebody can record a payment they did not make — the host
              // can — so it is worth saying who wrote it down when the two
              // are different people.
              final recorder = payment.createdBy == payment.fromUserId
                  ? null
                  : detail?.nameOf(payment.createdBy);

              return ListTile(
                leading: PersonAvatar(
                  userId: payment.fromUserId,
                  initials: detail?.byId[payment.fromUserId]?.initials ?? '?',
                ),
                title: Text(
                  '${detail?.nameOf(payment.fromUserId) ?? '...'}  →  '
                  '${detail?.nameOf(payment.toUserId) ?? '...'}',
                ),
                subtitle: Text(
                  [
                    _formatDate(payment.paidAt),
                    if (converted)
                      'pagado en '
                          '${payment.amount.format(currencyCode: payment.currencyCode)}',
                    if (recorder != null) 'registró $recorder',
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      payment.inUsdt.format(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    // Drawn only for people the server would let through.
                    ?(payment.canBeDeletedBy(me, groupCreatedBy: groupCreatedBy)
                        ? IconButton(
                            tooltip: 'Eliminar el pago',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onDelete(payment),
                          )
                        : null),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// "7 de septiembre", or "7 de septiembre de 2025" when it was another year.
String _formatDate(DateTime when) {
  const months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  final local = when.toLocal();
  final month = months[local.month - 1];
  final sameYear = local.year == DateTime.now().year;

  return sameYear
      ? '${local.day} de $month'
      : '${local.day} de $month de ${local.year}';
}
