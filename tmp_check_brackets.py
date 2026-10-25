path = 'E:/projets/StreetPhare/lib/features/admin/presentation/admin_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.read().splitlines()

for i in range(167, 215):
    l = lines[i]
    depth = 0
    for c in l:
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
    if depth != 0:
        print(f'Line {i+1}: imbalance={depth}, open={l.count("(")}, close={l.count(")")}')
        print(f'  content: {l.strip()[:80]}')
