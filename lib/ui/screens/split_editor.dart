import 'package:flutter/material.dart' hide Split;

import '../../models/allocation.dart';
import '../../models/money.dart';
import '../../models/split.dart';
import '../../models/user.dart';

/// Every way an amount can be divided.
///
/// ONE enum for two places, filtered rather than duplicated. A whole expense
/// can use anything except `proportionalToConsumption` — there would be
/// nothing to be proportional to. A single item can use anything except
/// `items`, because a line of a bill is not itself a bill.
///
/// Two enums would have been the obvious move and the wrong one: the modes
/// mean the same thing in both places, and the day somebody added a seventh
/// they would have added it to one of them.
enum SplitMode {
  equally,
  exactAmounts,
  percentages,
  shares,
  mixed,
  items,
  proportionalToConsumption,
}

extension on SplitMode {
  String get label => switch (this) {
        SplitMode.equally => 'Iguales',
        SplitMode.exactAmounts => 'Montos',
        SplitMode.percentages => 'Porcentaje',
        SplitMode.shares => 'Partes',
        SplitMode.mixed => 'Mixta',
        SplitMode.items => 'Por ítem',
        SplitMode.proportionalToConsumption => 'Propina',
      };

  String get explanation => switch (this) {
        SplitMode.equally => 'Todos pagan lo mismo. Los centavos que sobran '
            'van a los primeros de la lista.',
        SplitMode.exactAmounts =>
          'Escribí cuánto le toca a cada uno. Tiene que sumar el total.',
        SplitMode.percentages =>
          'Escribí la parte de cada uno como porcentaje. Tienen que sumar '
              '100%.',
        SplitMode.shares => 'Pesos relativos: 2 / 1 / 1 significa que el '
            'primero paga la mitad. No tienen que sumar nada en particular.',
        SplitMode.mixed => 'Poné un monto fijo para algunos. Dejá el resto en '
            'blanco y esos se reparten lo que queda, en partes iguales.',
        SplitMode.items => 'Una línea por cada cosa de la cuenta, cada una '
            'con su gente y su propia forma de dividirse.',
        SplitMode.proportionalToConsumption =>
          'Se reparte en proporción a lo que consumió cada uno en las otras '
              'líneas.',
      };

  /// Whether this mode needs a number per person.
  bool get hasFields =>
      this != SplitMode.equally &&
      this != SplitMode.items &&
      this != SplitMode.proportionalToConsumption;

  /// Whether a running total is worth showing. Shares are ratios, so there is
  /// nothing for them to add up to.
  bool get hasRunningTotal => hasFields && this != SplitMode.shares;
}

/// What a whole expense can be.
const _expenseModes = [
  SplitMode.equally,
  SplitMode.exactAmounts,
  SplitMode.percentages,
  SplitMode.shares,
  SplitMode.mixed,
  SplitMode.items,
];

/// What one line of a bill can be. Same list, minus nesting, plus the
/// surcharge that only makes sense next to other lines.
const _itemModes = [
  SplitMode.equally,
  SplitMode.exactAmounts,
  SplitMode.percentages,
  SplitMode.shares,
  SplitMode.mixed,
  SplitMode.proportionalToConsumption,
];

/// "33,33" -> 3333 basis points. Integers again: 33.33% is not a double we
/// can add three times and land on exactly 100%.
int _basisPointsOf(String input) => Money.tryParse(input)?.cents ?? 0;

String _asPercent(int basisPoints) =>
    '${(basisPoints / 100).toStringAsFixed(2)}%';

String _difference(Money assigned, Money total, String currencyCode) {
  final gap = total.cents - assigned.cents;
  final amount = Money(gap.abs()).format(currencyCode: currencyCode);

  return gap > 0 ? 'Falta asignar $amount' : 'Te pasaste por $amount';
}

// -------------------------------------------------------------------------
// One division: who is in, and what each of them was given
// -------------------------------------------------------------------------

