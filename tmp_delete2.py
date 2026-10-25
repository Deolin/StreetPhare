import io

path = 'E:/projets/StreetPhare/lib/features/admin/presentation/admin_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.read().splitlines()

# Remove old _buildModeratorsectionCard block (lowercase s) - line 915
start = None
end = None
for i in range(910, 930):
    if 'Widget _buildModeratorsectionCard' in lines[i]:
        start = i
        break

for i in range(start + 1, min(start + 60, len(lines))):
    if lines[i].strip() == '}' and i > start + 1:
        # Check it's the end of the method (not a nested block)
        if 'Widget _buildModeratorsectionCard' not in lines[i]:
            end = i + 1
            break

print('Removing block:', start + 1, 'to', end)
new_lines = lines[:start] + lines[end:]
with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(new_lines) + '\n')
print('New line count:', len(new_lines))
