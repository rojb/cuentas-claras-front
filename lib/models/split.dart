import 'money.dart';

/// How an expense gets divided.
///
/// A sealed class, so `switch` over one of these has to handle every case and
/// the compiler says so. Add a seventh way to split next term and every place
/// that reacts to a split lights up red until it is handled — instead of
/// silently falling through a `default` and charging somebody nothing.
///
/// Each case mirrors exactly one shape the backend accepts. Every number
/// travels attached to its owner, never as a parallel list: the server does
/// the same, precisely so nobody has to keep two arrays aligned.
sealed class Split {
  const Split();

  String get kind;

  Map<String, dynamic> toJson();

  /// Everybody named in this split, in order, without repeats.
  List<String> get participantIds;

  /// Reads back what was sent, so an expense can be reopened for editing.
  ///
  /// The server stores the split verbatim — what was asked for, not what it
  /// resolved to — precisely so this is possible. Rebuilding a split from the
  /// resolved shares would be lossy: 2:1:1 shares and the amounts they
  /// produced look identical afterwards, and reopening the second as the
  /// first would silently change what happens when the total is edited.
  ///
  /// Returns null for anything it does not recognise. An expense saved by a
  /// newer version of the app should open with an empty editor, not crash the
  /// screen.
  static Split? tryFromJson(Object? source) {
    if (source is! Map<String, dynamic>) return null;

    final people = source['participants'];
    final entries = people is List ? people : const [];

    List<String> plainIds() => [
          for (final entry in entries)
            if (entry is String) entry,
        ];

    Map<String, T> keyed<T>(T? Function(Map<String, dynamic>) read) {
      final result = <String, T>{};
      for (final entry in entries) {
        if (entry is! Map<String, dynamic>) continue;
        final userId = entry['userId'];
        if (userId is! String) continue;
        final value = read(entry);
        if (value is T) result[userId] = value;
      }
      return result;
    }

    switch (source['kind']) {
      case 'equally':
        return EquallySplit(plainIds());

      case 'proportionalToConsumption':
        return ProportionalToConsumptionSplit(plainIds());

      case 'exactAmounts':
        return ExactAmountsSplit(
          keyed<Money>((entry) {
            final cents = entry['amountCents'];
            return cents is int ? Money(cents) : null;
          }),
        );

      case 'percentages':
        return PercentagesSplit(
          keyed<int>((entry) {
            final points = entry['percentageBasisPoints'];
            return points is int ? points : null;
          }),
        );

      case 'shares':
        return SharesSplit(
          keyed<int>((entry) {
            final shares = entry['shares'];
            return shares is int ? shares : null;
          }),
        );

      case 'mixed':
        // Every participant belongs in the map; a missing amountCents is the
        // meaning, so it maps to null rather than dropping the person.
        final fixed = <String, Money?>{};
        for (final entry in entries) {
          if (entry is! Map<String, dynamic>) continue;
          final userId = entry['userId'];
          if (userId is! String) continue;
          final cents = entry['amountCents'];
          fixed[userId] = cents is int ? Money(cents) : null;
        }
        return MixedSplit(fixed);

      case 'items':
        final raw = source['items'];
        if (raw is! List) return null;

        final items = <ExpenseItem>[];
        for (final entry in raw) {
          if (entry is! Map<String, dynamic>) continue;
          final split = Split.tryFromJson(entry['split']);
          final cents = entry['amountCents'];
          if (split == null || cents is! int) continue;
          items.add(ExpenseItem(
            description: entry['description'] as String? ?? '',
            amount: Money(cents),
            split: split,
          ));
        }
        return items.isEmpty ? null : ItemsSplit(items);

      default:
        return null;
    }
  }
}

/// Same amount for everybody. Leftover cents go to the first participants.
class EquallySplit extends Split {
  const EquallySplit(this.userIds);

  final List<String> userIds;

  @override
  String get kind => 'equally';

  @override
  List<String> get participantIds => userIds;

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'participants': userIds};
}