/// The people half of a split, and the arithmetic over it.
///
/// A PLAIN OBJECT, NOT A WIDGET, and that is the whole reason this refactor
/// was worth doing. Both the expense form and every single item need the same
/// thing — a set of people, a text field each, auto-fill, and the reading that
/// turns them into a Split — and the parent has to be able to ask for the
/// answer at any moment. A child widget holding that state would mean a
/// GlobalKey per item and a reach into somebody else's State; a plain object
/// the parent owns just answers.
///
/// It does NOT hold the mode. Whoever draws the chips owns that, and passes it
/// in: the top level has an `items` mode this class cannot divide, and an item
/// has a `propina` mode the top level cannot use.
class _Division {
  _Division({required this.members, Iterable<String>? participants})
      : selected = {
          ...?participants,
          if (participants == null)
            for (final member in members) member.userId,
        };

  final List<GroupMember> members;

  /// Everybody, unless we are reopening a split that excluded somebody.
  ///
  /// Defaulting to all is what makes "por defecto todos, pero se puede
  /// excluir gente" one unchecked box rather than a chore.
  final Set<String> selected;

  /// One text field per person. Cleared when the mode changes, because the
  /// same number means something different in each: 50 is fifty pesos under
  /// Montos, fifty percent under Porcentaje and fifty parts under Partes.
  final Map<String, TextEditingController> _values = {};

  /// Who the user has typed a number for.
  ///
  /// This is the line between "the app decided this" and "the person decided
  /// this". Auto-fill only ever writes into fields nobody has touched, so
  /// recalculating never overwrites something somebody meant.
  final Set<String> touched = {};

  TextEditingController controllerFor(String userId) =>
      _values.putIfAbsent(userId, TextEditingController.new);

  List<String> get ordered => [
        for (final member in members)
          if (selected.contains(member.userId)) member.userId,
      ];

  Money get assignedAmount => selected.fold(
        Money.zero,
        (sum, userId) =>
            sum + (Money.tryParse(controllerFor(userId).text) ?? Money.zero),
      );

  int get assignedBasisPoints => selected.fold(
        0,
        (sum, userId) => sum + _basisPointsOf(controllerFor(userId).text),
      );

  void clearValues() {
    for (final controller in _values.values) {
      controller.clear();
    }
    touched.clear();
  }

  /// Dropping somebody also drops what they had typed, so the rest can take
  /// their share back.
  void deselect(String userId) {
    selected.remove(userId);
    touched.remove(userId);
    controllerFor(userId).clear();
  }

  /// Emptying a field is not a decision, so it hands the field back and the
  /// share gets computed again.
  void noteTyping(String userId) {
    if (controllerFor(userId).text.trim().isEmpty) {
      touched.remove(userId);
    } else {
      touched.add(userId);
    }
  }

  /// Fills in the untouched fields so the split adds up on its own.
  ///
  /// Whatever the person typed is taken as given; the remainder is spread
  /// over everybody else. That is what makes editing one number recalculate
  /// the others instead of just complaining that the total is off.
  void autoFill(SplitMode mode, Money total) {
    final free = [for (final id in ordered) if (!touched.contains(id)) id];
    if (free.isEmpty) return;

    switch (mode) {
      case SplitMode.exactAmounts:
        final taken = ordered
            .where(touched.contains)
            .fold(0, (sum, id) => sum + (Money.tryParse(controllerFor(id).text)?.cents ?? 0));
        final rest = splitEqually(total.cents - taken, free.length);
        // Over-assigned already: leave the fields alone and let the running
        // total say so, rather than writing negative amounts into them.
        if (rest == null) return;
        for (final (index, id) in free.indexed) {
          controllerFor(id).text = Money(rest[index]).asPlainText;
        }

      case SplitMode.percentages:
        final taken = ordered
            .where(touched.contains)
            .fold(0, (sum, id) => sum + _basisPointsOf(controllerFor(id).text));
        final rest =
            splitEqually(PercentagesSplit.fullAmount - taken, free.length);
        if (rest == null) return;
        for (final (index, id) in free.indexed) {
          controllerFor(id).text = Money(rest[index]).asPlainText;
        }

      case SplitMode.shares:
        // Shares are ratios, so there is no remainder to spread — one each is
        // the split everybody expects to start from.
        for (final id in free) {
          controllerFor(id).text = '1';
        }

      // Equally and the surcharge have no fields. Mixed's blanks ARE the
      // meaning — filling them in would turn "split me the rest" into a fixed
      // amount. Items are typed line by line and have nothing to guess.
      case SplitMode.equally:
      case SplitMode.mixed:
      case SplitMode.items:
      case SplitMode.proportionalToConsumption:
        break;
    }
  }

