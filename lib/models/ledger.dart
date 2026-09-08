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
    required this.currencyCode,
    required this.rate,
    required this.inUsdt,
    required this.paidAt,
    required this.createdBy,
    this.voidedAt,
    this.voidedBy,
  });

  final String id;
  final String groupId;
  final String fromUserId;
  final String toUserId;

  /// What actually changed hands, in [currencyCode]. A debt is in USDT but
  /// settling it is not obliged to be: handing somebody Bs 348 to cover
  /// 50 USDT is a normal thing to do.
  final Money amount;
  final String currencyCode;
  final Rate rate;

  /// What it moved in the ledger.
  final Money inUsdt;

  final DateTime paidAt;

  /// Who wrote this down, which is not always who paid: the group's creator
  /// can record somebody else's payment. It is also half of who is allowed to
  /// delete it again.
  final String createdBy;

  /// When it was undone, or null while it still counts.
  ///
  /// A voided payment stays OUT of the balances and IN the history, struck
  /// through. Money moving and then un-moving is a thing that happened, and a
  /// record it can vanish from is not a record.
  final DateTime? voidedAt;

  /// Who undid it. Null for payments voided before the server recorded that,
  /// which the screen shows as "anulado" with no name rather than guessing.
  final String? voidedBy;

  bool get isVoided => voidedAt != null;

  /// Whether [userId] may strike this payment through.
  ///
  /// Both ends of the payment, whoever recorded it, and whoever created the
  /// group — and nobody at all once it is already void. Mirrors the rule the
  /// server enforces in deletePayment; the UI hides the button, the server is
  /// what actually refuses.
  bool canBeDeletedBy(String? userId, {required String groupCreatedBy}) =>
      !isVoided &&
      userId != null &&
      (userId == createdBy ||
          userId == fromUserId ||
          userId == toUserId ||
          userId == groupCreatedBy);

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        fromUserId: json['fromUser'] as String,
        toUserId: json['toUser'] as String,
        amount: Money(json['amountCents'] as int),
        currencyCode: json['currencyCode'] as String,
        rate: Rate(json['rateMicros'] as int),
        inUsdt: Money(json['amountUsdtCents'] as int),
        paidAt: DateTime.parse(json['paidAt'] as String),
        createdBy: json['createdBy'] as String,
        voidedAt: json['voidedAt'] is String
            ? DateTime.tryParse(json['voidedAt'] as String)
            : null,
        voidedBy: json['voidedBy'] as String?,
      );
}
