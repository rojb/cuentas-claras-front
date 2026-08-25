import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../models/expense.dart';
import '../../models/group.dart';
import '../../models/ledger.dart';
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

  String get _currency => widget.group.currencyCode;

  /// Opens the expense form, blank to add one or filled in to correct one.
  Future<void> _editExpense([Expense? existing]) async {
    final members = _controller.detail.state.valueOrNull?.members;
    if (members == null || members.isEmpty) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          groupId: widget.group.id,
          currencyCode: _currency,
          members: members,
          editing: existing,
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

  Future<void> _addMember() async {
    // Captured BEFORE the await: after it, this State may no longer be in the
    // tree and its context would be dead.
    final groups = Dependencies.of(context).groups;

    final email = await showDialog<String>(
      context: context,
      builder: (_) => const _AddMemberDialog(),
    );

    if (email == null) return;

    try {
      await groups.addMember(groupId: widget.group.id, email: email);
      await _controller.refreshMembers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Se sumó al grupo')),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
    }
  }

  Future<void> _recordPayment({Transfer? suggestion}) async {
    final detail = _controller.detail.state.valueOrNull;
    if (detail == null) return;

    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordPaymentSheet(
        groupId: widget.group.id,
        currencyCode: _currency,
        members: detail.members,
        suggestion: suggestion,
      ),
    );

    if (recorded ?? false) await _controller.refreshLedger();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.group.name),
          actions: [
            IconButton(
              tooltip: 'Agregar a alguien',
              icon: const Icon(Icons.person_add_alt),
              onPressed: _addMember,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Gastos'),
              Tab(text: 'Saldos'),
              Tab(text: 'Liquidar'),
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
                  currencyCode: _currency,
                  onEdit: _editExpense,
                  onDelete: _deleteExpense,
                ),
                _BalancesTab(
                  controller: _controller,
                  detail: detail,
                  currencyCode: _currency,
                ),
                _SettleTab(
                  controller: _controller,
                  detail: detail,
                  currencyCode: _currency,
                  onPay: (transfer) => _recordPayment(suggestion: transfer),
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
    required this.currencyCode,
    required this.onEdit,
    required this.onDelete,
  });

  final GroupController controller;
  final GroupDetail? detail;
  final String currencyCode;
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
                  trailing: Text(
                    expense.total.format(currencyCode: currencyCode),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => onEdit(expense),
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
    required this.currencyCode,
  });

  final GroupController controller;
  final GroupDetail? detail;
  final String currencyCode;

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
                  balance.amount.absolute.format(currencyCode: currencyCode),
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
    required this.currencyCode,
    required this.onPay,
  });

  final GroupController controller;
  final GroupDetail? detail;
  final String currencyCode;
  final void Function(Transfer transfer) onPay;

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
                      transfer.amount.format(currencyCode: currencyCode),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => onPay(transfer),
                      child: const Text('Registrar'),
                    ),
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

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog();

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar a alguien'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tiene que tener cuenta creada.'),
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
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
