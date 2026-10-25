import io

path = 'E:/projets/StreetPhare/lib/features/admin/presentation/admin_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.read().splitlines()

# Remove duplicate _buildSandboxSectionCard block (lines 990-1043, 0-indexed 989-1042)
# Verify start and end
start = None
end = None
for i in range(985, 1000):
    if 'Widget _buildSandboxSectionCard' in lines[i]:
        start = i
        break

for i in range(start + 1, min(start + 60, len(lines))):
    if lines[i].strip() == '}' and i > start + 1:
        end = i + 1
        break

print('Removing block:', start + 1, 'to', end)

new_lines = lines[:start] + lines[end:]
with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(new_lines) + '\n')

print('New line count:', len(new_lines))
