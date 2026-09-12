import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/patient_api.dart';

/// Care-coordination screens. None of these screens diagnose a condition or
/// turn a patient-reported statement into a clinician-confirmed fact.
class PatientCareMessagesPage extends StatefulWidget {
  const PatientCareMessagesPage({super.key, required this.api});
  final PatientApi api;

  @override
  State<PatientCareMessagesPage> createState() =>
      _PatientCareMessagesPageState();
}

class _PatientCareMessagesPageState extends State<PatientCareMessagesPage> {
  final _composer = TextEditingController();
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.messages();
      if (mounted) {
        setState(() => _messages = (result['items'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList());
      }
    } on PatientApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Messages could not be loaded. Please try again.');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final result = await widget.api.sendMessage(text);
      if (!mounted) return;
      final message = result['message'];
      setState(() {
        if (message is Map) {
          _messages = [..._messages, Map<String, dynamic>.from(message)];
        }
        _composer.clear();
      });
      final notice = result['notice'] as String?;
      if (notice != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(notice)));
      }
    } on PatientApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('We could not send your message. Please try again.')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ask your care team')),
        body: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _InfoCard(
              icon: Icons.forum_outlined,
              text:
                  'Send non-urgent questions to your assigned care team. This is not an emergency service and does not expose a clinician’s personal phone number.',
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: Text(_error!)))
                    : _messages.isEmpty
                        ? const Center(
                            child: Text(
                                'No messages yet. Ask a non-urgent question below.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final item = _messages[index];
                                final mine = item['sender_role'] == 'patient';
                                return Align(
                                  alignment: mine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    constraints:
                                        const BoxConstraints(maxWidth: 320),
                                    decoration: BoxDecoration(
                                      color: mine
                                          ? const Color(0xffDDEFE9)
                                          : const Color(0xffF1F4F4),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              mine
                                                  ? 'You'
                                                  : (item['sender_name']
                                                          as String? ??
                                                      'Care team'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge),
                                          const SizedBox(height: 4),
                                          Text(item['body'] as String? ?? ''),
                                        ]),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        hintText: 'Write a non-urgent question'),
                  ),
                ),
                IconButton(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded)),
              ]),
            ),
          ),
        ]),
      );
}

class PatientAssistantPage extends StatefulWidget {
  const PatientAssistantPage({super.key, required this.api});
  final PatientApi api;

  @override
  State<PatientAssistantPage> createState() => _PatientAssistantPageState();
}

class _PatientAssistantPageState extends State<PatientAssistantPage> {
  final _composer = TextEditingController();
  final List<_AssistantMessage> _messages = [
    const _AssistantMessage(
      text:
          'Hello. I can provide general maternal-care education and help you decide what to ask your care team. I cannot see your medical record or live watch readings.',
      mine: false,
    ),
  ];
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(_AssistantMessage(text: text, mine: true));
      _composer.clear();
      _sending = true;
    });
    try {
      final result = await widget.api.askAssistant(text);
      if (!mounted) return;
      setState(() => _messages.add(_AssistantMessage(
          text: result['answer'] as String? ??
              'I could not prepare a response. Please contact your care team.',
          mine: false,
          urgent: result['urgent'] == true)));
    } on PatientApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('MaatriCare AI is unavailable. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('MaatriCare AI')),
        body: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _InfoCard(
              icon: Icons.auto_awesome_outlined,
              text:
                  'General education only. MaatriCare AI cannot diagnose, prescribe, interpret results, or monitor your watch. For urgent symptoms or feeling unsafe, seek emergency help now.',
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: message.urgent
                          ? const Color(0xffFFF1EE)
                          : message.mine
                              ? const Color(0xffDDEFE9)
                              : const Color(0xffF1F4F4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(message.text),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    enabled: !_sending,
                    maxLength: 800,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                        hintText: 'Ask a general care question'),
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ]),
      );
}

class _AssistantMessage {
  const _AssistantMessage(
      {required this.text, required this.mine, this.urgent = false});
  final String text;
  final bool mine;
  final bool urgent;
}

class PatientActivityPage extends StatefulWidget {
  const PatientActivityPage({super.key, required this.api});
  final PatientApi api;

  @override
  State<PatientActivityPage> createState() => _PatientActivityPageState();
}

