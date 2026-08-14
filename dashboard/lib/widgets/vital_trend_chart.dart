import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';

import '../core/models.dart';

enum VitalMetric { heartRate, spo2, temperature, systolic }

extension VitalMetricLabel on VitalMetric {
  String get label => switch (this) {
        VitalMetric.heartRate => 'Heart rate',
        VitalMetric.spo2 => 'SpO₂',
        VitalMetric.temperature => 'Temperature',
        VitalMetric.systolic => 'Blood pressure',
      };

  String get unit => switch (this) {
        VitalMetric.heartRate => 'bpm',
        VitalMetric.spo2 => '%',
        VitalMetric.temperature => '°C',
        VitalMetric.systolic => 'mmHg',
      };

  double? value(VitalReading item) => switch (this) {
        VitalMetric.heartRate => item.heartRate,
        VitalMetric.spo2 => item.spo2,
        VitalMetric.temperature => item.temperature,
        VitalMetric.systolic => item.systolic,
      };
}

class VitalTrendChart extends StatelessWidget {
  const VitalTrendChart({super.key, required this.items, required this.metric});

  final List<VitalReading> items;
  final VitalMetric metric;

  @override
  Widget build(BuildContext context) {
    final points = <FlSpot>[];
    for (var index = 0; index < items.length; index++) {
      final value = metric.value(items[index]);
      if (value != null) points.add(FlSpot(index.toDouble(), value));
    }
    if (points.isEmpty) {
      return const SizedBox(
        height: 240,
        child: Center(child: Text('No readings are available for this period.')),
      );
    }
    final minY = points.map((point) => point.y).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((point) => point.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.15;
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: minY - padding,
          maxY: maxY + padding,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (spot) => LineTooltipItem(
                      '${spot.y.toStringAsFixed(1)} ${metric.unit}\n${_labelFor(spot.x.toInt())}',
                      MaatriTokens.type(size: MaatriTokens.type12, color: Colors.white),
                    ),
                  )
                  .toList(),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, _) => Text(
                  value.toStringAsFixed(0),
                  style: MaatriTokens.type(size: MaatriTokens.type12),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (points.length / 3).ceilToDouble().clamp(1, double.infinity),
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(top: MaatriTokens.space4),
                  child: Text(
                    _labelFor(value.toInt()),
                    style: MaatriTokens.type(size: MaatriTokens.type12),
                  ),
                ),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points,
              isCurved: false,
              color: MaatriTokens.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: MaatriTokens.primary.withValues(alpha: 0.1)),
            ),
          ],
        ),
      ),
    );
  }

  String _labelFor(int index) {
    if (index < 0 || index >= items.length || items[index].capturedAt == null) return '';
    return DateFormat('HH:mm').format(items[index].capturedAt!);
  }
}