  /// Loads an existing split back into the controls that produced it, and
  /// says which mode it was.
  ///
  /// Only the split's OWN numbers are restored — never the resolved shares.
  /// Reopening 2:1:1 as "500 / 250 / 250" would look identical and behave
  /// differently the moment somebody changes the total.
  SplitMode reopen(Split split) {
    void select(Iterable<String> ids) {
      selected
        ..clear()
        ..addAll(ids);
    }

    void fill(Map<String, String> values) {
      values.forEach((userId, text) => controllerFor(userId).text = text);
    }

    switch (split) {
      case EquallySplit(:final userIds):
        select(userIds);
        return SplitMode.equally;

      case ExactAmountsSplit(:final amounts):
        select(amounts.keys);
        fill({
          for (final entry in amounts.entries) entry.key: entry.value.asPlainText,
        });
        return SplitMode.exactAmounts;

      case PercentagesSplit(:final basisPoints):
        select(basisPoints.keys);
        // Basis points are hundredths of a percent, which is the same shape
        // as cents — so the same formatter reads them back.
        fill({
          for (final entry in basisPoints.entries)
            entry.key: Money(entry.value).asPlainText,
        });
        return SplitMode.percentages;

      case SharesSplit(:final shares):
        select(shares.keys);
        fill({for (final entry in shares.entries) entry.key: '${entry.value}'});
        return SplitMode.shares;

      case MixedSplit(:final fixedAmounts):
        select(fixedAmounts.keys);
        fill({
          for (final entry in fixedAmounts.entries)
            if (entry.value != null) entry.key: entry.value!.asPlainText,
        });
        return SplitMode.mixed;

      case ProportionalToConsumptionSplit(:final userIds):
        select(userIds);
        return SplitMode.proportionalToConsumption;

      // A list of divisions is not a division. The caller unpacks it and
      // hands each line to its own _Division.
      case ItemsSplit():
        return SplitMode.items;
    }
  }

  /// Reads the controls WITHOUT touching state.
  ///
  /// Returning a problem rather than throwing keeps this a question a form can
  /// ask on every rebuild. One reader, so what the button validates and what
  /// the screen previews can never disagree.
  ({Split? split, String? problem}) read(
    SplitMode mode,
    Money total,
    String currencyCode,
  ) {
    ({Split? split, String? problem}) fail(String message) =>
        (split: null, problem: message);
    ({Split? split, String? problem}) ok(Split split) =>
        (split: split, problem: null);

    if (selected.isEmpty) return fail('Elegí al menos a una persona');

    final people = ordered;

    switch (mode) {
      case SplitMode.equally:
        return ok(EquallySplit(people));

      case SplitMode.proportionalToConsumption:
        return ok(ProportionalToConsumptionSplit(people));

      case SplitMode.exactAmounts:
        final amounts = <String, Money>{};
        for (final userId in people) {
          final amount = Money.tryParse(controllerFor(userId).text);
          if (amount == null) return fail('Cada persona necesita un monto');
          amounts[userId] = amount;
        }
        if (assignedAmount.cents != total.cents) {
          return fail(_difference(assignedAmount, total, currencyCode));
        }
        return ok(ExactAmountsSplit(amounts));

      case SplitMode.percentages:
        final points = <String, int>{};
        for (final userId in people) {
          final value = Money.tryParse(controllerFor(userId).text);
          if (value == null) return fail('Cada persona necesita un porcentaje');
          points[userId] = value.cents;
        }
        final split = PercentagesSplit(points);
        if (!split.addsUpToOneHundred) {
          return fail(
            'Los porcentajes suman ${_asPercent(split.assigned)}, no 100%',
          );
        }
        return ok(split);

      case SplitMode.shares:
        final shares = <String, int>{};
        for (final userId in people) {
          final value = int.tryParse(controllerFor(userId).text.trim());
          if (value == null || value < 0) {
            return fail('Las partes tienen que ser números enteros');
          }
          shares[userId] = value;
        }
        if (shares.values.every((value) => value == 0)) {
          return fail('Alguien tiene que pagar algo');
        }
        return ok(SharesSplit(shares));

      case SplitMode.mixed:
        final fixed = <String, Money?>{};
        var everybodyHasAnAmount = true;
        for (final userId in people) {
          final amount = Money.tryParse(controllerFor(userId).text);
          fixed[userId] = amount;
          if (amount == null) everybodyHasAnAmount = false;
        }
        // With nobody left blank there is no "rest" to split, so the fixed
        // amounts have to cover the total on their own.
        if (everybodyHasAnAmount && assignedAmount.cents != total.cents) {
          return fail(_difference(assignedAmount, total, currencyCode));
        }
        if (assignedAmount > total) {
          return fail('Los montos fijos ya superan el total');
        }
        return ok(MixedSplit(fixed));

      // Handled by whoever owns the list of items, never here.
      case SplitMode.items:
        return fail('Agregá al menos un ítem');
    }
  }

