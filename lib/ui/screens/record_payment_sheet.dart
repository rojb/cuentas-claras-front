import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../models/allocation.dart';
import '../../models/ledger.dart';
import '../../models/money.dart';
import '../../models/user.dart';
import '../widgets/currency_rate_fields.dart';
import '../widgets/failure_view.dart';

/// Writing down that money changed hands.
///
/// The amount is pre-filled with what the settlement suggests, and is fully
/// editable. That is the entire "partial payment" feature: somebody hands
/// over less than the suggestion, types what they actually gave, and the
/// balance says what is left. There is no half-paid state to model, because
/// there is no debt record to mark.
///
/// The debt is in USDT; handing it over is not obliged to be. Paying a
/// 50 USDT debt with Bs 348 is an ordinary thing to do, so the currency and
/// the rate are here too — and, like an expense, the rate is frozen on the
/// payment. What was handed over that day does not get re-valued later.
class RecordPaymentSheet extends StatefulWidget {
  const RecordPaymentSheet({
    super.key,
    required this.groupId,
    required this.members,
    this.suggestion,
    this.recentRates = const {},
    this.me,
    this.isHost = false,
  });

  final String groupId;
  final List<GroupMember> members;

  /// The transfer the settlement proposed, in USDT. Null when somebody is
  /// recording a payment nobody suggested.
  final Transfer? suggestion;

  /// The last rate this group used for each currency, offered as a starting
  /// point. Nothing is invented: no history means an empty field.
  final Map<String, Rate> recentRates;

  /// Who is signed in.
  final String? me;

  /// Whether this person created the group.
  ///
  /// The host can write down a payment between any two people. Everybody else
  /// has to be ONE OF THE TWO — either end, since the person receiving the
  /// money is usually the one who knows it arrived. The form says so instead
  /// of letting somebody fill it in and collect a 403; the server checks
  /// again regardless.
  final bool isHost;

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _rate;

  String _currency = settlementCurrency;
  String? _fromUserId;
  String? _toUserId;
  bool _busy = false;

  /// Whether the person has typed in the amount themselves.
  ///
  /// The line between "the app guessed" and "they decided". Switching
  /// currency re-fills the amount only while it is still a guess; once
  /// somebody has typed a number, nothing overwrites it.
  bool _amountIsMine = false;

  @override
  void initState() {
    super.initState();

    final suggestion = widget.suggestion;
    _fromUserId = suggestion?.fromUserId;
    _toUserId = suggestion?.toUserId;

    // Opens in USDT: the suggestion is already in USDT, so the common case
    // needs no rate and no conversion at all.
    _amount = TextEditingController(
      text: suggestion == null ? '' : suggestion.amount.asPlainText,
    );
    _rate = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    super.dispose();
  }

  Money? get _parsedAmount => Money.tryParse(_amount.text);

  Rate? get _parsedRate =>
      _currency == settlementCurrency ? Rate.par : Rate.tryParse(_rate.text);

  /// What this payment will actually move in the ledger.
  Money? get _amountInUsdt {
    final amount = _parsedAmount;
    final rate = _parsedRate;
    if (amount == null || rate == null) return null;
    return toSettlement(amount, rate);
  }

  bool get _isPartial {
    final suggested = widget.suggestion?.amount;
    final moving = _amountInUsdt;
    if (suggested == null || moving == null) return false;
    return moving < suggested && moving.cents > 0;
  }

  /// Re-offers the suggested transfer, priced in the currency now selected.
  ///
  /// Only while the amount is still the app's guess. Somebody who typed
  /// "300" meant 300, and having it jump to 348 because they picked a
  /// currency afterwards would be the app overruling them.
  void _reprice() {
    if (_amountIsMine) return;

    final suggestion = widget.suggestion;
    final rate = _parsedRate;

    if (suggestion == null || rate == null) return;

    _amount.text = _currency == settlementCurrency
        ? suggestion.amount.asPlainText
        : fromSettlement(suggestion.amount, rate).asPlainText;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final rate = _parsedRate;
    if (rate == null) return;

    setState(() => _busy = true);

    try {
      await Dependencies.of(context).ledger.recordPayment(
            groupId: widget.groupId,
            fromUserId: _fromUserId,
            toUserId: _toUserId!,
            amount: _parsedAmount!,
            currencyCode: _currency,
            rate: rate,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Registrar un pago', style: theme.textTheme.titleLarge),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _fromUserId,
                decoration: InputDecoration(
                  labelText: 'Quién pagó',
                  helperText: widget.isHost
                      ? null
                      : 'Tenés que ser una de las dos personas del pago',
                  helperMaxLines: 2,
                ),
                items: [
                  for (final member in widget.members)
                    DropdownMenuItem(
                      value: member.userId,
                      child: Text(member.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _fromUserId = value),
                validator: (value) => value == null ? 'Elegí a alguien' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _toUserId,
                decoration: const InputDecoration(labelText: 'Quién lo recibió'),
                items: [
                  for (final member in widget.members)
                    DropdownMenuItem(
                      value: member.userId,
                      child: Text(member.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _toUserId = value),
                validator: (value) {
                  if (value == null) return 'Elegí a alguien';
                  if (value == _fromUserId) {
                    return 'Un pago va entre dos personas distintas';
                  }
                  // Checked here and not on the payer field because this is
                  // the one where both halves of the pair are known.
                  if (!widget.isHost &&
                      widget.me != _fromUserId &&
                      widget.me != value) {
                    return 'Solo el anfitrión puede registrar un pago entre '
                        'otras dos personas';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) => setState(() {
                  // An emptied field is not a decision, so clearing it hands
                  // the suggestion back.
                  _amountIsMine = value.trim().isNotEmpty;
                }),
                decoration: InputDecoration(
                  labelText: 'Monto',
                  prefixText: '${currencies[_currency]?.symbol ?? _currency} ',
                  helperText: _isPartial
                      ? 'Menos de lo sugerido — está bien, el resto queda '
                          'como saldo'
                      : null,
                  helperMaxLines: 2,
                ),
                validator: (_) {
                  final amount = _parsedAmount;
                  if (amount == null) return 'Escribí un monto';
                  if (amount.cents <= 0) return 'Tiene que ser mayor a cero';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              CurrencyRateFields(
                currencyCode: _currency,
                rate: _rate,
                amount: _parsedAmount,
                onCurrencyChanged: (value) => setState(() {
                  _currency = value;
                  // The rate in the field belonged to the old currency.
                  _rate.text = widget.recentRates[value]?.asPlainText ?? '';
                  _reprice();
                }),
                onRateChanged: () => setState(_reprice),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Registrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
