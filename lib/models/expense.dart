import 'money.dart';
import 'split.dart';

/// What one person owes for one expense, already resolved into cents by the
/// server. Never recalculated here: the app displays the ledger, it does not
/// second-guess it.
class ExpenseShare {
  const ExpenseShare({required this.userId, required this.amount});

  final String userId;
  final Money amount;

  factory ExpenseShare.fromJson(Map<String, dynamic> json) => ExpenseShare(
        userId: json['userId'] as String,
        amount: Money(json['shareCents'] as int),
      );
}

class Expense {
  const Expense({
    required this.id,
    required this.groupId,
    required this.description,
    required this.total,
    required this.paidBy,
    required this.splitStrategy,
    required this.split,
    required this.spentAt,
    required this.shares,
  });

  final String id;
  final String groupId;
  final String description;
  final Money total;
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

  /// What this person owes for this expense. Zero if they were not in it.
  Money shareOf(String userId) {
    for (final share in shares) {
      if (share.userId == userId) return share.amount;
    }
    return Money.zero;
  }

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