  void dispose() {
    for (final controller in _values.values) {
      controller.dispose();
    }
  }
}

// -------------------------------------------------------------------------
// The editor
// -------------------------------------------------------------------------

/// Picking how an expense gets divided.
///
/// Two things happen here, and they are worth telling apart.
///
/// The editor FILLS IN the numbers for you: pick a mode and everybody already
/// has a share, worked out by [allocate]. Change one and the people you have
/// not touched absorb the difference, so the split keeps adding up while you
/// type instead of only when you press save.
///
/// What it shows is a PREVIEW. The server divides the money again when the
/// expense is saved, and its answer is the one that becomes the ledger.
/// [allocate] is a line-by-line port of the server's domain, verified against
/// it, precisely so the preview and the ledger cannot disagree — but if they
/// ever did, the server would be right.
class SplitEditor extends StatefulWidget {
  const SplitEditor({
    super.key,
    required this.members,
    required this.currencyCode,
    required this.total,
    this.rate,
    this.initial,
  });

  final List<GroupMember> members;

  /// The currency the expense was paid in. EVERY number this editor shows
  /// and every number it collects is in it: the split is what the people
  /// agreed to, and they agreed to it in the money they were holding.
  final String currencyCode;

  final Money total;

  /// What turns those amounts into the unit the ledger settles in. Null while
  /// the rate field is empty or half-typed, which just means the second line
  /// under each name is not ready yet.
  final Rate? rate;

  /// The split to reopen when editing an existing expense. Null when adding a
  /// new one, which starts with everybody selected and an equal division.
  final Split? initial;

  @override
  State<SplitEditor> createState() => SplitEditorState();
}

class SplitEditorState extends State<SplitEditor> {
  SplitMode _mode = SplitMode.equally;

  late final _Division _division = _Division(members: widget.members);

  final List<_ItemDraft> _items = [];

  String? _problem;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;

