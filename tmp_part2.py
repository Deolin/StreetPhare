path = 'E:/projets/StreetPhare/lib/features/admin/presentation/admin_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.read().splitlines()

target = next(i for i, l in enumerate(lines) if 'IconData _statusIcon' in l)

m3 = '''  Widget _buildSandboxSectionCard() {
    return Card(color: StreetPhareTheme.darkSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [Icon(Icons.security, color: Colors.deepOrangeAccent), SizedBox(width: 8), Text('Contrôles Sandbox', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: StreetPhareTheme.darkTextPrimary))]),
      const SizedBox(height: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SandboxButton(label: 'Connexion au sandbox', icon: Icons.link, color: Colors.blueAccent, onTap: _toggleSandboxConnection),
        const SizedBox(height: 8),
        _SandboxButton(label: 'Lancer une simulation', icon: Icons.play_circle_fill, color: Colors.greenAccent, onTap: _runSandboxSimulation),
        const SizedBox(height: 8),
        _SandboxButton(label: 'Recharger le sandbox', icon: Icons.refresh, color: Colors.amberAccent, onTap: _reloadSandbox),
      ]),
    ]))),
  }
'''

# Find the updated target (after part 1 insertion)
target2 = next(i for i, l in enumerate(lines) if 'IconData _statusIcon' in l)

# Insert m3 before target
lines.insert(target2, m3)

with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')

print('Part 2 done. New line count:', len(lines))
