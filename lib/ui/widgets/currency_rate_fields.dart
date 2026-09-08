import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../models/allocation.dart';
import '../../models/money.dart';
import '../../repositories/rate_repository.dart';

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
/// is already known is not a question, it is a trap.
///
/// For every other currency the rate is fetched from Binance: the person no
/// longer types "el dólar Binance", the app looks it up and shows it, frozen
/// on the expense the moment it is saved exactly as a typed one would be.
/// Only when Binance cannot be reached does the field turn back into a plain
/// input — empty, and then editable — so a bad connection never blocks
/// loading an expense.
class CurrencyRateFields extends StatefulWidget {
  const CurrencyRateFields({
    super.key,
    required this.currencyCode,
    required this.rate,
    required this.onCurrencyChanged,
    required this.onRateChanged,
    this.amount,
    this.autoFetch = true,
    this.rateRepository,
  });

  final String currencyCode;
  final TextEditingController rate;
  final ValueChanged<String> onCurrencyChanged;

  /// Fired whenever the rate changes — a keystroke, or a fetch landing — so
  /// the caller can redraw the converted amount.
  final VoidCallback onRateChanged;

  /// What is currently typed in the amount field, for the live conversion.
  /// Null while it is empty or half-written, which is most of the time.
  final Money? amount;

  /// Whether to look the rate up on Binance.
  ///
  /// False when editing an existing expense: it already carries the rate it
  /// was frozen at, and re-fetching would quietly re-rate a fact. The field
  /// shows that frozen value, and an "editar" affordance for the rare case
  /// where the original was wrong.
  final bool autoFetch;

  /// Where the rate is looked up. Defaults to the app's shared repository;
  /// the screens leave it null and only a scratch harness passes one.
  final RateRepository? rateRepository;

  @override
  State<CurrencyRateFields> createState() => _CurrencyRateFieldsState();
}

/// Where the number in the rate field came from, which decides how the field
/// behaves.
enum _RateSource {
  /// A fetch is in flight.
  loading,

  /// Binance answered. The field is read-only; the value is what will be
  /// frozen on the expense.
  binance,

  /// Binance could not be reached, or the person chose to override. The field
  /// is a plain editable input.
  manual,

  /// Editing an existing expense: the value is the one frozen on it.
  frozen,
}

class _CurrencyRateFieldsState extends State<CurrencyRateFields> {
  _RateSource _source = _RateSource.manual;
  DateTime? _fetchedAt;
  bool _stale = false;

  /// Bumped on every fetch so a slow response for a currency the person has
  /// already switched away from is ignored when it finally lands.
  int _fetchToken = 0;

  bool get _needsRate => widget.currencyCode != settlementCurrency;

  Rate? get _parsedRate =>
      _needsRate ? Rate.tryParse(widget.rate.text) : Rate.par;

  @override
  void initState() {
    super.initState();

    if (!_needsRate) return;

    if (widget.autoFetch) {
      // Plain write, not setState: the first build has not happened yet.
      _source = _RateSource.loading;
      _startFetch();
    } else {
      _source = _RateSource.frozen;
    }
  }

  @override
  void didUpdateWidget(CurrencyRateFields oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The currency changed under us. Whatever was in the field belonged to
    // the old one, so a fresh rate is always right here — even while editing,
    // because changing the currency of an expense is a deliberate act, not a
    // typo fix.
    if (widget.currencyCode != oldWidget.currencyCode) {
      if (_needsRate) {
        _refetch();
      } else {
        _fetchToken++; // ignore any in-flight fetch when it lands
        setState(() {
          _source = _RateSource.manual;
          _fetchedAt = null;
          _stale = false;
        });
      }
    }
  }

  /// Re-check the rate in response to something the user did.
  void _refetch() {
    setState(() {
      _source = _RateSource.loading;
      _fetchedAt = null;
      _stale = false;
    });
    _startFetch();
  }

  Future<void> _startFetch() async {
    final token = ++_fetchToken;
    final currency = widget.currencyCode;

    final rates = widget.rateRepository ?? Dependencies.of(context).rates;
    final result = await rates.currentRate(currency);

    // Disposed, or the person moved on to another currency while we waited.
    if (!mounted || token != _fetchToken) return;

    setState(() {
      if (result != null) {
        widget.rate.text = result.rate.asPlainText;
        _source = _RateSource.binance;
        _fetchedAt = result.fetchedAt;
        _stale = result.stale;
      } else {
        widget.rate.text = '';
        _source = _RateSource.manual;
        _fetchedAt = null;
        _stale = false;
      }
    });

    widget.onRateChanged();
  }