    if (initial case ItemsSplit(:final items)) {
      _mode = SplitMode.items;
      for (final item in items) {
        final draft = _ItemDraft(members: widget.members, participants: const []);
        draft.description.text = item.description;
        draft.amountText.text = item.amount.asPlainText;
        draft.mode = draft.division.reopen(item.split);
        // Reopened numbers came from a person, not from us.
        draft.division.touched.addAll(draft.division.selected);
        _items.add(draft);
      }
    } else if (initial != null) {
      _mode = _division.reopen(initial);
      _division.touched.addAll(_division.selected);
    } else {
      _division.autoFill(_mode, widget.total);
    }
  }

  /// The total lives on the screen above, so a change to it arrives here as a
  /// new widget. Everything not typed by hand gets recomputed against it.
  @override
  void didUpdateWidget(SplitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.total.cents != widget.total.cents) {
      _division.autoFill(_mode, widget.total);
    }
  }

  @override
  void dispose() {
    _division.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _changeMode(SplitMode mode) {
    setState(() {
      _mode = mode;
      _problem = null;
      // The same number means something different in each mode, so carrying it
      // over would be carrying over a lie.
      _division.clearValues();
      if (mode == SplitMode.items && _items.isEmpty) {
        _items.add(_ItemDraft(
          members: widget.members,
          participants: _division.selected,
        ));
      }
      _division.autoFill(mode, widget.total);
    });
  }

  Money get _itemsTotal =>
      _items.fold(Money.zero, (sum, item) => sum + (item.amount ?? Money.zero));

  // ---------------------------------------------------------------------
  // Building the payload
  // ---------------------------------------------------------------------

  /// The split as the API wants it, or null with [_problem] set.
  Split? buildSplit() {
    final reading = _read();
    setState(() => _problem = reading.problem);
    return reading.split;
  }

  /// Reads the controls WITHOUT touching state.
  ///
  /// Split out from [buildSplit] because the live preview has to run during
  /// build, and calling setState from there is a crash.
  ({Split? split, String? problem}) _read() {
    if (_mode != SplitMode.items) {
      return _division.read(_mode, widget.total, widget.currencyCode);
    }

    if (_items.isEmpty) {
      return (split: null, problem: 'Agregá al menos un ítem');
    }

    final built = <ExpenseItem>[];
    for (final draft in _items) {
      final reading = draft.read(widget.currencyCode);
      if (reading.item == null) return (split: null, problem: reading.problem);
      built.add(reading.item!);
    }

    if (_itemsTotal.cents != widget.total.cents) {
      return (
        split: null,
        problem: _difference(_itemsTotal, widget.total, widget.currencyCode),
      );
    }

    return (split: ItemsSplit(built), problem: null);
  }

  /// What each person owes right now, or null while the numbers do not work
  /// out. Recomputed on every build — it is integer arithmetic over a handful
  /// of people, and a stale preview would be worse than no preview.
  Map<String, Money>? get _preview {
    if (widget.total.isZero) return null;
    final split = _read().split;
    return split == null ? null : allocate(split, widget.total);
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cómo se divide', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _ModeChips(
          modes: _expenseModes,
          selected: _mode,
          onSelected: _changeMode,
        ),
        const SizedBox(height: 8),
        Text(
          _mode.explanation,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 16),
        if (_mode == SplitMode.items)
          _buildItemsEditor(theme)
        else
          _DivisionFields(
            division: _division,
            mode: _mode,
            total: widget.total,
            currencyCode: widget.currencyCode,
            rate: widget.rate,
            onChanged: () => setState(() => _problem = null),
          ),
        if (_problem != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.error_outline,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _problem!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildItemsEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in _items.indexed)
          _ItemCard(
            draft: item,
            currencyCode: widget.currencyCode,
            onChanged: () => setState(() => _problem = null),
            onRemove: _items.length == 1
                ? null
                : () => setState(() {
                      _items.removeAt(index).dispose();
                      _problem = null;
                    }),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _items.add(_ItemDraft(
              members: widget.members,
              participants: _division.selected,
            ));
            _problem = null;
          }),
          icon: const Icon(Icons.add),
          label: const Text('Agregar ítem'),
        ),
        const SizedBox(height: 8),
        _RunningTotal(
          label: 'Los ítems suman '
              '${_itemsTotal.format(currencyCode: widget.currencyCode)} de '
              '${widget.total.format(currencyCode: widget.currencyCode)}',
          settled: _itemsTotal.cents == widget.total.cents,
        ),
        ?_buildItemsBreakdown(theme),
      ],
    );
  }

  /// Who owes what once every line is added up.
  ///
  /// This is where an itemised bill stops being a list and becomes an answer.
  /// A surcharge is charged by consumption, so nobody can work their share
  /// out in their head — which is exactly why it has to be on screen.
  Widget? _buildItemsBreakdown(ThemeData theme) {
    final preview = _preview;
    if (preview == null) return null;

    final byName = [
      for (final member in widget.members)
        if (preview[member.userId] case final owed?)
          (name: member.displayName, owed: owed),
    ];
    if (byName.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Le toca a cada uno', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final person in byName)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(person.name),
                  Text(
                    person.owed.format(currencyCode: widget.currencyCode),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Shared pieces
// -------------------------------------------------------------------------

class _ModeChips extends StatelessWidget {
  const _ModeChips({
    required this.modes,
    required this.selected,
    required this.onSelected,
    this.dense = false,
  });

  final List<SplitMode> modes;
  final SplitMode selected;
  final ValueChanged<SplitMode> onSelected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: dense ? 6 : 8,
      runSpacing: dense ? 0 : 4,
      children: [
        for (final mode in modes)
          ChoiceChip(
            label: Text(mode.label),
            selected: selected == mode,
            onSelected: (_) => onSelected(mode),
            visualDensity: dense ? VisualDensity.compact : null,
            labelStyle: dense ? Theme.of(context).textTheme.bodySmall : null,
          ),
      ],
    );
  }
}

/// The people of a division, their fields, and what each of them ends up
/// owing — used by the expense form AND by every item card.
///
/// Stateless on purpose: all the state lives in the [_Division] its parent
/// owns, so this only draws and reports back.
class _DivisionFields extends StatelessWidget {
  const _DivisionFields({
    required this.division,
    required this.mode,
    required this.total,
    required this.currencyCode,
    required this.onChanged,
    this.rate,
  });

  final _Division division;
  final SplitMode mode;
  final Money total;
  final String currencyCode;
  final VoidCallback onChanged;

  /// Null inside an item: a second currency under every name on every line
  /// turns a bill into a wall of numbers. The breakdown at the bottom already
  /// says what the whole thing comes to.
  final Rate? rate;

  Map<String, Money>? get _preview {
    if (total.isZero) return null;
    final split = division.read(mode, total, currencyCode).split;
    return split == null ? null : allocate(split, total);
  }

  /// The same division, in the unit the ledger settles in.
  ///
  /// Not [_preview] converted person by person. The total is converted once
  /// and the native shares become the weights that divide it, exactly the way
  /// the server does it — converting each row on its own would round each one
  /// on its own and the column would stop adding up to the total.
  Map<String, Money>? get _usdtPreview {
    final withRate = rate;
    if (withRate == null || currencyCode == settlementCurrency) return null;
    if (total.isZero) return null;

    final split = division.read(mode, total, currencyCode).split;
    return split == null
        ? null
        : allocateInSettlement(split, total, withRate);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final inUsdt = _usdtPreview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final member in division.members)
          _PersonRow(
            member: member,
            selected: division.selected.contains(member.userId),
            amount: preview?[member.userId],
            usdtAmount: inUsdt?[member.userId],
            currencyCode: currencyCode,
            onSelected: (selected) {
              if (selected) {
                division.selected.add(member.userId);
              } else {
                division.deselect(member.userId);
              }
              division.autoFill(mode, total);
              onChanged();
            },
            field: !mode.hasFields
                ? null
                : _ValueField(
                    controller: division.controllerFor(member.userId),
                    mode: mode,
                    currencyCode: currencyCode,
                    onChanged: () {
                      // Typed by a person from now on: auto-fill will leave
                      // this field alone and rebalance the others around it.
                      division.noteTyping(member.userId);
                      division.autoFill(mode, total);
                      onChanged();
                    },
                  ),
          ),
        if (mode.hasRunningTotal) ...[
          const SizedBox(height: 8),
          _RunningTotal(
            label: mode == SplitMode.percentages
                ? 'Asignado ${_asPercent(division.assignedBasisPoints)} de 100%'
                : 'Asignado '
                    '${division.assignedAmount.format(currencyCode: currencyCode)}'
                    ' de ${total.format(currencyCode: currencyCode)}',
            settled: mode == SplitMode.percentages
                ? division.assignedBasisPoints == PercentagesSplit.fullAmount
                : division.assignedAmount.cents == total.cents,
          ),
        ],
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.member,
    required this.selected,
    required this.currencyCode,
    required this.onSelected,
    this.amount,
    this.usdtAmount,
    this.field,
  });

  final GroupMember member;
  final bool selected;
  final String currencyCode;

  /// What this person ends up owing, in the expense's own currency. Null
  /// while the split does not add up.
  final Money? amount;

  /// The same amount in the unit the ledger settles in. Null when the expense
  /// is already in it, or while there is no rate to convert with.
  final Money? usdtAmount;

  final ValueChanged<bool> onSelected;
  final Widget? field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = amount;

    return Row(
      children: [
        Expanded(
          child: CheckboxListTile(
            value: selected,
            onChanged: (value) => onSelected(value ?? false),
            title: Text(member.displayName),
            // The whole point of the exercise: what this person actually
            // pays, updated as you type, not after you save.
            subtitle: selected && owed != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        owed.format(currencyCode: currencyCode),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // What the ledger will actually charge them. Second,
                      // and quieter: the first line is the one they can
                      // check against the receipt.
                      ?(usdtAmount == null
                          ? null
                          : Text(
                              usdtAmount!.format(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            )),
                    ],
                  )
                : null,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        if (field != null)
          SizedBox(
            width: 120,
            child: Opacity(opacity: selected ? 1 : 0.4, child: field),
          ),
      ],
    );
  }
}

