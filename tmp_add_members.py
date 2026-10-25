path = 'E:/projets/StreetPhare/lib/features/admin/presentation/admin_dashboard_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.read().splitlines()

# Find the end of the class (before _SandboxButton class)
class_end = None
for i, l in enumerate(lines):
    if 'class _SandboxButton' in l:
        class_end = i
        break

print('Class ends at:', class_end + 1)

# Members to add (before the _SandboxButton class)
members = '''

  // --- État ---
  final _eventFormKey = GlobalKey<FormState>();
  TextEditingController _evCodeCtrl = TextEditingController();
  TextEditingController _evTitleCtrl = TextEditingController();
  TextEditingController _evZoneCtrl = TextEditingController();
  bool _creatingEvent = false;
  bool _loadingDashboard = false;
  RbacAdminService _service = RbacAdminService();
  List<Event> _events = [];
  List<Moderator> _moderators = [];
  bool _isLoadingSandbox = false;

  // --- Actions ---
  Future<void> _handleCreateEvent() async {
    if (!_eventFormKey.currentState!.validate()) return;
    setState(() {
      _creatingEvent = true;
      _loadingDashboard = true;
    });
    try {
      final ev = await _service.createEvent(
        code: _evCodeCtrl.text.trim(),
        title: _evTitleCtrl.text.trim(),
        zone: _evZoneCtrl.text.trim().isEmpty ? null : _evZoneCtrl.text.trim(),
      );
      if (!mounted) return;
      _events = [..._events, ev];
      _evCodeCtrl.clear();
      _evTitleCtrl.clear();
      _evZoneCtrl.clear();
    } finally {
      setState(() {
        _creatingEvent = false;
        _loadingDashboard = false;
      });
    }
  }

  void _handleDeleteEvent(String code) {
    setState(() {
      _events = _events.where((e) => e.code != code).toList();
    });
  }

  void _handleDeleteModerator(Moderator mod) {
    setState(() {
      _moderators = _moderators.where((m) => m.id != mod.id).toList();
    });
  }

  void _toggleSandboxConnection() {
    if (SandboxController.instance.connectionState == SandboxConnectionState.connected) {
      SandboxController.instance.disconnect();
    } else {
      SandboxController.instance.connect();
    }
  }

  void _runSandboxSimulation() {
    SandboxController.instance.simulateUsers(count: 5);
  }

  void _reloadSandbox() {
    setState(() => _isLoadingSandbox = true);
    SandboxController.instance.reload().then((_) {
      setState(() => _isLoadingSandbox = false);
    });
  }

'''

# Insert before class_end (0-indexed: class_end - 1)
lines.insert(class_end - 1, members)

with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')

print('Done. New line count:', len(lines))
