import 'package:flutter/material.dart' hide Split;

import '../../models/allocation.dart';
import '../../models/money.dart';
import '../../models/split.dart';
import '../../models/user.dart';

enum SplitMode { equally, exactAmounts, percentages, shares, mixed, items }

extension on SplitMode {
  String get label => switch (this) {
        SplitMode.equally => 'Iguales',
        SplitMode.exactAmounts => 'Montos',
        SplitMode.percentages => 'Porcentaje',
        SplitMode.shares => 'Partes',
        SplitMode.mixed => 'Mixta',
        SplitMode.items => 'Por ítem',
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
            'con su gente. La propina se puede cobrar en proporción a lo que '
            'consumió cada uno.',
      };
}

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
    this.initial,
  });

  final List<GroupMember> members;
  final String currencyCode;
  final Money total;

  /// The split to reopen when editing an existing expense. Null when adding a
  /// new one, which starts with everybody selected and an equal division.
  final Split? initial;

  @override
  State<SplitEditor> createState() => SplitEditorState();
}

class SplitEditorState extends State<SplitEditor> {
  SplitMode _mode = SplitMode.equally;

  /// Everybody, unless we are reopening a split that excluded somebody.
  ///
  /// Defaulting to all is what makes "por defecto todos, pero se puede
  /// excluir gente" one unchecked box rather than a chore.
  late final Set<String> _selected = {
    for (final member in widget.members) member.userId,
  };

  /// One text field per person. Cleared when the mode changes, because the
  /// same number means something different in each: 50 is fifty pesos under
  /// Amounts, fifty percent under Percent and fifty parts under Shares.
  final Map<String, TextEditingController> _values = {};

  final List<_ItemDraft> _items = [];

  /// Who the user has typed a number for.
  ///
  /// This is the line between "the app decided this" and "the person decided
  /// this". Auto-fill only ever writes into fields nobody has touched, so
  /// recalculating never overwrites something somebody meant.
  final Set<String> _touched = {};