/// Each person owes a number you typed. They have to add up to the total.
class ExactAmountsSplit extends Split {
  const ExactAmountsSplit(this.amounts);

  final Map<String, Money> amounts;

  @override
  String get kind => 'exactAmounts';

  @override
  List<String> get participantIds => amounts.keys.toList();

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'participants': [
          for (final entry in amounts.entries)
            {'userId': entry.key, 'amountCents': entry.value.cents},
        ],
      };
}

/// Percentages, in basis points: 3333 is 33.33%.
///
/// Integers again, for the same reason as cents. 33.33% is not representable
/// as a double, and three of them have to add up to exactly 100% — which they
/// will, as whole basis points, and will not, as doubles.
class PercentagesSplit extends Split {
  const PercentagesSplit(this.basisPoints);

  static const int fullAmount = 10000;

  final Map<String, int> basisPoints;

  int get assigned =>
      basisPoints.values.fold(0, (total, points) => total + points);

  bool get addsUpToOneHundred => assigned == fullAmount;

  @override
  String get kind => 'percentages';

  @override
  List<String> get participantIds => basisPoints.keys.toList();

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'participants': [
          for (final entry in basisPoints.entries)
            {'userId': entry.key, 'percentageBasisPoints': entry.value},
        ],
      };
}

/// Relative weights: 2 / 1 / 1 means the first person pays half.
///
/// Unlike percentages, these do not have to add up to anything in particular
/// — 2:1:1 and 4:2:2 are the same split. Only the ratio matters.
class SharesSplit extends Split {
  const SharesSplit(this.shares);

  final Map<String, int> shares;

  @override
  String get kind => 'shares';

  @override
  List<String> get participantIds => shares.keys.toList();

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'participants': [
          for (final entry in shares.entries)
            {'userId': entry.key, 'shares': entry.value},
        ],
      };
}

/// Some people owe a fixed amount; whoever is left splits the rest equally.
///
/// A null amount is what says "and you take a share of the remainder". That
/// is why the map holds `Money?` and not `Money`: the absence IS the meaning.
class MixedSplit extends Split {
  const MixedSplit(this.fixedAmounts);

  final Map<String, Money?> fixedAmounts;

  @override
  String get kind => 'mixed';

  @override
  List<String> get participantIds => fixedAmounts.keys.toList();

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'participants': [
          for (final entry in fixedAmounts.entries)
            {
              'userId': entry.key,
              if (entry.value != null) 'amountCents': entry.value!.cents,
            },
        ],
      };
}

/// An itemised bill: burger for Juan, pizza for Juan and Ana, tip for all.
class ItemsSplit extends Split {
  const ItemsSplit(this.items);

  final List<ExpenseItem> items;

  Money get total =>
      items.fold(Money.zero, (sum, item) => sum + item.amount);

  @override
  String get kind => 'items';

  @override
  List<String> get participantIds =>
      {for (final item in items) ...item.split.participantIds}.toList();

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'items': [for (final item in items) item.toJson()],
      };
}

/// One line of a bill. An item is really a small expense of its own, which is
/// why it carries a Split like any other.
class ExpenseItem {
  const ExpenseItem({
    required this.description,
    required this.amount,
    required this.split,
  });

  final String description;
  final Money amount;
  final Split split;

  Map<String, dynamic> toJson() => {
        'description': description,
        'amountCents': amount.cents,
        'split': split.toJson(),
      };
}

/// A surcharge nobody ordered — tip, service, delivery — charged in
/// proportion to what each person actually consumed.
///
/// Only ever valid inside an item, never as the split of a whole expense:
/// there would be nothing to be proportional to.
class ProportionalToConsumptionSplit extends Split {
  const ProportionalToConsumptionSplit(this.userIds);

  final List<String> userIds;

  @override
  String get kind => 'proportionalToConsumption';

  @override
  List<String> get participantIds => userIds;

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'participants': userIds};
}
