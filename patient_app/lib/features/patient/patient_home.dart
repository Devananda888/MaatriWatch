import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/patient_api.dart';

/// Patient-facing safety companion. It routes concerns to care teams; it does not diagnose.
class PatientHome extends StatefulWidget {
  const PatientHome({super.key, this.api, this.onSignOut, this.onAccessDenied});
  final PatientApi? api;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onAccessDenied;
  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  PatientApi? _fallbackApi;
  Map<String, dynamic> _data = const {};
  Map<String, bool> _consents = {};
  int _page = 0;
  bool _busy = false;
  String? _offline;
  String? _accessDenied;
  PatientApi get _api => widget.api ?? (_fallbackApi ??= PatientApi());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _offline = null;
      _accessDenied = null;
    });
    try {
      final values = await Future.wait([_api.home(), _api.consents()]);
      final consents = values[1]['items'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _data = values[0];
          _consents = {
            for (final item in consents.whereType<Map>())
              item['consent_type'] as String: item['granted'] == true
          };
        });
      }
    } on PatientApiException catch (error) {
      if (mounted) {
        if (error.statusCode == 401 || error.statusCode == 403) {
          setState(() => _accessDenied = error.message);
        } else {
          setState(() => _offline =
              'Live data is unavailable. Check your connection before relying on this screen.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _offline =
            'Live data is unavailable. Check your connection before relying on this screen.');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_accessDenied != null) {
      return _AccountAccessDenied(
        message: _accessDenied!,
        onSignOut: widget.onAccessDenied ?? widget.onSignOut,
      );
    }
    return Scaffold(
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: _load,
                child: IndexedStack(
                    index: _page,
                    children: [_home(), _plan(), _help(), _profile()]))),
        bottomNavigationBar: NavigationBar(
            selectedIndex: _page,
            onDestinationSelected: (i) => setState(() => _page = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Care plan'),
              NavigationDestination(
                  icon: Icon(Icons.health_and_safety_outlined),
                  selectedIcon: Icon(Icons.health_and_safety),
                  label: 'Get help'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile'),
            ]),
      );
  }

  Widget _home() {
    final patient = _map(_data['patient']);
    final vital = _map(_data['latest_vital']);
    final device = _map(_data['device']);
    final deviceHealth = _map(_data['device_health']);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hello, ${_first(patient['full_name'])}',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(_days(patient['delivery_date']),
              style: Theme.of(context).textTheme.bodyMedium)
        ])),
        IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh')
      ]),
      if (_busy)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator()),
      if (_offline != null)
        _Notice(
            icon: Icons.cloud_off_outlined,
            text: _offline!,
            color: MaatriTokens.warning),
      const SizedBox(height: 16),
      _Safety(onTap: () => setState(() => _page = 2)),
      const SizedBox(height: 20),
      Text('Your wearable', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const CircleAvatar(
                    backgroundColor: Color(0xffE5F4EF),
                    child: Icon(Icons.watch_outlined,
                        color: MaatriTokens.primary)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          deviceHealth['title'] as String? ??
                              (device.isEmpty
                                  ? 'Wearable not connected'
                                  : 'Wearable connected'),
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                          deviceHealth['message'] as String? ??
                              (vital.isEmpty
                                  ? 'Waiting for a reading'
                                  : _readingContext(vital, 'wearable')),
                          style: Theme.of(context).textTheme.bodySmall)
                    ])),
                if (vital['battery_percent'] != null)
                  Text('${vital['battery_percent']}%',
                      style: const TextStyle(fontWeight: FontWeight.w800))
              ]))),
      const SizedBox(height: 20),
      Text('Latest readings', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _Vital('PPG-derived heart rate',
            _reading(vital, 'heart_rate_bpm', 'bpm'),
            _readingContext(vital, _source(vital['heart_rate_source'])),
            Icons.favorite_outline, const Color(0xffC9546C)),
        _Vital('PPG-derived SpO₂', _reading(vital, 'spo2_percent', '%'),
            _readingContext(vital, _source(vital['spo2_source'])),
            Icons.air_rounded, const Color(0xff317D9D)),
        _Vital(
            'Device / skin-adjacent temperature',
            _reading(vital, 'skin_adjacent_temperature_c', '°C'),
            _readingContext(vital, _source(vital['temperature_source'])),
            Icons.thermostat_outlined,
            const Color(0xffD8863F)),
        _Vital(
            'Blood pressure (validated source)',
            _hasValidatedBloodPressure(vital) && _fresh(vital)
                ? '${vital['systolic_bp']}/${vital['diastolic_bp']} mmHg'
                : 'Not currently available',
            _readingContext(vital, _source(vital['blood_pressure_source'])),
            Icons.monitor_heart_outlined,
            const Color(0xff7062A6))
      ]),
      const SizedBox(height: 20),
      Text('Next step', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      _task((_data['care_plan'] as List? ?? const []).isEmpty
          ? null
          : (_data['care_plan'] as List).first),
      const SizedBox(height: 16),
      Text(
          'Wearable readings support your care team. They do not diagnose illness or replace medical advice.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _plan() {
    final tasks = _data['care_plan'] as List<dynamic>? ?? const [];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Your care plan', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text('Small steps help your care team support you between visits.'),
      const SizedBox(height: 16),
      if (tasks.isEmpty)
        const _Empty(
            icon: Icons.event_available_outlined,
            title: 'You are up to date',
            text: 'No care-plan tasks are due.'),
      ...tasks.whereType<Map>().map((t) => _task(t)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
          onPressed: _report,
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('Complete a wellbeing check-in'))
    ]);
  }

  Widget _help() {
    final signs = _data['danger_signs'] as List<dynamic>? ?? const [];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Get help', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text(
          'If something does not feel right, trust yourself and ask for help.'),
      const SizedBox(height: 18),
      SizedBox(
          height: 68,
          child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: MaatriTokens.critical,
                  foregroundColor: Colors.white),
              onPressed: _sos,
              icon: const Icon(Icons.sos_rounded, size: 30),
              label: const Text('SOS — I need urgent help'))),
      const SizedBox(height: 10),
      OutlinedButton.icon(
          onPressed: _report,
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('Report symptoms to my care team')),
      const SizedBox(height: 24),
      Text('Urgent warning signs',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Get emergency care immediately for any of these.'),
      ...signs.whereType<Map>().map((s) => Card(
          child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded,
                  color: MaatriTokens.critical),
              title: Text(s['title'] as String? ?? ''),
              subtitle: Text(s['action'] as String? ?? '')))),
      const _Notice(
          icon: Icons.info_outline,
          text:
              'In an emergency, call your local emergency number or go to the nearest hospital. Do not wait for an app reply.',
          color: MaatriTokens.critical)
    ]);
  }

  Widget _profile() {
    final p = _map(_data['patient']);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Privacy & profile',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(p['hospital_name'] as String? ?? 'Your care team'),
      const SizedBox(height: 18),
      _row(Icons.language_outlined, 'Language',
          p['preferred_language'] as String? ?? 'English'),
      _row(
          Icons.contact_phone_outlined,
          'Emergency contact',
          p['emergency_contact_name'] as String? ??
              'Set up with your care team'),
      const SizedBox(height: 18),
      Text('Sharing choices', style: Theme.of(context).textTheme.titleLarge),
      const Text('Optional sharing can be changed at any time.'),
      _consent('Wearable monitoring', 'Share readings with your care team',
          'monitoring', true),
      _consent('Care-team sharing', 'Share records with assigned clinicians',
          'care_team_sharing', false),
      _consent(
          'Emergency contact',
          'Contact your chosen person when you request help',
          'emergency_contact',
          false),
      _consent('Location during SOS', 'Share location only with an SOS request',
          'location', false),
      const SizedBox(height: 12),
      if (widget.onSignOut != null)
        OutlinedButton.icon(
            onPressed: () async => widget.onSignOut!(),
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Sign out')),
      if (widget.onSignOut != null) const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: () => _message(
              'Your care team can help with a record copy or correction request.'),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Request my data'))
    ]);
  }

  Widget _task(dynamic raw) {
    if (raw is! Map) {
      return const _Empty(
          icon: Icons.check_circle_outline,
          title: 'All caught up',
          text: 'There are no care-plan tasks right now.');
    }
    final t = Map<String, dynamic>.from(raw);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check_circle_outline, color: MaatriTokens.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(t['title'] as String? ?? 'Care task',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (t['detail'] != null) Text(t['detail'] as String),
                  TextButton(
                      onPressed: () => _complete(t),
                      child: const Text('Mark complete')),
                ])),
          ]),
        ),
      ),
    );
  }

  Widget _consent(String title, String detail, String type, bool locked) =>
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(detail),
          value: locked || (_consents[type] ?? false),
          onChanged: locked
              ? null
              : (value) async {
                  try {
                    await _api.setConsent(type, value);
                    if (mounted) setState(() => _consents[type] = value);
                  } catch (_) {
                    _message(
                        'We could not update this choice. Please try again.');
                  }
                });
  Widget _row(IconData icon, String title, String detail) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: MaatriTokens.primary),
      title: Text(title),
      subtitle: Text(detail));
  Future<void> _complete(Map task) async {
    final id = task['id'] as String?;
    if (id == null) return;
    try {
      await _api.completeTask(id, 'completed');
      await _load();
    } catch (_) {
      _message('This task will be updated when you are back online.');
    }
  }

  Future<void> _sos() async {
    final note = await _dialog('Request urgent help',
        'Tell us anything your care team should know (optional).');
    if (note == null) return;
    try {
      await _api.sos(note);
      _message(
          'Help request sent. If this is life-threatening, call emergency services now.');
    } catch (_) {
      _message(
          'We could not send this request. Call emergency services or your care team now.');
    }
  }

  Future<void> _report() async {
    final choice = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _Symptoms());
    if (choice == null) return;
    try {
      final result = await _api.symptoms(choice, '');
      _message(result['urgent'] == true
          ? 'Urgent report sent. Seek medical care now.'
          : 'Your report was sent to your care team.');
    } catch (_) {
      _message(
          'Unable to send now. Please call your care team if you need help.');
    }
  }

  Future<String?> _dialog(String title, String hint) {
    final c = TextEditingController();
    return showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: c,
                    maxLength: 500,
                    decoration: InputDecoration(hintText: hint)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, c.text),
                      child: const Text('Send'))
                ]));
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  String _first(Object? name) => (name as String? ?? 'there').split(' ').first;
  String _reading(Map<String, dynamic> vital, String key, String unit) {
    if (!_fresh(vital) || vital[key] is! num) return 'Not currently available';
    return '${vital[key]} $unit';
  }

  bool _fresh(Map<String, dynamic> vital) {
    if (vital['is_fresh'] is bool) return vital['is_fresh'] as bool;
    if (vital['measurement_quality'] == 'unavailable' ||
        vital['contact_detected'] == false) {
      return false;
    }
    final raw = vital['captured_at'] ?? vital['observed_at'];
    final captured = raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    return captured != null &&
        DateTime.now().toUtc().difference(captured) <=
            const Duration(minutes: 10);
  }

  bool _hasValidatedBloodPressure(Map<String, dynamic> vital) {
    const sources = {
      'validated_cuff',
      'clinician_entered'
    };
    return sources.contains(vital['blood_pressure_source']) &&
        vital['systolic_bp'] is num &&
        vital['diastolic_bp'] is num;
  }

  String _source(Object? raw) => switch (raw) {
        'wearable_ppg' => 'MAX30102 PPG',
        'wearable_skin_adjacent' => 'TMP117 device / skin-adjacent',
        'validated_cuff' => 'Validated cuff',
        'external_validated_device' => 'Validated external device',
        'clinician_entered' => 'Clinician-entered',
        _ => 'Source unavailable',
      };

  String _readingContext(Map<String, dynamic> vital, String source) {
    final raw = vital['observed_at'] ?? vital['captured_at'];
    final observed = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    final time = observed == null
        ? 'observation time unavailable'
        : 'observed ${observed.hour.toString().padLeft(2, '0')}:${observed.minute.toString().padLeft(2, '0')}';
    final freshness = switch (vital['freshness']) {
      'current' => 'current',
      'stale' => 'stale',
      'unavailable' => 'unavailable',
      _ => _fresh(vital) ? 'current' : 'unavailable',
    };
    return '$source • $time • $freshness';
  }

  String _days(Object? date) {
    final d = date is String ? DateTime.tryParse(date) : null;
    return d == null
        ? 'Your maternal care companion'
        : '${DateTime.now().difference(d).inDays.clamp(0, 366)} days since delivery';
  }
}

