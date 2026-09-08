import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../models/expense.dart';
import '../../models/money.dart';
import '../../models/user.dart';
import '../widgets/currency_rate_fields.dart';
import '../widgets/failure_view.dart';
import 'split_editor.dart';

/// Adding an expense: what it was, how much, in what money, who paid, and how
/// to divide it.
///
/// The division is the whole point of this app, so it gets its own editor and
/// its own file. This screen owns the easy fields and hands the hard part to
/// [SplitEditor].
///
/// EVERYTHING ON THIS FORM IS IN THE EXPENSE'S OWN CURRENCY — the total and
/// every number inside the split. That is what the people at the table
/// actually agreed to ("Ana pone Bs 40"), and it is what has to add up to
/// what the receipt says. The conversion to USDT happens once, on the server,
/// on the total; this screen only shows what it will come to.
///
/// Editing reuses this same screen rather than getting one of its own. An
/// edit form that drifts from the create form is how you end up able to
/// create a split you cannot correct.
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({
    super.key,
    required this.groupId,
    required this.members,
    this.editing,
    this.recentCurrency,
  });

  final String groupId;
  final List<GroupMember> members;

  /// The expense being corrected, or null when adding a new one.
  final Expense? editing;

  /// What the group has been spending in lately, so the common case is one
  /// tap shorter. The rate is not carried across: [CurrencyRateFields] fetches
  /// a live one from Binance instead of reusing whatever was last typed.
  final String? recentCurrency;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _total;
  late final TextEditingController _rate;

  late String _currency;
  late String _paidBy;
  final _splitKey = GlobalKey<SplitEditorState>();

  bool _busy = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();

    final editing = widget.editing;

    _description = TextEditingController(text: editing?.description ?? '');
    _total = TextEditingController(text: editing?.total.asPlainText ?? '');

    // Reopening an expense shows the rate it was FROZEN at, not today's. The
    // whole point of freezing is that the numbers on an old expense do not
    // move on their own; showing anything else here would quietly re-rate it
    // the next time somebody fixed a typo in the description.
    _currency = editing?.currencyCode ??
        widget.recentCurrency ??
        (currencies.containsKey('BOB') ? 'BOB' : settlementCurrency);

    // New expense: left empty, CurrencyRateFields fills it from Binance.
    // Editing: the rate this expense was frozen at, shown as-is and not
    // re-fetched — the numbers on an old expense must not move on their own.
    _rate = TextEditingController(text: editing?.rate.asPlainText ?? '');

    // An expense whose payer is somehow no longer in the group would leave the
    // dropdown with a value it cannot show, which throws on build.
    final payer = editing?.paidBy;
    _paidBy = widget.members.any((member) => member.userId == payer)
        ? payer!
        : widget.members.first.userId;
  }

  @override
  void dispose() {
    _description.dispose();
    _total.dispose();
    _rate.dispose();
    super.dispose();
  }

  Money? get _parsedTotal => Money.tryParse(_total.text);

  Rate? get _parsedRate =>
      _currency == settlementCurrency ? Rate.par : Rate.tryParse(_rate.text);

  void _changeCurrency(String value) {
    if (value == _currency) return;

    setState(() {
      _currency = value;
      // Whatever rate was in the field belonged to the old currency. Clear
      // it; CurrencyRateFields fetches the new one from Binance.
      _rate.text = '';
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final split = _splitKey.currentState?.buildSplit();
    if (split == null) return;

    final rate = _parsedRate;
    if (rate == null) return;

    setState(() => _busy = true);

    final ledger = Dependencies.of(context).ledger;
    final editing = widget.editing;

    try {
      if (editing == null) {
        await ledger.addExpense(
          groupId: widget.groupId,
          description: _description.text.trim(),
          total: _parsedTotal!,
          currencyCode: _currency,
          rate: rate,
          split: split,
          paidBy: _paidBy,
        );
      } else {
        await ledger.replaceExpense(
          groupId: widget.groupId,
          expenseId: editing.id,
          description: _description.text.trim(),
          total: _parsedTotal!,
          currencyCode: _currency,
          rate: rate,
          split: split,
          paidBy: _paidBy,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      // A 422 here means the numbers do not add up — the server checked the
      // same arithmetic we did and disagreed. Worth showing verbatim: its
      // message says exactly how much is missing.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describeFailure(error)),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar gasto' : 'Nuevo gasto'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextFormField(
              controller: _description,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Qué fue',
                hintText: 'Cena del viernes',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Escribí qué fue'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _total,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Total',
                prefixText:
                    '${currencies[_currency]?.symbol ?? _currency} ',
              ),
              validator: (_) {
                final total = _parsedTotal;
                if (total == null) return 'Escribí el total';
                if (total.cents <= 0) return 'Tiene que ser mayor a cero';
                return null;
              },
            ),
            const SizedBox(height: 16),
            CurrencyRateFields(
              currencyCode: _currency,
              rate: _rate,
              amount: _parsedTotal,
              onCurrencyChanged: _changeCurrency,
              onRateChanged: () => setState(() {}),
              // Editing shows the frozen rate; a new expense looks it up.
              autoFetch: !_isEditing,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _paidBy,
              decoration: const InputDecoration(labelText: 'Quién pagó'),
              items: [
                for (final member in widget.members)
                  DropdownMenuItem(
                    value: member.userId,
                    child: Text(member.displayName),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _paidBy = value ?? _paidBy),
            ),
            const SizedBox(height: 24),
            SplitEditor(
              key: _splitKey,
              members: widget.members,
              currencyCode: _currency,
              total: _parsedTotal ?? Money.zero,
              rate: _parsedRate,
              initial: widget.editing?.split,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? 'Guardar cambios' : 'Guardar gasto'),
          ),
        ),
      ),
    );
  }
}
