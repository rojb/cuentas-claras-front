import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../models/group.dart';
import '../../models/invitation.dart';
import '../../models/money.dart';
import '../load_state.dart';
import '../widgets/failure_view.dart';
import '../widgets/load_state_view.dart';
import 'group_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final Loader<List<ExpenseGroup>> _groups;
  late final Loader<List<Invitation>> _invitations;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Built in initState, not in build: a Loader created during build would
    // be thrown away and refetched on every rebuild.
    final groups = Dependencies.of(context).groups;

    _groups = Loader(groups.myGroups);
    _invitations = Loader(groups.myInvitations);

    _refresh();

    // An invitation is the one thing here that arrives without being asked
    // for, and it arrives while the app is closed as often as not. Coming
    // back to it is the moment to look.
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _groups.dispose();
    _invitations.dispose();
    super.dispose();
  }

  /// The two go together: answering an invitation moves both lists, and this
  /// is also the only screen where a new invitation can turn up.
  Future<void> _refresh() => Future.wait([_groups.load(), _invitations.load()]);

  /// Says yes or no, and reloads whatever moved.
  ///
  /// Accepting is the interesting one: it does not just remove a card, it
  /// makes a group appear. Reloading both lists in one go is what keeps the
  /// screen from showing the invitation gone and the group not there yet.
  Future<void> _answer(Invitation invitation, {required bool accept}) async {
    final groups = Dependencies.of(context).groups;
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (accept) {
        final group = await groups.acceptInvitation(invitation.id);
        await _refresh();
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Te uniste a ${group.name}')),
        );
      } else {
        await groups.rejectInvitation(invitation.id);
        await _invitations.load();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Invitación rechazada')),
        );
      }
    } on Object catch (error) {
      // The invitation may have been answered somewhere else, so the list is
      // reloaded either way: leaving a card that no longer exists on screen
      // would only let somebody tap it again.
      await _invitations.load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
    }
  }

  Future<void> _createGroup() async {
    final created = await showModalBottomSheet<ExpenseGroup>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewGroupSheet(),
    );

    if (created != null) await _groups.load();
  }

  /// Opens a group and reloads the list if it comes back changed.
  ///
  /// The screen answers true when somebody left the group. Without this the
  /// list would keep drawing a group the user is no longer in until the next
  /// pull to refresh — and tapping it would answer 404, which is correct and
  /// still looks like a bug.
  Future<void> _openGroup(ExpenseGroup group) async {
    final left = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GroupScreen(group: group)),
    );

    if (left ?? false) await _groups.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tus grupos'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => Dependencies.of(context).auth.logOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo grupo'),
      ),
      // The invitations sit ABOVE the list and outside its LoadStateView on
      // purpose: they are the one thing on this screen that is waiting for an
      // answer, and burying them under a groups list that may itself be
      // loading or broken would hide the only actionable thing here.
      body: ListenableBuilder(
        listenable: _invitations,
        builder: (context, child) {
          final invitations =
              _invitations.state.valueOrNull ?? const <Invitation>[];

          if (invitations.isEmpty) return child!;

          return Column(
            children: [
              for (final invitation in invitations)
                _InvitationCard(
                  invitation: invitation,
                  onAccept: () => _answer(invitation, accept: true),
                  onReject: () => _answer(invitation, accept: false),
                ),
              const Divider(height: 1),
              Expanded(child: child!),
            ],
          );
        },
        child: LoadStateView<List<ExpenseGroup>>(
          loader: _groups,
          builder: (context, groups) {
          if (groups.isEmpty) {
            return const EmptyView(
              icon: Icons.groups_outlined,
              title: 'Todavía no hay grupos',
              subtitle: 'Creá uno y sumá a la gente con la que compartís '
                  'gastos.',
            );
          }

            return RefreshIndicator(
              // Pulling refreshes the invitations too. They are the other
              // half of this screen and they arrive without being asked for.
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: groups.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final group = groups[index];

                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(_initialOf(group.name)),
                    ),
                    title: Text(group.name),
                    subtitle: Text(_subtitleFor(group)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openGroup(group),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One invitation, with both answers on it.
///
/// "Aceptar" and "Rechazar" are equally reachable on purpose. A card where
/// saying no means finding a menu is a card that pressures people into saying
/// yes, and joining a group is exactly the decision this feature exists to
/// hand back to them.
class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.onAccept,
    required this.onReject,
  });

  final Invitation invitation;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = invitation.memberCount == 1
        ? '1 integrante'
        : '${invitation.memberCount} integrantes';

    return Container(
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invitation.groupName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    Text(
                      '${invitation.invitedByName} te invitó · $people',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onReject, child: const Text('Rechazar')),
              const SizedBox(width: 8),
              FilledButton(onPressed: onAccept, child: const Text('Aceptar')),
            ],
          ),
        ],
      ),
    );
  }
}

/// "3 integrantes · salda en USDT", or "1 integrante" when there is only one.
///
/// Spanish agrees in number, so a bare '$count integrantes' reads as broken
/// the moment somebody creates a group and has not added anybody yet.
///
/// The currency named here is the one the group SETTLES in, not one it was
/// created with. Its expenses can be in any of the three; this is the unit
/// they all end up in.
String _subtitleFor(ExpenseGroup group) {
  final count = group.memberCount ?? 0;
  final people = count == 1 ? '1 integrante' : '$count integrantes';

  return '$people · salda en $settlementCurrency';
}

/// First letter of the group's name, for the avatar. Falls back to a dot
/// rather than throwing on a name that is somehow empty.
String _initialOf(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '·' : trimmed.substring(0, 1).toUpperCase();
}

class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet();

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);

    try {
      final group = await Dependencies.of(context).groups.create(
            name: _name.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(group);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeFailure(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        // Lifts the sheet above the keyboard instead of hiding the button
        // under it.
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nuevo grupo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Viaje a Copacabana',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Poné un nombre al grupo'
                  : null,
            ),
            const SizedBox(height: 16),
            // No currency picker. A group does not have one: each expense
            // carries the money it was actually paid in, and everything is
            // reconciled in USDT.
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Los gastos pueden ser en bolivianos, dólares o '
                    '$settlementCurrency. Todo se salda en $settlementCurrency.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }
}