class _Safety extends StatelessWidget {
  const _Safety({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xffFFF1EE),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.health_and_safety_outlined,
                    color: MaatriTokens.critical),
                SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Need help now?',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('See warning signs or send an SOS request.')
                    ]))
              ]))));
}

class _Vital extends StatelessWidget {
  const _Vital(this.label, this.value, this.context, this.icon, this.color);
  final String label, value, context;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: (MediaQuery.sizeOf(context).width - 50) / 2,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(height: 10),
                    Text(value, style: Theme.of(context).textTheme.titleLarge),
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 3),
                    Text(this.context,
                        style: Theme.of(context).textTheme.labelSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis)
                  ]))));
}

class _AccountAccessDenied extends StatelessWidget {
  const _AccountAccessDenied({required this.message, this.onSignOut});
  final String message;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_person_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text('Account access needed',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'Please contact your hospital care team. Do not rely on this app until access is restored.',
                    textAlign: TextAlign.center,
                  ),
                  if (onSignOut != null) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => onSignOut!(),
                      icon: const Icon(Icons.logout_outlined),
                      label: const Text('Sign out'),
                    )
                  ]
                ]),
              ),
            ),
          ),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text))
          ])));
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            Icon(icon, size: 36, color: MaatriTokens.primary),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(text, textAlign: TextAlign.center)
          ])));
}

class _Symptoms extends StatefulWidget {
  const _Symptoms();
  @override
  State<_Symptoms> createState() => _SymptomsState();
}

class _SymptomsState extends State<_Symptoms> {
  final selected = <String>{};
  static const items = {
    'heavy_bleeding': 'Heavy bleeding',
    'breathing': 'Trouble breathing or chest pain',
    'headache': 'Severe headache or vision change',
    'fever': 'Fever or feeling very unwell',
    'mental_health': 'Feeling unsafe or thoughts of harm',
    'other': 'Something else worries me'
  };
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What are you feeling?',
                    style: Theme.of(context).textTheme.titleLarge),
                const Text('Select anything that applies.'),
                ...items.entries.map((e) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(e.key),
                    onChanged: (v) => setState(() => v == true
                        ? selected.add(e.key)
                        : selected.remove(e.key)),
                    title: Text(e.value))),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(context, selected.toList()),
                        child: const Text('Send to care team')))
              ])));
}