class _ValueField extends StatelessWidget {
  const _ValueField({
    required this.controller,
    required this.mode,
    required this.currencyCode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final SplitMode mode;
  final String currencyCode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textAlign: TextAlign.end,
      keyboardType: TextInputType.numberWithOptions(
        decimal: mode != SplitMode.shares,
      ),
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        isDense: true,
        prefixText: switch (mode) {
          SplitMode.exactAmounts || SplitMode.mixed => '$currencyCode ',
          _ => null,
        },
        suffixText: switch (mode) {
          SplitMode.percentages => '%',
          SplitMode.shares => 'x',
          _ => null,
        },
        hintText: mode == SplitMode.mixed ? 'resto' : null,
      ),
    );
  }
}

class _RunningTotal extends StatelessWidget {
  const _RunningTotal({required this.label, required this.settled});

  final String label;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour =
        settled ? Colors.green.shade700 : theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Icon(
          settled ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: colour,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: TextStyle(color: colour)),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------------
// Items
// -------------------------------------------------------------------------

/// One line of a bill while it is being typed.
///
/// A draft, not an ExpenseItem: half-typed text is not a valid item, and
/// pretending otherwise means a model full of nullable fields that are only
/// null on one screen.
///
/// It owns a [_Division] of its own, which is what lets a single line be
/// split any way a whole expense can — the pizza by percentage, the wine by
/// shares, the tip by consumption.
class _ItemDraft {
  _ItemDraft({required List<GroupMember> members, Iterable<String>? participants})
      : division = _Division(members: members, participants: participants);

