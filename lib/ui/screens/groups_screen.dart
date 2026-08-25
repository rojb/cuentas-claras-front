import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../models/group.dart';
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

  @override
  void initState() {
    super.initState();
    // Built in initState, not in build: a Loader created during build would
    // be thrown away and refetched on every rebuild.
    _groups = Loader(() => Dependencies.of(context).groups.myGroups());
    _groups.load();
  }

  @override
  void dispose() {
    _groups.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final created = await showModalBottomSheet<ExpenseGroup>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewGroupSheet(),
    );

    if (created != null) await _groups.load();
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
      body: LoadStateView<List<ExpenseGroup>>(
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
            onRefresh: _groups.load,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final group = groups[index];

                return ListTile(
                  leading: CircleAvatar(
                    child: Text(group.currencyCode.substring(0, 1)),
                  ),
                  title: Text(group.name),
                  subtitle: Text(_subtitleFor(group)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GroupScreen(group: group),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// "3 integrantes · Boliviano", or "1 integrante" when there is only one.
///
/// Spanish agrees in number, so a bare '$count integrantes' reads as broken
/// the moment somebody creates a group and has not added anybody yet.
String _subtitleFor(ExpenseGroup group) {
  final count = group.memberCount ?? 0;
  final people = count == 1 ? '1 integrante' : '$count integrantes';
  final currency = currencies[group.currencyCode]?.name ?? group.currencyCode;

  return '$people · $currency';
}

class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet();

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  String _currency = 'BOB';
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
            currencyCode: _currency,
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
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(labelText: 'Moneda'),
              // Driven by the same map the formatter uses, so a currency can
              // never be selectable and unformattable at the same time.
              items: [
                for (final entry in currencies.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text('${entry.value.name} (${entry.value.symbol})'),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _currency = value ?? _currency),
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
