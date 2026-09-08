import 'money.dart';
import 'split.dart';

/// What one person owes for one expense, already resolved into cents by the
/// server. Never recalculated here: the app displays the ledger, it does not
/// second-guess it.
class ExpenseShare {
  const ExpenseShare({
    required this.userId,
    required this.amount,
    required this.inUsdt,
  });

  final String userId;

  /// What they agreed to, in the currency the expense was paid in. This is
  /// the number that has to look right next to the receipt.
  final Money amount;

  /// What the ledger actually charges them. Balances are built from these,
  /// never from [amount].
  final Money inUsdt;

  factory ExpenseShare.fromJson(Map<String, dynamic> json) => ExpenseShare(
        userId: json['userId'] as String,
        amount: Money(json['shareCents'] as int),
        inUsdt: Money(json['shareUsdtCents'] as int),
      );
}

class Expense {
  const Expense({
    required this.id,
    required this.groupId,
    required this.description,
    required this.total,
    required this.currencyCode,
    required this.rate,
    required this.totalInUsdt,
    required this.paidBy,
    required this.splitStrategy,
    required this.split,
    required this.spentAt,
    required this.shares,
  });

  final String id;
  final String groupId;
  final String description;
  /// In [currencyCode]: what the receipt said.
  final Money total;

  /// What it was paid in. The group has no currency of its own.
  final String currencyCode;

  /// The rate agreed the day it was spent, FROZEN on this expense. It is not
  /// looked up again: that is what keeps a debt of 50 USDT worth 50 USDT
  /// tomorrow instead of drifting overnight.
  final Rate rate;

  /// The same money in the unit the ledger settles in.
  final Money totalInUsdt;

  final String paidBy;

  /// How it was divided, as the server spells it: 'equally', 'exact_amounts',
  /// 'percentages', 'shares', 'mixed', 'items'. Shown as a label, not used to
  /// recompute anything.
  final String splitStrategy;

  /// The split as it was originally asked for, ready to reopen in the editor.
  /// Null when the server sent a shape this version cannot read.
  final Split? split;

  final DateTime spentAt;
  final List<ExpenseShare> shares;

  /// What this person owes for this expense, in the expense's own currency.
  /// Zero if they were not in it.
  Money shareOf(String userId) {
    for (final share in shares) {
      if (share.userId == userId) return share.amount;
    }
    return Money.zero;
  }

  /// The same share in USDT: what it actually moves in the ledger.
  Money usdtShareOf(String userId) {
    for (final share in shares) {
      if (share.userId == userId) return share.inUsdt;
    }
    return Money.zero;
  }

  /// True when the money was already in the unit the ledger settles in, so
  /// there is no conversion worth showing anybody.
  bool get isAlreadySettlementCurrency => currencyCode == settlementCurrency;

  bool involves(String userId) =>
      paidBy == userId || shares.any((share) => share.userId == userId);

  /// The list endpoint wraps each expense as {expense: {...}, shares: [...]}.
  factory Expense.fromJson(Map<String, dynamic> json) {
    final expense = json['expense'] as Map<String, dynamic>;
    final shares = json['shares'] as List<dynamic>? ?? const [];

    return Expense(
      id: expense['id'] as String,
      groupId: expense['groupId'] as String,
      description: expense['description'] as String,
      total: Money(expense['totalCents'] as int),
      currencyCode: expense['currencyCode'] as String,
      rate: Rate(expense['rateMicros'] as int),
      totalInUsdt: Money(expense['totalUsdtCents'] as int),
      paidBy: expense['paidBy'] as String,
      splitStrategy: expense['splitStrategy'] as String,
      split: Split.tryFromJson(expense['splitParams']),
      spentAt: DateTime.parse(expense['spentAt'] as String),
      shares: shares
          .whereType<Map<String, dynamic>>()
          .map(ExpenseShare.fromJson)
          .toList(),
    );
  }
}
