
/// Works out what each person owes, so the app can show it while you type.
///
/// THIS IS A PREVIEW, NOT THE LEDGER. The server runs the same arithmetic and
/// its answer is the one that gets stored; what happens here never leaves the
/// screen. Keeping that straight matters, because the moment a client's
/// numbers are treated as authoritative you have two ledgers.
///
/// So why duplicate it at all? Because "Bs 33,34 / Bs 33,33 / Bs 33,33" is the
/// answer to the question the user is actually asking, and making them save
/// an expense to find out is a worse app. The duplication is deliberate, and
/// it is a real cost: two implementations of one rule can drift.
///
/// What keeps them honest is that this is a LINE-BY-LINE port of
/// `backend/src/domain/` — same algorithm, same tie-breaking, same order.
/// Any change to the split rules has to land in both files or the preview
/// starts lying. It was verified against the live API across every strategy
/// before being trusted.
library;

import 'money.dart';
import 'split.dart';

/// Distributes an amount by whole-number weights, using the LARGEST REMAINDER
/// METHOD. The engine every proportional split shares.
///
/// Each exact share is rounded DOWN, which always leaves a few cents over.
/// Those go to whoever was cut the most by the rounding — the same rule that
/// hands out parliamentary seats from vote counts. Ties go to the earlier
/// participant, so the same input always produces the same output.
///
/// Returns null when the weights do not add up to more than zero: there is no
/// meaningful way to divide by nothing.
List<int>? distributeProportionally(int totalCents, List<int> weights) {
  if (totalCents < 0) return null;

  final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
  if (totalWeight <= 0) return null;

  // Scaled by totalWeight so it stays a whole number: no rounding yet.
  final scaled = [for (final weight in weights) totalCents * weight];
  final roundedDown = [for (final value in scaled) value ~/ totalWeight];

  // Rounding down never loses more than one cent per participant, because
  // each discarded remainder is below a full cent.
  final leftover =
      totalCents - roundedDown.fold<int>(0, (sum, share) => sum + share);

  final byLoss = [
    for (final (index, value) in scaled.indexed)
      (index: index, remainder: value % totalWeight),
  ]..sort((a, b) {
      final byRemainder = b.remainder.compareTo(a.remainder);
      return byRemainder != 0 ? byRemainder : a.index.compareTo(b.index);
    });

  final getsAnExtraCent = {
    for (final entry in byLoss.take(leftover)) entry.index,
  };

  return [
    for (final (index, share) in roundedDown.indexed)
      getsAnExtraCent.contains(index) ? share + 1 : share,
  ];
}

/// Splits an amount equally. Leftover cents go to the first participants, so
/// no two shares differ by more than one cent and the total is exact.
List<int>? splitEqually(int totalCents, int people) {
  if (totalCents < 0 || people <= 0) return null;

  final base = totalCents ~/ people;
  final leftover = totalCents - base * people;

  return [
    for (var index = 0; index < people; index++)
      index < leftover ? base + 1 : base,
  ];
}

/// Splits by relative weights. 2/1/1 and 4/2/2 divide the money identically —
/// only the ratio matters, so these do not have to add up to anything.
List<int>? splitByShares(int totalCents, List<int> shares) {
  if (shares.isEmpty || shares.any((share) => share < 0)) return null;
  return distributeProportionally(totalCents, shares);
}

/// Splits by percentages in basis points. They must add up to exactly 100%.
List<int>? splitByPercentages(int totalCents, List<int> basisPoints) {
  if (basisPoints.isEmpty || basisPoints.any((points) => points < 0)) {
    return null;
  }
  final assigned = basisPoints.fold<int>(0, (sum, points) => sum + points);
  if (assigned != PercentagesSplit.fullAmount) return null;

  return distributeProportionally(totalCents, basisPoints);
}

