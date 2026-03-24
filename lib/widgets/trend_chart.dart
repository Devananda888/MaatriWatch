import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/theme.dart';
import '../models/vitals_model.dart';

class TrendChart extends StatelessWidget {
  final List<VitalsHistoryEntry> history;
  final String type; // 'hr' | 'spo2' | 'temp'
  final double? baseline;

  const TrendChart({
    super.key,
    required this.history,
    required this.type,
    this.baseline,
  });

  double _getValue(VitalsHistoryEntry e) {
    switch (type) {
      case 'hr':   return e.heartRate;
      case 'spo2': return e.spo2;
      case 'temp': return e.temperature;
      default:     return e.heartRate;
    }
  }

  String get _label {
    switch (type) {
      case 'hr':   return 'Heart Rate (BPM)';
      case 'spo2': return 'SpO₂ (%)';
      case 'temp': return 'Temperature (°C)';
      default:     return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Container(
        height: 180,
        decoration: AppTheme.cardDecoration,
        child: Center(
          child: Text('No data yet', style: AppTheme.caption),
        ),
      );
    }

    final spots = history
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), _getValue(e.value)))
        .toList();

    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b) - 5;
    final maxY = values.reduce((a, b) => a > b ? a : b) + 5;

    final barGroups = <LineChartBarData>[
      LineChartBarData(
        spots: spots,
        isCurved: true,
        color: AppTheme.pink,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.pink.withOpacity(0.15),
              Colors.transparent,
            ],
          ),
        ),
      ),
      if (baseline != null)
        LineChartBarData(
          spots: [
            FlSpot(0, baseline!),
            FlSpot((history.length - 1).toDouble(), baseline!),
          ],
          isCurved: false,
          color: AppTheme.gold.withOpacity(0.5),
          barWidth: 1,
          dashArray: [6, 4],
          dotData: const FlDotData(show: false),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_label, style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                backgroundColor: Colors.transparent,
                gridData: FlGridData(
                  drawHorizontalLine: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.pinkMuted.withOpacity(0.2),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (_) => FlLine(
                    color: AppTheme.pinkMuted.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineBarsData: barGroups,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.surfaceElevated,
                    getTooltipItems: (touchedSpots) => touchedSpots
                        .map((s) => LineTooltipItem(
                              s.y.toStringAsFixed(1),
                              AppTheme.caption.copyWith(color: AppTheme.pink),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