  final description = TextEditingController();
  final amountText = TextEditingController();
  final _Division division;

  SplitMode mode = SplitMode.equally;

  Money? get amount => Money.tryParse(amountText.text);

  void changeMode(SplitMode next) {
    mode = next;
    division.clearValues();
    division.autoFill(next, amount ?? Money.zero);
  }

  /// The line as the API wants it, or the reason it is not ready.
  ///
  /// The item's name goes in front of whatever the division complained about:
  /// with six lines on screen, "Cada persona necesita un porcentaje" is not an
  /// error message, it is a riddle.
  ({ExpenseItem? item, String? problem}) read(String currencyCode) {
    final name = description.text.trim();
    if (name.isEmpty) {
      return (item: null, problem: 'Cada ítem necesita un nombre');
    }

    final value = amount;
    if (value == null || value.cents <= 0) {
      return (item: null, problem: '"$name" necesita un monto mayor a cero');
    }

    final reading = division.read(mode, value, currencyCode);
    if (reading.split == null) {
      return (item: null, problem: '"$name": ${reading.problem}');
    }

    return (
      item: ExpenseItem(description: name, amount: value, split: reading.split!),
      problem: null,
    );
  }

  void dispose() {
    description.dispose();
    amountText.dispose();
    division.dispose();
  }
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.draft,
    required this.currencyCode,
    required this.onChanged,
    this.onRemove,
  });

  final _ItemDraft draft;
  final String currencyCode;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.description,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Qué es',
                      hintText: 'Pizza',
                    ),
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: draft.amountText,
                    textAlign: TextAlign.end,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    // Labelled, hinted and bordered, because it used to be
                    // none of the three: a borderless empty field whose
                    // prefix Flutter only paints once it has focus is a field
                    // nobody can find. People thought the tip switch was the
                    // only thing on the card.
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Cuánto',
                      hintText: '0,00',
                      prefixText: '${widget.currencyCode} ',
                    ),
                    onChanged: (_) => setState(widget.onChanged),
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    tooltip: 'Sacar este ítem',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ModeChips(
              modes: _itemModes,
              selected: draft.mode,
              onSelected: (mode) => setState(() {
                draft.changeMode(mode);
                widget.onChanged();
              }),
              dense: true,
            ),
            const SizedBox(height: 4),
            Text(
              draft.mode.explanation,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const Divider(height: 20),
            _DivisionFields(
              division: draft.division,
              mode: draft.mode,
              total: draft.amount ?? Money.zero,
              currencyCode: widget.currencyCode,
              onChanged: () => setState(widget.onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