/// Splits where some people put in a fixed amount and the rest share what is
/// left, equally. A null entry means "and I take a cut of the remainder".
List<int>? splitMixed(int totalCents, List<int?> parts) {
  if (totalCents < 0 || parts.isEmpty) return null;
  if (parts.any((part) => part != null && part < 0)) return null;

  final fixed = parts.fold<int>(0, (sum, part) => sum + (part ?? 0));
  if (fixed > totalCents) return null;

  final remaining = totalCents - fixed;
  final sharingTheRest = parts.where((part) => part == null).length;

  // Nobody left to absorb the difference: the fixed amounts had better be the
  // whole expense, or this simply does not add up.
  if (sharingTheRest == 0) {
    return remaining > 0 ? null : [for (final part in parts) part ?? 0];
  }

  final pending = splitEqually(remaining, sharingTheRest);
  if (pending == null) return null;

  var next = 0;
  return [for (final part in parts) part ?? pending[next++]];
}

/// What one person owes across a whole itemised bill.
///
/// Every item is divided on its own and the shares are added up. Surcharges —
/// a tip, a service charge — are held back for a second pass and then charged
/// in proportion to what each person consumed, because until the other lines
/// are resolved there is no proportion to respect.
Map<String, Money>? splitByItems(List<ExpenseItem> items) {
  if (items.isEmpty) return null;

  final owed = <String, int>{};

  for (final item in items) {
    for (final userId in item.split.participantIds) {
      owed.putIfAbsent(userId, () => 0);
    }
  }

  void add(List<String> people, List<int> shares) {
    for (final (index, userId) in people.indexed) {
      owed[userId] = (owed[userId] ?? 0) + shares[index];
    }
  }

  final surcharges = <ExpenseItem>[];

  for (final item in items) {
    final people = item.split.participantIds;
    if (people.isEmpty) return null;

    if (item.split is ProportionalToConsumptionSplit) {
      surcharges.add(item);
      continue;
    }

    final shares = allocate(item.split, item.amount);
    if (shares == null) return null;
    add(people, [for (final userId in people) shares[userId]!.cents]);
  }

  for (final item in surcharges) {
    final people = item.split.participantIds;
    final consumed = [for (final userId in people) owed[userId] ?? 0];

    // A bill that is only a tip has no consumption to weight by, so the fair
    // fallback is an equal split.
    final shares = consumed.fold<int>(0, (sum, value) => sum + value) > 0
        ? distributeProportionally(item.amount.cents, consumed)
        : splitEqually(item.amount.cents, people.length);

    if (shares == null) return null;
    add(people, shares);
  }

  return {
    for (final entry in owed.entries) entry.key: Money(entry.value),
  };
}

/// What each person owes for [split], or null when the numbers do not work
/// out yet — half-typed input is the normal state of a form, not an error.
///
/// The participant order is the split's own, which is the same order the
/// server divides by. That is what makes the leftover cents land on the same
/// people here as they will in the ledger.
Map<String, Money>? allocate(Split split, Money total) {
  final List<int>? cents;
  final List<String> people;

  switch (split) {
    case EquallySplit(:final userIds):
      people = userIds;
      cents = splitEqually(total.cents, userIds.length);

    case ExactAmountsSplit(:final amounts):
      people = amounts.keys.toList();
      final assigned =
          amounts.values.fold<int>(0, (sum, amount) => sum + amount.cents);
      // Nothing to distribute here — the user already decided. The only
      // question is whether it adds up, and if it does not there is no
      // preview to show.
      cents = assigned == total.cents
          ? [for (final amount in amounts.values) amount.cents]
          : null;

    case PercentagesSplit(:final basisPoints):
      people = basisPoints.keys.toList();
      cents = splitByPercentages(total.cents, basisPoints.values.toList());

    case SharesSplit(:final shares):
      people = shares.keys.toList();
      cents = splitByShares(total.cents, shares.values.toList());

    case MixedSplit(:final fixedAmounts):
      people = fixedAmounts.keys.toList();
      cents = splitMixed(
        total.cents,
        [for (final amount in fixedAmounts.values) amount?.cents],
      );

    case ItemsSplit(:final items):
      return splitByItems(items);

    case ProportionalToConsumptionSplit():
      // Only ever the split of an item, never of a whole expense: there would
      // be nothing to be proportional to.
      return null;
  }

  if (cents == null) return null;

  return {
    for (final (index, userId) in people.indexed) userId: Money(cents[index]),
  };
}
