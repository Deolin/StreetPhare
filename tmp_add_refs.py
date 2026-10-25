path = 'E:/projets/StreetPhare/lib/features/admin/presentation/admin_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.read().splitlines()

# Find the end of ValueListenableBuilder (line 151) and insert card methods before line 152
insert_idx = None
for i, l in enumerate(lines):
    if 'SandboxController.instance.simulateUsers(count: 5),' in l:
        insert_idx = i + 1
        break

print('Insert at line:', insert_idx + 1)

# Card methods to add
cards = '''
                const SizedBox(height: 16),
                _buildEventsectionCard(),
                const SizedBox(height: 12),
                _buildModeratorsSectionCard(),
                const SizedBox(height: 12),
                _buildSandboxSectionCard(),
'''

lines.insert(insert_idx, cards)

with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')

print('Done. New line count:', len(lines))
