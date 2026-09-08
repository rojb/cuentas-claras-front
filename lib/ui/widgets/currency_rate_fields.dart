import 'package:flutter/material.dart';

import '../../models/allocation.dart';
import '../../models/money.dart';

/// What an amount was paid in, and what it is worth in the unit the ledger
/// settles in.
///
/// One widget for both the expense form and the payment sheet, because the
/// two fields are really one idea: an amount without its currency is a
/// number, and a currency without its rate is a number the ledger cannot use.
/// Two copies of this would drift, and the day they did, one screen would be
/// quietly recording money at a different rate than the other.
///
/// The rate field DISAPPEARS when the currency is already USDT. There is only
/// one honest answer there — one to one — and a field whose only valid value
/// is already known is not a question, it is a trap: the server rejects a
/// USDT expense quoted at anything but par, and the cleanest way to never see
/// that error is to never let anybody type it.
class CurrencyRateFields extends StatelessWidget {
  const CurrencyRateFields({
    super.key,
    required this.currencyCode,
    required this.rate,
    required this.onCurrencyChanged,
    required this.onRateChanged,
    this.amount,
  });

  final String currencyCode;
  final TextEditingController rate;
  final ValueChanged<String> onCurrencyChanged;

  /// Fired on every keystroke so the caller can redraw the converted amount.
  final VoidCallback onRateChanged;

  /// What is currently typed in the amount field, for the live conversion.
  /// Null while it is empty or half-written, which is most of the time.
  final Money? amount;

  bool get _needsRate => currencyCode != settlementCurrency;

  Rate? get _parsedRate =>
      _needsRate ? Rate.tryParse(rate.text) : Rate.par;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: currencyCode,
                decoration: const InputDecoration(labelText: 'Moneda'),
                // Driven by the same map the formatter uses, so a currency
                // can never be selectable and unformattable at once.
                items: [
                  for (final entry in currencies.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text('${entry.value.name} (${entry.value.symbol})'),
                    ),
                ],
                onChanged: (value) => onCurrencyChanged(value ?? currencyCode),
              ),
            ),
            if (_needsRate) ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: rate,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onRateChanged(),
                  decoration: InputDecoration(
                    labelText: 'Tipo de cambio',
                    hintText: '6,96',
                    prefixText: '1 $settlementCurrency = ',
                    suffixText: currencies[currencyCode]?.symbol ?? currencyCode,
                  ),
                  validator: (_) {
                    if (!_needsRate) return null;
                    if (rate.text.trim().isEmpty) {
                      return 'Poné el tipo de cambio';
                    }
                    return Rate.tryParse(rate.text) == null
                        ? 'No se entiende'
                        : null;
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _conversion(theme),
      ],
    );
  }

  Widget _conversion(ThemeData theme) {
    if (!_needsRate) {
      return Text(
        'Se registra tal cual: el grupo salda en $settlementCurrency.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      );
    }

    final parsed = _parsedRate;
    final money = amount;

    if (parsed == null) {
      return Text(
        'Cuántos ${currencies[currencyCode]?.name.toLowerCase() ?? currencyCode} '
        'vale un $settlementCurrency.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      );
    }

    if (money == null || money.isZero) {
      return Text(
        'Se guarda con este cambio y no se vuelve a tocar.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      );
    }

    final converted = toSettlement(money, parsed);

    if (converted == null) {
      return Text(
        'Es menos de un centavo de $settlementCurrency.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.error),
      );
    }

    return Row(
      children: [
        Icon(Icons.sync_alt, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${money.format(currencyCode: currencyCode)}  =  '
            '${converted.format()}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
