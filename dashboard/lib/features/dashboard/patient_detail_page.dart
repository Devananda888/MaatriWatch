import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/vital_trend_chart.dart';

class PatientDetailPage extends StatefulWidget {
  const PatientDetailPage({
    super.key,
    required this.api,
    required this.hospital,
    required this.patient,
  });

  final ApiClient api;
  final HospitalMembership hospital;
  final PatientSummary patient;

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  PatientDetail? _detail;
  List<VitalReading> _vitals = const [];
  List<ClinicalNote> _notes = const [];
  List<AlertItem> _alerts = const [];
  bool _loading = true;
  bool _savingNote = false;
  String? _error;
  VitalMetric _metric = VitalMetric.heartRate;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.api.patient(widget.hospital.hospitalId, widget.patient.id),
        widget.api.vitals(widget.hospital.hospitalId, widget.patient.id),
        widget.api.notes(widget.hospital.hospitalId, widget.patient.id),
        widget.api.alerts(widget.hospital.hospitalId, patientId: widget.patient.id),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = values[0] as PatientDetail;
        _vitals = values[1] as List<VitalReading>;
        _notes = values[2] as List<ClinicalNote>;
        _alerts = values[3] as List<AlertItem>;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'We could not load this patient record. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _createNote() async {
    final text = _note.text.trim();
    if (text.isEmpty || _savingNote) return;
    setState(() => _savingNote = true);
    try {
      final created = await widget.api.createNote(widget.hospital.hospitalId, widget.patient.id, text);
      if (!mounted) return;
      setState(() {
        _notes = [created, ..._notes];
        _note.clear();
      });
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.patient.name ?? widget.patient.name),
        actions: [
          IconButton(tooltip: 'Refresh patient record', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: MaatriTokens.space8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : detail == null
                  ? const SizedBox.shrink()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1000;
                        final main = _mainColumn(context, detail);
                        final side = _notesAndAlerts(context);
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(MaatriTokens.space16),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 3, child: main),
                                    const SizedBox(width: MaatriTokens.space16),
                                    Expanded(flex: 2, child: side),
                                  ],
                                )
                              : Column(children: [main, const SizedBox(height: MaatriTokens.space16), side]),
                        );
                      },
                    ),
    );
  }

  Widget _mainColumn(BuildContext context, PatientDetail detail) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: MaatriTokens.space16,
                runSpacing: MaatriTokens.space12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.patient.name, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: MaatriTokens.space4),
                      Text('MRN ${detail.patient.medicalRecordNumber}  •  ${detail.patient.language ?? 'Language not recorded'}'),
                      if (detail.patient.deliveryDate != null)
                        Text('Delivery date: ${DateFormat('d MMM y').format(detail.patient.deliveryDate!)}'),
                    ],
                  ),
                  StatusChip(status: detail.status),
                ],
              ),
            ),
          ),
          const SizedBox(height: MaatriTokens.space16),
          _VitalsSnapshot(reading: detail.latestVital),
          const SizedBox(height: MaatriTokens.space16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: MaatriTokens.space12,
                    runSpacing: MaatriTokens.space8,
                    children: [
                      Text('Vital trends (last 24 hours)', style: Theme.of(context).textTheme.titleLarge),
                      SegmentedButton<VitalMetric>(
                        segments: VitalMetric.values
                            .map((metric) => ButtonSegment(value: metric, label: Text(metric.label)))
                            .toList(growable: false),
                        selected: {_metric},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) => setState(() => _metric = selection.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: MaatriTokens.space16),
                  VitalTrendChart(items: _vitals, metric: _metric),
                ],
              ),
            ),
          ),
          if (detail.latestScreening != null && detail.latestScreening!.isNotEmpty) ...[
            const SizedBox(height: MaatriTokens.space16),
            _ScreeningSummary(screening: detail.latestScreening!),
          ],
        ],
      );

  Widget _notesAndAlerts(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Clinical notes', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: MaatriTokens.space12),
                  TextField(
                    controller: _note,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 5000,
                    decoration: const InputDecoration(hintText: 'Add a clinical note'),
                  ),
                  const SizedBox(height: MaatriTokens.space8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _savingNote ? null : _createNote,
                      icon: _savingNote
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_comment_outlined),
                      label: const Text('Add note'),
                    ),
                  ),
                  const Divider(height: MaatriTokens.space32),
                  if (_notes.isEmpty)
                    const Text('No clinical notes yet.')
                  else
                    ..._notes.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: MaatriTokens.space16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(note.note),
                            const SizedBox(height: MaatriTokens.space4),
                            Text(
                              '${note.authorName ?? 'Clinician'}${note.createdAt == null ? '' : '  •  ${DateFormat('d MMM, HH:mm').format(note.createdAt!)}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MaatriTokens.space16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active alerts', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: MaatriTokens.space12),
                  if (_alerts.isEmpty)
                    const Text('No active alerts.')
                  else
                    ..._alerts.map(
                      (alert) => Padding(
                        padding: const EdgeInsets.only(bottom: MaatriTokens.space12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(spacing: MaatriTokens.space8, children: [StatusChip(status: alert.severity, compact: true), StatusChip(status: alert.status, compact: true)]),
                            const SizedBox(height: MaatriTokens.space4),
                            Text(alert.message),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _VitalsSnapshot extends StatelessWidget {
  const _VitalsSnapshot({this.reading});

  final VitalReading? reading;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _VitalValue(icon: Icons.favorite_outline_rounded, label: 'Heart rate', value: reading?.heartRate == null ? '—' : '${reading!.heartRate!.toStringAsFixed(0)} bpm'),
      _VitalValue(icon: Icons.air_rounded, label: 'SpO₂', value: reading?.spo2 == null ? '—' : '${reading!.spo2!.toStringAsFixed(0)}%'),
      _VitalValue(icon: Icons.thermostat_outlined, label: 'Temperature', value: reading?.temperature == null ? '—' : '${reading!.temperature!.toStringAsFixed(1)} °C'),
      _VitalValue(
        icon: Icons.monitor_heart_outlined,
        label: 'Blood pressure',
        value: reading?.systolic == null || reading?.diastolic == null
            ? '—'
            : '${reading!.systolic!.toStringAsFixed(0)}/${reading!.diastolic!.toStringAsFixed(0)}',
      ),
    ];
    return Wrap(
      spacing: MaatriTokens.space12,
      runSpacing: MaatriTokens.space12,
      children: cards.map((card) => SizedBox(width: 170, child: card)).toList(growable: false),
    );
  }
}

class _VitalValue extends StatelessWidget {
  const _VitalValue({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: MaatriTokens.primary),
              const SizedBox(height: MaatriTokens.space12),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _ScreeningSummary extends StatelessWidget {
  const _ScreeningSummary({required this.screening});

  final Map<String, dynamic> screening;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Latest screening', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: MaatriTokens.space8),
              Text('${screening['screening_type'] ?? 'Screening'}  •  ${screening['risk_level'] ?? 'Not classified'}'),
              if (screening['score'] != null) Text('Score: ${screening['score']}'),
            ],
          ),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, color: MaatriTokens.warning, size: 42),
              const SizedBox(height: MaatriTokens.space16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: MaatriTokens.space16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}
