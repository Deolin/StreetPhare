path = 'E:/projets/StreetPhare/lib/features/admin/presentation/admin_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.read().splitlines()

# Find start and end of malformed card methods
blocks = {
    '_buildEventsectionCard': None,
    '_buildModeratorsSectionCard': None,
    '_buildSandboxSectionCard': None,
}

for i, l in enumerate(lines):
    for name in blocks:
        if l.strip().startswith(f'Widget {name}('):
            if blocks[name] is None:
                blocks[name] = i

print('Found start positions:', {k: v for k, v in blocks.items()})

# For each block, find the end (line where '  }' closes the method)
for name, start in blocks.items():
    if start is not None:
        for i in range(start + 1, min(start + 30, len(lines))):
            if lines[i].strip() == '}' and i > start + 1:
                blocks[name] = (start, i + 1)
                break

print('Blocks to remove:', {k: (v[0]+1, v[1]) if v else None for k, v in blocks.items()})

# Remove all blocks
new_lines = []
i = 0
while i < len(lines):
    is_start = False
    for name in blocks:
        if blocks[name] and blocks[name][0] == i:
            i = blocks[name][1]
            is_start = True
            break
    if not is_start:
        new_lines.append(lines[i])
        i += 1

with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(new_lines) + '\n')

print('Removed malformed methods. New line count:', len(new_lines))