  /// Hands the field back to the person. Keeps whatever value is in it — the
  /// Binance number is a fine starting point for the correction.
  void _unlock() {
    setState(() => _source = _RateSource.manual);
  }

  bool get _readOnly =>
      _source == _RateSource.loading ||
      _source == _RateSource.binance ||
      _source == _RateSource.frozen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: widget.currencyCode,
          decoration: const InputDecoration(labelText: 'Moneda'),
          // Driven by the same map the formatter uses, so a currency can
          // never be selectable and unformattable at once.
          items: [
            for (final entry in currencies.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text('${entry.value.name} (${entry.value.symbol})'),
              ),
          ],
          onChanged: (value) =>
              widget.onCurrencyChanged(value ?? widget.currencyCode),
        ),
        if (_needsRate) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.rate,
            readOnly: _readOnly,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => widget.onRateChanged(),
            decoration: InputDecoration(
              labelText: 'Tipo de cambio',
              hintText: '6,96',
              prefixText: '1 $settlementCurrency = ',
              suffixText: currencies[widget.currencyCode]?.symbol ??
                  widget.currencyCode,
              suffixIcon: _suffixIcon(theme),
            ),
            validator: (_) {
              if (!_needsRate) return null;
              switch (_source) {
                case _RateSource.loading:
                  return 'Esperá la cotización';
                case _RateSource.binance:
                case _RateSource.frozen:
                  return null;
                case _RateSource.manual:
                  if (widget.rate.text.trim().isEmpty) {
                    return 'Poné el tipo de cambio';
                  }
                  return Rate.tryParse(widget.rate.text) == null
                      ? 'No se entiende'
                      : null;
              }
            },
          ),
        ],
        const SizedBox(height: 8),
        _status(theme),
        _conversion(theme),
      ],
    );
  }

  Widget? _suffixIcon(ThemeData theme) {
    switch (_source) {
      case _RateSource.loading:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _RateSource.binance:
      case _RateSource.manual:
        // Refresh in both: from Binance it re-checks, and from a manual
        // field it is the way back to an automatic rate after a failure.
        return IconButton(
          tooltip: 'Buscar la cotización en Binance',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _refetch,
        );
      case _RateSource.frozen:
        return IconButton(
          tooltip: 'Editar el tipo de cambio',
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: _unlock,
        );
    }
  }

  Widget _status(ThemeData theme) {
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.outline);

    final text = switch (_source) {
      _ when !_needsRate => null,
      _RateSource.loading => 'Buscando la cotización en Binance…',
      _RateSource.binance when _stale =>
        'Binance no respondió — última cotización conocida'
            '${_fetchedAt == null ? '' : ' (${_ago(_fetchedAt!)})'}',
      _RateSource.binance =>
        'Cotización de Binance P2P · ${_ago(_fetchedAt!)}',
      _RateSource.frozen => 'Tipo de cambio con el que se cargó el gasto',
      _RateSource.manual => 'No se pudo traer de Binance. Ponelo a mano.',
    };

    if (text == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            _source == _RateSource.manual || _stale
                ? Icons.error_outline
                : Icons.trending_up,
            size: 14,
            color: _source == _RateSource.manual || _stale
                ? theme.colorScheme.error
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: _source == _RateSource.manual || _stale
                  ? style?.copyWith(color: theme.colorScheme.error)
                  : style,
            ),
          ),
        ],
      ),
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
    final money = widget.amount;

    if (parsed == null) {
      if (_source == _RateSource.loading) return const SizedBox.shrink();
      return Text(
        'Cuántos ${currencies[widget.currencyCode]?.name.toLowerCase() ?? widget.currencyCode} '
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
            '${money.format(currencyCode: widget.currencyCode)}  =  '
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

/// "hace un momento", "hace 3 min", "hace 2 h". Rough on purpose: the point
/// is "recent enough to trust", not a stopwatch.
String _ago(DateTime when) {
  final minutes = DateTime.now().difference(when).inMinutes;
  if (minutes < 1) return 'hace un momento';
  if (minutes < 60) return 'hace $minutes min';
  final hours = minutes ~/ 60;
  return 'hace $hours h';
}
