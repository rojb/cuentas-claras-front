import 'money.dart';

/// Where one person stands in a group.
///
/// Positive: the group owes them. Negative: they owe the group. Zero: square.
///
/// This never arrives from a "debts" table, because there is no such table on
/// the server either. It is recomputed from the expenses and the payments on
/// every request, which is exactly why it can never be out of date — and why
/// the app must not cache it and must not do arithmetic on it.
class Balance {
  const Balance({required this.userId, required this.amount});

  final String userId;
  final Money amount;

  bool get isSettled => amount.isZero;

  /// They put in more than their share, so the group owes them.
  bool get isOwed => amount.isPositive;

  /// They owe the group.
  bool get owes => amount.isNegative;

  factory Balance.fromJson(Map<String, dynamic> json) => Balance(
        userId: json['userId'] as String,
        amount: Money(json['balanceCents'] as int),
      );
}

/// One transfer somebody still has to make for the group to be square.
///
/// Nobody cares that "Beto owes the group $15.64" — they need to know who to
/// send money to. The server collapses the tangle of debts into at most N-1
/// transfers for N people.
class Transfer {
  const Transfer({
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
  });

  final String fromUserId;
  final String toUserId;
  final Money amount;

  factory Transfer.fromJson(Map<String, dynamic> json) => Transfer(
        fromUserId: json['fromUser'] as String,
        toUserId: json['toUser'] as String,
        amount: Money(json['amountCents'] as int),
      );
}

/// Money that actually changed hands.
///
/// There is no "partial" flag, and there is no status. Paying half of what
/// you owe is recording a payment for half: the balance recomputes and says
/// what is left. That is the whole feature.
class Payment {
  const Payment({
    required this.id,
    required this.groupId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.paidAt,
  });

  final String id;
  final String groupId;
  final String fromUserId;
  final String toUserId;
  final Money amount;
  final DateTime paidAt;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        fromUserId: json['fromUser'] as String,
        toUserId: json['toUser'] as String,
        amount: Money(json['amountCents'] as int),
        paidAt: DateTime.parse(json['paidAt'] as String),
      );
}
