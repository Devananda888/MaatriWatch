import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/design_tokens.dart';
import '../../core/patient_api.dart';

/// Patient-confirmed lab entry. Parsing is a convenience only: values must be
/// visible to the patient and explicitly confirmed before the API stores them.
class PatientLabResultPage extends StatefulWidget {
  const PatientLabResultPage({super.key, required this.api});
  final PatientApi api;
  @override
  State<PatientLabResultPage> createState() => _PatientLabResultPageState();
}

class _PatientLabResultPageState extends State<PatientLabResultPage> {
  final _report = TextEditingController();
  String _category = 'gestational_diabetes';
  Map<String, dynamic>? _extracted;
  PlatformFile? _selectedReport;
  bool _confirmed = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _report.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    setState(() {
      _busy = true;
      _message = null;
      _extracted = null;
      _confirmed = false;
    });
    try {
      final result = await widget.api.extractLabResult(_category, _report.text);
      if (!mounted) {
        return;
      }
      final values = result['values'] as Map? ?? const {};
      setState(() {
        _extracted = Map<String, dynamic>.from(result);
        _message = values.isEmpty
            ? 'We could not find a supported value. Check the report and enter/paste its labelled result.'
            : 'Review the extracted values against your report before saving.';
      });
    } on PatientApiException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'We could not read this result. Please try again.');
      }
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  String? _mediaType(PlatformFile file) {
    switch ((file.extension ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
    }
    return null;
  }

  Future<void> _chooseReport() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null || !mounted) return;
    final length = await file.length();
    if (!mounted) return;
    if (length > 4000000) {
      setState(() => _message = 'Choose a report smaller than 4 MB.');
      return;
    }
    setState(() {
      _selectedReport = file;
      _message =
          'Report selected. Upload it for clinician review, then confirm any values before saving them.';
    });
  }

  Future<void> _uploadReport() async {
    final file = _selectedReport;
    final mediaType = file == null ? null : _mediaType(file);
    if (file == null || mediaType == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final result = await widget.api.uploadReportDocument(
        bytes: bytes,
        filename: file.name,
        mediaType: mediaType,
        documentType: 'lab_report',
        confirmedText: _report.text,
      );
      if (mounted) {
        setState(() {
          _selectedReport = null;
          _message = result['message'] as String? ??
              'Report uploaded for clinician review.';
        });
      }
    } on PatientApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'We could not upload this report. Please try again.');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  bool get _hasCompleteValues {
    final values = _extracted?['values'];
    if (values is! Map) {
      return false;
    }
    return _category == 'gestational_diabetes'
        ? ['fasting', 'one_hour', 'two_hour'].every(values.containsKey)
        : values.containsKey('tsh');
  }

  Future<void> _save() async {
    if (!_confirmed || !_hasCompleteValues || _extracted == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.api.submitLabResult({
        'category': _category,
        'test_type': _extracted!['test_type'],
        'values': _extracted!['values'],
        'units': _extracted!['units'],
      });
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline,
              color: MaatriTokens.success),
          title: const Text('Sent for review'),
          content: Text(result['message'] as String? ??
              'Your care team will review this result.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'))
          ],
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on PatientApiException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'We could not save your result. Please try again.');
      }
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Lab result follow-up')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const _CareNotice(
            icon: Icons.info_outline,
            text:
                'Copy or type the labelled values from your laboratory report. The app only saves values you confirm and sends every result to a clinician for review.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _chooseReport,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_selectedReport == null
                ? 'Choose PDF or image report'
                : _selectedReport!.name),
          ),
          if (_selectedReport != null) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _busy ? null : _uploadReport,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload for clinician review'),
            ),
          ],
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'gestational_diabetes', label: Text('Glucose')),
              ButtonSegment(value: 'thyroid', label: Text('Thyroid')),
            ],
            selected: {_category},
            onSelectionChanged: (values) => setState(() {
              _category = values.first;
              _extracted = null;
              _confirmed = false;
              _message = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _report,
            maxLines: 5,
            maxLength: 5000,
            decoration: InputDecoration(
              labelText: 'Paste report text',
              hintText: _category == 'gestational_diabetes'
                  ? 'Fasting: 94 mg/dL; 1 hour: 171 mg/dL; 2 hour: 142 mg/dL'
                  : 'TSH: 2.1 mIU/L',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _report.text.trim().isEmpty ? null : _extract,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Extract values to review'),
          ),
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
          if (_message != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!)),
          if (_extracted != null) ...[
            const SizedBox(height: 16),
            Text('Confirm these values',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                    _formatValues(_extracted!['values'], _extracted!['units'])),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: _hasCompleteValues
                  ? (value) => setState(() => _confirmed = value ?? false)
                  : null,
              title: const Text(
                  'I confirm these values match my laboratory report.'),
              subtitle:
                  const Text('This result will be pending clinician review.'),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _confirmed && _hasCompleteValues && !_busy ? _save : null,
                child: const Text('Send for clinician review'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Important',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const Text(
              'The app does not decide whether a result is healthy, diagnose a condition, or change your diet or medicines. Contact your care team if you are worried.'),
        ]),
      );

  String _formatValues(Object? rawValues, Object? rawUnits) {
    final values = rawValues is Map ? rawValues : const {};
    final units = rawUnits is Map ? rawUnits : const {};
    if (values.isEmpty) return 'No supported values found.';
    return values.entries.map((entry) {
      final label = switch (entry.key) {
        'one_hour' => '1 hour',
        'two_hour' => '2 hours',
        'free_t4' => 'Free T4',
        'tsh' => 'TSH',
        _ => entry.key.toString(),
      };
      return '$label: ${entry.value} ${units[entry.key] ?? ''}'.trim();
    }).join('\n');
  }
}

