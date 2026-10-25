path = 'E:/projets/StreetPhare/lib/features/admin/presentation/admin_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.read().splitlines()

target = next(i for i, l in enumerate(lines) if 'IconData _statusIcon' in l)

m1 = '''  Widget _buildEventsectionCard() {
    return Card(color: StreetPhareTheme.darkSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [Icon(Icons.event_note, color: Colors.amberAccent), SizedBox(width: 8), Text('Gestion des Èvénements', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: StreetPhareTheme.darkTextPrimary))]),
      const SizedBox(height: 12),
      Form(key: _eventFormKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: TextFormField(controller: _evCodeCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code *', hintText: 'MANIF-2026', isDense: true), validator: (v) => (v == null || v.trim().isEmpty) ? 'Code requis' : null)), const SizedBox(width: 12), Expanded(flex: 2, child: TextFormField(controller: _evTitleCtrl, decoration: const InputDecoration(labelText: 'Titre *', hintText: 'Cortège citoyen', isDense: true), validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre requis' : null))])),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextFormField(controller: _evZoneCtrl, decoration: const InputDecoration(labelText: 'Zone (optionnel)', hintText: 'Fleurus', isDense: true))), const SizedBox(width: 12), ElevatedButton.icon(onPressed: _creatingEvent ? null : _handleCreateEvent, style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black), icon: _creatingEvent ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.add, size: 18), label: Text(_creatingEvent ? 'Création...' : 'Créer l\'événement'))]),
      ])),
      const Divider(height: 20),
      if (!_service.isAuthenticated)
        const Text('Authentifiez-vous pour gérer les événements.', style: TextStyle(color: StreetPhareTheme.darkTextSecondary, fontSize: 12))
      else if (_events.isEmpty)
        const Text('Aucun événement enregistré.', style: TextStyle(color: StreetPhareTheme.darkTextSecondary, fontSize: 12))
      else
        for (final ev in _events)
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.flag_circle, color: Colors.greenAccent), title: Text('${ev.title} (${ev.code})', style: const TextStyle(color: StreetPhareTheme.darkTextPrimary, fontWeight: FontWeight.w600)), subtitle: Text('Début : ${ev.startAt}', style: const TextStyle(color: StreetPhareTheme.darkTextSecondary, fontSize: 11)), trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: _loadingDashboard ? null : () => _handleDeleteEvent(ev.code))),
    ]))),
  }
'''

m2 = '''  Widget _buildModeratorsSectionCard() {
    return Card(color: StreetPhareTheme.darkSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [Icon(Icons.people_outline, color: Colors.lightBlueAccent), SizedBox(width: 8), Text('Gestion des Modérateurs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: StreetPhareTheme.darkTextPrimary))]),
      const SizedBox(height: 12),
      if (!_service.isAuthenticated)
        const Text('Authentifiez-vous pour gérer les modérateurs.', style: TextStyle(color: StreetPhareTheme.darkTextSecondary, fontSize: 12))
      else if (_moderators.isEmpty)
        const Text('Aucun modérateur enregistré.', style: TextStyle(color: StreetPhareTheme.darkTextSecondary, fontSize: 12))
      else
        for (final mod in _moderators)
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person, color: Colors.greenAccent), title: Text(mod.username, style: const TextStyle(color: StreetPhareTheme.darkTextPrimary, fontWeight: FontWeight.w600)), subtitle: Text('Rôles : ${mod.permissions.join(', ')}', style: const TextStyle(color: StreetPhareTheme.darkTextSecondary, fontSize: 11)), trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: _loadingDashboard ? null : () => _handleDeleteModerator(mod))),
    ]))),
  }
'''

# Process: insert m1 and m2 before target
base = '\n'.join(lines[:target])
insert_content = m1 + '\n\n' + m2
lines = lines[:target] + [insert_content] + lines[target:]

with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')

print('Part 1 done. New line count:', len(lines))