class _PatientActivityPageState extends State<PatientActivityPage> {
  final _minutes = TextEditingController(text: '30');
  List<Map<String, dynamic>> _entries = const [];
  String _clearance = 'not_recorded';
  String _part = 'morning';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await widget.api.activity();
      if (mounted) {
        setState(() {
          _clearance =
              result['activity_clearance'] as String? ?? 'not_recorded';
          _entries = (result['items'] as List? ?? const [])
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Activity records could not be loaded.')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _record() async {
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes < 1 || minutes > 180) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a whole number of minutes between 1 and 180.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.recordActivity(
          activityType: 'walking', sessionPart: _part, minutes: minutes);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Your patient-reported walk was recorded.')));
      }
    } on PatientApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleared = _clearance == 'cleared_by_clinician';
    return Scaffold(
      appBar: AppBar(title: const Text('Walking & activity')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              _InfoCard(
                icon: Icons.directions_walk_outlined,
                text: cleared
                    ? 'Your care team has marked activity tracking as appropriate. Record a comfortable morning or evening walk only as advised in your personal care plan.'
                    : 'Ask your care team before starting or tracking a walking routine. Activity recommendations must be personalised for pregnancy and postpartum care.',
              ),
              const SizedBox(height: 16),
              Text('Record a walk',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'morning', label: Text('Morning')),
                  ButtonSegment(value: 'evening', label: Text('Evening')),
                ],
                selected: {_part},
                onSelectionChanged:
                    cleared ? (v) => setState(() => _part = v.first) : null,
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: cleared,
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes walked'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: cleared && !_saving ? _record : null,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'Saving…' : 'Record walk'),
              ),
              const SizedBox(height: 22),
              Text('Recent activity',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_entries.isEmpty)
                const Text(
                    'No activity has been recorded. Wearable automatic tracking will appear only after its classifier is clinically evaluated.')
              else
                ..._entries.map((entry) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.directions_walk,
                            color: MaatriTokens.primary),
                        title: Text(
                            '${entry['minutes'] ?? '--'} minutes • ${entry['session_part'] ?? 'walk'}'),
                        subtitle: Text(entry['source'] == 'wearable_classifier'
                            ? 'Wearable-classified activity'
                            : 'Patient-reported activity'),
                      ),
                    )),
            ]),
    );
  }
}

class PatientClinicalProfilePage extends StatefulWidget {
  const PatientClinicalProfilePage({super.key, required this.api});
  final PatientApi api;

  @override
  State<PatientClinicalProfilePage> createState() =>
      _PatientClinicalProfilePageState();
}

class _PatientClinicalProfilePageState
    extends State<PatientClinicalProfilePage> {
  final _complications = TextEditingController();
  final _conditions = TextEditingController();
  final _allergies = TextEditingController();
  final _medicines = TextEditingController();
  String _stage = 'not_recorded';
  String _clearance = 'not_recorded';
  bool _hypertension = false;
  bool _gdmHistory = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _complications.dispose();
    _conditions.dispose();
    _allergies.dispose();
    _medicines.dispose();
    super.dispose();
  }

  List<String> _items(TextEditingController controller) => controller.text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();

  Future<void> _load() async {
    try {
      final result = await widget.api.clinicalProfile();
      final profile = result['profile'] is Map
          ? Map<String, dynamic>.from(result['profile'] as Map)
          : <String, dynamic>{};
      final history = profile['patient_reported_history'] is Map
          ? Map<String, dynamic>.from(
              profile['patient_reported_history'] as Map)
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          _stage = profile['pregnancy_stage'] as String? ?? 'not_recorded';
          _clearance =
              profile['activity_clearance'] as String? ?? 'not_recorded';
          _hypertension = history['previous_hypertension'] == true;
          _gdmHistory = history['gdm_or_diabetes_history'] == true;
          _complications.text =
              (history['previous_pregnancy_complications'] as List? ?? const [])
                  .join(', ');
          _conditions.text =
              (history['other_conditions'] as List? ?? const []).join(', ');
          _allergies.text =
              (history['allergies'] as List? ?? const []).join(', ');
          _medicines.text =
              (profile['current_medications'] as List? ?? const []).join(', ');
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your profile could not be loaded.')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final result = await widget.api.updateClinicalProfile({
        'pregnancy_stage': _stage,
        'history': {
          'previous_hypertension': _hypertension,
          'gdm_or_diabetes_history': _gdmHistory,
          'previous_pregnancy_complications': _items(_complications),
          'other_conditions': _items(_conditions),
          'allergies': _items(_allergies),
        },
        'current_medications': _items(_medicines),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                result['message'] as String? ?? 'Profile saved for review.')));
      }
    } on PatientApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Health profile')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: [
                const _InfoCard(
                  icon: Icons.verified_user_outlined,
                  text:
                      'Share information that may help your care team personalise follow-up. Your entries are patient-reported until a clinician reviews them.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _stage,
                  decoration:
                      const InputDecoration(labelText: 'Pregnancy stage'),
                  items: const [
                    DropdownMenuItem(
                        value: 'not_recorded', child: Text('Not recorded')),
                    DropdownMenuItem(
                        value: 'first_trimester',
                        child: Text('First trimester')),
                    DropdownMenuItem(
                        value: 'second_trimester',
                        child: Text('Second trimester')),
                    DropdownMenuItem(
                        value: 'third_trimester',
                        child: Text('Third trimester')),
                    DropdownMenuItem(
                        value: 'postpartum', child: Text('Postpartum')),
                  ],
                  onChanged: (value) =>
                      setState(() => _stage = value ?? 'not_recorded'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _hypertension,
                  onChanged: (value) => setState(() => _hypertension = value),
                  title: const Text('Previous hypertension'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _gdmHistory,
                  onChanged: (value) => setState(() => _gdmHistory = value),
                  title: const Text('Previous GDM or diabetes history'),
                ),
                _listField(_complications, 'Previous pregnancy complications'),
                _listField(_conditions, 'Other relevant conditions'),
                _listField(_allergies, 'Allergies'),
                _listField(_medicines, 'Current medications'),
                const SizedBox(height: 12),
                Text('Activity status: ${_clearance.replaceAll('_', ' ')}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child:
                      Text(_saving ? 'Saving…' : 'Save for clinician review'),
                ),
              ]),
      );

  Widget _listField(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: controller,
          maxLength: 800,
          decoration: InputDecoration(labelText: '$label (comma-separated)'),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xffE5F4EF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: MaatriTokens.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}