/// A supportive five-item prompt, intentionally separate from the validated
/// 10-item EPDS. It makes only a safety escalation, never a diagnosis/score.
class PatientWellbeingPage extends StatefulWidget {
  const PatientWellbeingPage({super.key, required this.api});
  final PatientApi api;
  @override
  State<PatientWellbeingPage> createState() => _PatientWellbeingPageState();
}

class _PatientWellbeingPageState extends State<PatientWellbeingPage> {
  static const _regular = [
    ('never', 'Never'),
    ('some_days', 'Some days'),
    ('often', 'Often'),
    ('almost_every_day', 'Almost every day'),
    ('prefer_not_to_say', 'Prefer not to say'),
  ];
  final Map<String, String> _answers = {};
  bool _guardianConsent = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (_answers.length != 5) return;
    setState(() => _busy = true);
    try {
      final result =
          await widget.api.submitWellbeingCheckin(_answers, _guardianConsent);
      if (!mounted) return;
      final urgent = result['urgent'] == true;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
              urgent ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: urgent ? MaatriTokens.critical : MaatriTokens.success),
          title: Text(urgent ? 'Please get immediate help' : 'Check-in sent'),
          content: Text(result['message'] as String? ??
              'Your care team has been notified.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'))
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on PatientApiException catch (error) {
      _message(error.message);
    } catch (_) {
      _message(
          'We could not send your check-in. If you feel unsafe, call emergency services or go to the nearest hospital now.');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Wellbeing check-in')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.psychology_outlined,
                          color: MaatriTokens.primary),
                      const SizedBox(width: 8),
                      Text('Your emotional wellbeing',
                          style: Theme.of(context).textTheme.titleMedium),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                        'Pregnancy and the months after birth can bring low mood, loss of enjoyment, anxiety, feeling overwhelmed, or trouble bonding. These experiences are common and deserve support; they are not a personal failure.'),
                    const SizedBox(height: 8),
                    const Text(
                        'Tell your care team promptly if symptoms persist, interfere with daily life, or you feel unsafe. Thoughts of harming yourself or your baby need immediate emergency help—do not wait for an app reply.'),
                    const SizedBox(height: 8),
                    const Text(
                        'A clinician can offer a standard validated perinatal mental-health screen and follow-up. This short check-in does not replace that assessment.'),
                  ]),
            ),
          ),
          const SizedBox(height: 16),
          const _CareNotice(
            icon: Icons.favorite_border,
            text:
                'Suggested twice each week. This is a support check-in, not a diagnosis or a replacement for a validated clinical screen such as the 10-item EPDS.',
          ),
          const SizedBox(height: 16),
          _question(
              'mood',
              'Over the last few days, how often have you felt low, sad, or emotionally drained?',
              _regular),
          _question(
              'enjoyment',
              'How often have you found it hard to enjoy or look forward to things?',
              _regular),
          _question(
              'overwhelmed',
              'How often have you felt overwhelmed by day-to-day tasks?',
              _regular),
          _question(
              'support',
              'How often have you felt that you lacked the support you needed?',
              _regular),
          _question(
              'safety',
              'Have you had thoughts of harming yourself, or felt unsafe?',
              const [
                ('no', 'No'),
                ('yes', 'Yes'),
                ('prefer_not_to_say', 'Prefer not to say'),
              ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _guardianConsent,
            onChanged: (value) =>
                setState(() => _guardianConsent = value ?? false),
            title: const Text(
                'If I report an immediate safety concern, I consent to notifying my chosen guardian.'),
            subtitle: const Text(
                'Only works if the hospital has a verified, opted-in WhatsApp contact.'),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _answers.length == 5 && !_busy ? _submit : null,
              child: const Text('Send check-in'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
              'If you feel unsafe right now, call local emergency services or go to the nearest hospital. Do not wait for an app reply.'),
        ]),
      );

  Widget _question(String key, String label, List<(String, String)> choices) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String>(
          initialValue: _answers[key],
          decoration: InputDecoration(labelText: label),
          items: choices
              .map((choice) =>
                  DropdownMenuItem(value: choice.$1, child: Text(choice.$2)))
              .toList(),
          onChanged: (value) => setState(() => _answers[key] = value ?? ''),
        ),
      );
}

class _CareNotice extends StatelessWidget {
  const _CareNotice({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xffE5F4EF),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: MaatriTokens.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );
}
