import '../api/api_client.dart';
import '../models/expense.dart';
import '../models/ledger.dart';
import '../models/money.dart';
import '../models/split.dart';

/// Expenses, balances, settlement and payments: everything that touches the
/// ledger of a group.
///
/// One repository instead of three, because these four endpoints are never
/// used apart. Recording a payment changes the balances; adding an expense
/// changes the settlement. Splitting them across files would only spread one
/// idea over three imports.
class LedgerRepository {
  const LedgerRepository(this._api);

  final ApiClient _api;

  Future<List<Expense>> expenses(String groupId) async {
    final response =
        await _api.get('/groups/$groupId/expenses') as Map<String, dynamic>;
    final expenses = response['expenses'] as List<dynamic>;

    return expenses
        .whereType<Map<String, dynamic>>()
        .map(Expense.fromJson)
        .toList();
  }

  /// Records an expense.
  ///
  /// [total] is sent even for an itemised split, where the server could work
  /// it out from the items. It is a checksum: if what the user believes the
  /// bill came to and what the lines add up to disagree, that is a 422 and a
  /// question worth asking, not something to paper over.
  Future<Expense> addExpense({
    required String groupId,
    required String description,
    required Money total,
    required Split split,
    String? paidBy,
    DateTime? spentAt,
  }) async {
    final response = await _api.post(
      '/groups/$groupId/expenses',
      body: _expenseBody(
        description: description,
        total: total,
        split: split,
        paidBy: paidBy,
        spentAt: spentAt,
      ),
    ) as Map<String, dynamic>;

    return Expense.fromJson(response);
  }

  /// Edits an expense: same body as creating one, sent with PUT.
  ///
  /// The whole expense goes, not the changed fields. A split only makes sense
  /// read as one thing — new percentages against the old participant list is
  /// not a smaller edit, it is an expense that does not add up.
  ///
  /// The server answers with a NEW id: editing a ledger entry voids it and
  /// appends the correction. Callers should reload rather than assume the id
  /// they sent still resolves.
  Future<Expense> replaceExpense({
    required String groupId,
    required String expenseId,
    required String description,
    required Money total,
    required Split split,
    String? paidBy,
    DateTime? spentAt,
  }) async {
    final response = await _api.put(
      '/groups/$groupId/expenses/$expenseId',
      body: _expenseBody(
        description: description,
        total: total,
        split: split,
        paidBy: paidBy,
        spentAt: spentAt,
      ),
    ) as Map<String, dynamic>;

    return Expense.fromJson(response);
  }

  static Map<String, dynamic> _expenseBody({
    required String description,
    required Money total,
    required Split split,
    String? paidBy,
    DateTime? spentAt,
  }) =>
      {
        'description': description,
        'totalCents': total.cents,
        'split': split.toJson(),
        'paidBy': ?paidBy,
        if (spentAt != null) 'spentAt': spentAt.toUtc().toIso8601String(),
      };

  /// Voids an expense. The server keeps the row and stops counting it; every
  /// balance recomputes without it on the next read.
  Future<void> deleteExpense({
    required String groupId,
    required String expenseId,
  }) =>
      _api.delete('/groups/$groupId/expenses/$expenseId');

  Future<List<Balance>> balances(String groupId) async {
    final response =
        await _api.get('/groups/$groupId/balances') as Map<String, dynamic>;
    final balances = response['balances'] as List<dynamic>;

    return balances
        .whereType<Map<String, dynamic>>()
        .map(Balance.fromJson)
        .toList();
  }

  Future<List<Transfer>> settlement(String groupId) async {
    final response =
        await _api.get('/groups/$groupId/settlement') as Map<String, dynamic>;
    final transfers = response['transfers'] as List<dynamic>;

    return transfers
        .whereType<Map<String, dynamic>>()
        .map(Transfer.fromJson)
        .toList();
  }

  Future<List<Payment>> payments(String groupId) async {
    final response =
        await _api.get('/groups/$groupId/payments') as Map<String, dynamic>;
    final payments = response['payments'] as List<dynamic>;

    return payments
        .whereType<Map<String, dynamic>>()
        .map(Payment.fromJson)
        .toList();
  }

  /// Records that money changed hands.
  ///
  /// There is no separate call for a partial payment, and no amount to mark
  /// as settled. Paying part of what you owe is recording that part.
  Future<Payment> recordPayment({
    required String groupId,
    required String toUserId,
    required Money amount,
    String? fromUserId,
    DateTime? paidAt,
  }) async {
    final response = await _api.post('/groups/$groupId/payments', body: {
      'toUser': toUserId,
      'amountCents': amount.cents,
      'fromUser': ?fromUserId,
      if (paidAt != null) 'paidAt': paidAt.toUtc().toIso8601String(),
    }) as Map<String, dynamic>;

    return Payment.fromJson(response['payment'] as Map<String, dynamic>);
  }

  Future<void> deletePayment({
    required String groupId,
    required String paymentId,
  }) =>
      _api.delete('/groups/$groupId/payments/$paymentId');
}