  String? _problem;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _reopen(initial);
      // Reopened numbers came from a person, not from us.
      _touched.addAll(_selected);
    } else {
      _autoFill();
    }
  }

  /// The total lives on the screen above, so a change to it arrives here as a
  /// new widget. Everything not typed by hand gets recomputed against it.
  @override
  void didUpdateWidget(SplitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.total.cents != widget.total.cents) _autoFill();
  }

  /// Fills in the untouched fields so the split adds up on its own.
  ///
  /// Whatever the person typed is taken as given; the remainder is spread
  /// over everybody else. That is what makes editing one number recalculate
  /// the others instead of just complaining that the total is off.
  void _autoFill() {
    final ordered = [
      for (final member in widget.members)
        if (_selected.contains(member.userId)) member.userId,
    ];

    final free = [for (final id in ordered) if (!_touched.contains(id)) id];
    if (free.isEmpty) return;

    switch (_mode) {
      case SplitMode.exactAmounts:
        final taken = ordered
            .where(_touched.contains)
            .fold(0, (sum, id) => sum + (_amountOf(id)?.cents ?? 0));
        final rest = splitEqually(widget.total.cents - taken, free.length);
        // Over-assigned already: leave the fields alone and let the running
        // total say so, rather than writing negative amounts into them.
        if (rest == null) return;
        for (final (index, id) in free.indexed) {
          _controllerFor(id).text = Money(rest[index]).asPlainText;
        }

      case SplitMode.percentages:
        final taken = ordered
            .where(_touched.contains)
            .fold(0, (sum, id) => sum + _basisPointsOf(_controllerFor(id).text));
        final rest =
            splitEqually(PercentagesSplit.fullAmount - taken, free.length);
        if (rest == null) return;
        for (final (index, id) in free.indexed) {
          _controllerFor(id).text = Money(rest[index]).asPlainText;
        }

      case SplitMode.shares:
        // Shares are ratios, so there is no remainder to spread — one each is
        // the split everybody expects to start from.
        for (final id in free) {
          _controllerFor(id).text = '1';
        }

      // Equally has no fields. Mixed's blanks ARE the meaning — filling them
      // in would turn "split me the rest" into a fixed amount. Items are
      // typed line by line and have nothing to guess.
      case SplitMode.equally:
      case SplitMode.mixed:
      case SplitMode.items:
        break;
    }
  }

  Money? _amountOf(String userId) =>
      Money.tryParse(_controllerFor(userId).text);

  /// Loads an existing split back into the controls that produced it.
  ///
  /// Only the split's OWN numbers are restored — never the resolved shares.
  /// Reopening 2:1:1 as "500 / 250 / 250" would look identical and behave
  /// differently the moment somebody changes the total.
  void _reopen(Split split) {
    void select(Iterable<String> ids) {
      _selected
        ..clear()
        ..addAll(ids);
    }

    void fill(Map<String, String> values) {
      values.forEach((userId, text) => _controllerFor(userId).text = text);
    }

    switch (split) {
      case EquallySplit(:final userIds):
        _mode = SplitMode.equally;
        select(userIds);

      case ExactAmountsSplit(:final amounts):
        _mode = SplitMode.exactAmounts;
        select(amounts.keys);
        fill({
          for (final entry in amounts.entries) entry.key: entry.value.asPlainText,
        });

      case PercentagesSplit(:final basisPoints):
        _mode = SplitMode.percentages;
        select(basisPoints.keys);
        // Basis points are hundredths of a percent, which is the same shape
        // as cents — so the same formatter reads them back.
        fill({
          for (final entry in basisPoints.entries)
            entry.key: Money(entry.value).asPlainText,
        });

      case SharesSplit(:final shares):
        _mode = SplitMode.shares;
        select(shares.keys);
        fill({
          for (final entry in shares.entries) entry.key: '${entry.value}',
        });

      case MixedSplit(:final fixedAmounts):
        _mode = SplitMode.mixed;
        select(fixedAmounts.keys);
        fill({
          for (final entry in fixedAmounts.entries)
            if (entry.value != null) entry.key: entry.value!.asPlainText,
        });

      case ItemsSplit(:final items):
        _mode = SplitMode.items;
        for (final item in items) {
          final draft = _ItemDraft(participants: {...item.split.participantIds})
            ..isSurcharge = item.split is ProportionalToConsumptionSplit;
          draft.description.text = item.description;
          draft.amountText.text = item.amount.asPlainText;
          _items.add(draft);
        }

      // Never the split of a whole expense — only ever of an item, which the
      // items branch above already unpacks.
      case ProportionalToConsumptionSplit():
        break;
    }
  }

  @override
  void dispose() {
    for (final controller in _values.values) {
      controller.dispose();
    }
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String userId) =>
      _values.putIfAbsent(userId, TextEditingController.new);

  void _changeMode(SplitMode mode) {
    setState(() {
      _mode = mode;
      _problem = null;
      // The same number means something different in each mode: 50 is fifty
      // pesos under Montos, fifty percent under Porcentaje and fifty parts
      // under Partes. Carrying it over would be carrying over a lie.
      for (final controller in _values.values) {
        controller.clear();
      }
      _touched.clear();
      if (mode == SplitMode.items && _items.isEmpty) {
        _items.add(_ItemDraft(participants: {..._selected}));
      }
      _autoFill();
    });
  }

  // ---------------------------------------------------------------------
  // What the editor knows about whether the numbers work out
  // ---------------------------------------------------------------------

  Money get _assignedAmount => _selected.fold(
        Money.zero,
        (sum, userId) =>
            sum + (Money.tryParse(_controllerFor(userId).text) ?? Money.zero),
      );

  int get _assignedBasisPoints => _selected.fold(
        0,
        (sum, userId) => sum + _basisPointsOf(_controllerFor(userId).text),
      );

  Money get _itemsTotal =>
      _items.fold(Money.zero, (sum, item) => sum + (item.amount ?? Money.zero));

  /// "33,33" -> 3333 basis points. Integers again: 33.33% is not a double we
  /// can add three times and land on exactly 100%.
  static int _basisPointsOf(String input) {
    final asMoney = Money.tryParse(input);
    return asMoney?.cents ?? 0;
  }

  // ---------------------------------------------------------------------
  // Building the payload
  // ---------------------------------------------------------------------

  /// The split as the API wants it, or null with [_problem] set.
  ///
  /// Returning null rather than throwing keeps this a question the form can
  /// ask without a try/catch around a button press.
  Split? buildSplit() {
    final reading = _read();
    setState(() => _problem = reading.problem);
    return reading.split;
  }

  /// Reads the controls WITHOUT touching state.
  ///
  /// Split out from [buildSplit] because the live preview has to run during
  /// build, and calling setState from there is a crash. Same rules, same
  /// messages — one reader, so what the button validates and what the screen
  /// shows can never disagree.
  ({Split? split, String? problem}) _read() {
    ({Split? split, String? problem}) fail(String message) =>
        (split: null, problem: message);
    ({Split? split, String? problem}) ok(Split split) =>
        (split: split, problem: null);

    if (_mode != SplitMode.items && _selected.isEmpty) {
      return fail('Elegí al menos a una persona');
    }

    final ordered = [
      for (final member in widget.members)
        if (_selected.contains(member.userId)) member.userId,
    ];

    switch (_mode) {
      case SplitMode.equally:
        return ok(EquallySplit(ordered));

      case SplitMode.exactAmounts:
        final amounts = <String, Money>{};
        for (final userId in ordered) {
          final amount = Money.tryParse(_controllerFor(userId).text);
          if (amount == null) return fail('Cada persona necesita un monto');
          amounts[userId] = amount;
        }
        if (_assignedAmount.cents != widget.total.cents) {
          return fail(_difference(_assignedAmount, widget.total));
        }
        return ok(ExactAmountsSplit(amounts));

      case SplitMode.percentages:
        final points = <String, int>{};
        for (final userId in ordered) {
          final value = Money.tryParse(_controllerFor(userId).text);
          if (value == null) return fail('Cada persona necesita un porcentaje');
          points[userId] = value.cents;
        }
        final split = PercentagesSplit(points);
        if (!split.addsUpToOneHundred) {
          return fail('Los porcentajes suman '
              '${_asPercent(split.assigned)}, no 100%');
        }
        return ok(split);

      case SplitMode.shares:
        final shares = <String, int>{};
        for (final userId in ordered) {
          final value = int.tryParse(_controllerFor(userId).text.trim());
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
        for (final userId in ordered) {
          final amount = Money.tryParse(_controllerFor(userId).text);
          fixed[userId] = amount;
          if (amount == null) everybodyHasAnAmount = false;
        }
        // With nobody left blank there is no "rest" to split, so the fixed
        // amounts have to cover the total on their own.
        if (everybodyHasAnAmount && _assignedAmount.cents != widget.total.cents) {
          return fail(_difference(_assignedAmount, widget.total));
        }
        if (_assignedAmount > widget.total) {
          return fail('Los montos fijos ya superan el total');
        }
        return ok(MixedSplit(fixed));

      case SplitMode.items:
        if (_items.isEmpty) return fail('Agregá al menos un ítem');

        final built = <ExpenseItem>[];
        for (final item in _items) {
          final problem = item.validate();
          if (problem != null) return fail(problem);
          built.add(item.build());
        }
        if (_itemsTotal.cents != widget.total.cents) {
          return fail(_difference(_itemsTotal, widget.total));
        }
        return ok(ItemsSplit(built));
    }
  }

  String _difference(Money assigned, Money total) {
    final gap = total.cents - assigned.cents;
    final amount = Money(gap.abs()).format(currencyCode: widget.currencyCode);

    return gap > 0 ? 'Falta asignar $amount' : 'Te pasaste por $amount';
  }

  static String _asPercent(int basisPoints) =>
      '${(basisPoints / 100).toStringAsFixed(2)}%';

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
        Wrap(
          spacing: 8,
          children: [
            for (final mode in SplitMode.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: _mode == mode,
                onSelected: (_) => _changeMode(mode),
              ),
          ],
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
          _buildPeopleEditor(theme),
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

  Widget _buildPeopleEditor(ThemeData theme) {
    final preview = _preview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final member in widget.members)
          _PersonRow(
            member: member,
            selected: _selected.contains(member.userId),
            amount: preview?[member.userId],
            currencyCode: widget.currencyCode,
            onSelected: (selected) => setState(() {
              if (selected) {
                _selected.add(member.userId);
              } else {
                _selected.remove(member.userId);
                // Dropping somebody also drops what they had typed, so the
                // rest can take their share back.
                _touched.remove(member.userId);
                _controllerFor(member.userId).clear();
              }
              _problem = null;
              _autoFill();
            }),
            field: _mode == SplitMode.equally
                ? null
                : _ValueField(
                    controller: _controllerFor(member.userId),
                    mode: _mode,
                    currencyCode: widget.currencyCode,
                    onChanged: () => setState(() {
                      _problem = null;
                      // Typed by a person from now on: auto-fill will leave
                      // this field alone and rebalance the others around it.
                      // Emptying it is not a decision, so it hands the field
                      // back and the share gets computed again.
                      if (_controllerFor(member.userId).text.trim().isEmpty) {
                        _touched.remove(member.userId);
                      } else {
                        _touched.add(member.userId);
                      }
                      _autoFill();
                    }),
                  ),
          ),
        if (_mode != SplitMode.equally && _mode != SplitMode.shares) ...[
          const SizedBox(height: 8),
          _RunningTotal(
            label: _mode == SplitMode.percentages
                ? 'Asignado ${_asPercent(_assignedBasisPoints)} de 100%'
                : 'Asignado '
                    '${_assignedAmount.format(currencyCode: widget.currencyCode)}'
                    ' de '
                    '${widget.total.format(currencyCode: widget.currencyCode)}',
            settled: _mode == SplitMode.percentages
                ? _assignedBasisPoints == PercentagesSplit.fullAmount
                : _assignedAmount.cents == widget.total.cents,
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
            index: index,
            members: widget.members,
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
            _items.add(_ItemDraft(participants: {..._selected}));
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

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.member,
    required this.selected,
    required this.currencyCode,
    required this.onSelected,
    this.amount,
    this.field,
  });

  final GroupMember member;
  final bool selected;
  final String currencyCode;

  /// What this person ends up owing. Null while the split does not add up.
  final Money? amount;

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
                ? Text(
                    owed.format(currencyCode: currencyCode),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
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
class _ItemDraft {
  _ItemDraft({required this.participants});

  final description = TextEditingController();
  final amountText = TextEditingController();
  final Set<String> participants;

  /// A tip, service charge or delivery fee: charged in proportion to what
  /// each person consumed, which only makes sense once the other lines are
  /// worked out. The server does that in a second pass.
  bool isSurcharge = false;

  Money? get amount => Money.tryParse(amountText.text);

  String? validate() {
    if (description.text.trim().isEmpty) return 'Cada ítem necesita un nombre';
    final value = amount;
    if (value == null || value.cents <= 0) {
      return 'Cada ítem necesita un monto mayor a cero';
    }
    if (participants.isEmpty) {
      return 'A "${description.text.trim()}" no le asignaste a nadie';
    }
    return null;
  }

  ExpenseItem build() {
    final people = participants.toList();

    return ExpenseItem(
      description: description.text.trim(),
      amount: amount!,
      split: isSurcharge
          ? ProportionalToConsumptionSplit(people)
          : EquallySplit(people),
    );
  }

  void dispose() {
    description.dispose();
    amountText.dispose();
  }
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.draft,
    required this.index,
    required this.members,
    required this.currencyCode,
    required this.onChanged,
    this.onRemove,
  });

  final _ItemDraft draft;
  final int index;
  final List<GroupMember> members;
  final String currencyCode;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.description,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Pizza',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: draft.amountText,
                    textAlign: TextAlign.end,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: '${widget.currencyCode} ',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 6,
              children: [
                for (final member in widget.members)
                  FilterChip(
                    label: Text(member.displayName),
                    selected: draft.participants.contains(member.userId),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        draft.participants.add(member.userId);
                      } else {
                        draft.participants.remove(member.userId);
                      }
                      widget.onChanged();
                    }),
                  ),
              ],
            ),
            SwitchListTile(
              value: draft.isSurcharge,
              onChanged: (value) => setState(() {
                draft.isSurcharge = value;
                widget.onChanged();
              }),
              title: const Text('Propina o cargo por servicio'),
              subtitle: const Text('Se reparte en proporción a lo que '
                  'consumió cada uno'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}
