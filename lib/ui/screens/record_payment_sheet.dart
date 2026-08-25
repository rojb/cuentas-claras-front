import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../models/ledger.dart';
import '../../models/money.dart';
import '../../models/user.dart';
import '../widgets/failure_view.dart';

/// Writing down that money changed hands.
///
/// The amount is pre-filled with what the settlement suggests, and is fully
/// editable. That is the entire "partial payment" feature: somebody hands
/// over less than the suggestion, types what they actually gave, and the
/// balance says what is left. There is no half-paid state to model, because
/// there is no debt record to mark.
class RecordPaymentSheet extends StatefulWidget {
  const RecordPaymentSheet({
    super.key,
    required this.groupId,
    required this.currencyCode,
    required this.members,
    this.suggestion,
  });

  final String groupId;
  final String currencyCode;
  final List<GroupMember> members;
  final Transfer? suggestion;

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;

  String? _fromUserId;
  String? _toUserId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    final suggestion = widget.suggestion;
    _fromUserId = suggestion?.fromUserId;
    _toUserId = suggestion?.toUserId;
    _amount = TextEditingController(
      text: suggestion == null ? '' : suggestion.amount.asPlainText,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Money? get _parsedAmount => Money.tryParse(_amount.text);

  bool get _isPartial {
    final suggested = widget.suggestion?.amount;
    final typed = _parsedAmount;
    if (suggested == null || typed == null) return false;
    return typed < suggested && typed.cents > 0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);

    try {
      await Dependencies.of(context).ledger.recordPayment(
            groupId: widget.groupId,
            fromUserId: _fromUserId,
            toUserId: _toUserId!,
            amount: _parsedAmount!,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Registrar un pago', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _fromUserId,
              decoration: const InputDecoration(labelText: 'Quién pagó'),
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
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Monto',
                prefixText: '${widget.currencyCode} ',
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
    );
  }
}
