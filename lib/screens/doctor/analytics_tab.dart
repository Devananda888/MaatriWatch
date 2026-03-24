import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../utils/theme.dart';
import '../../services/firebase_service.dart';

class AnalyticsTab extends StatelessWidget {
  final String doctorId;
  final bool demoMode;

  const AnalyticsTab({super.key, required this.doctorId, this.demoMode = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.doctorBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
              child: Text('Analytics', style: AppTheme.headline),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _statsRow(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alerts This Week', style: AppTheme.subhead),
                  const SizedBox(height: 12),
                  _alertsBarChart(),
                  const SizedBox(height: 20),
                  Text('Patient Risk Distribution', style: AppTheme.subhead),
                  const SizedBox(height: 12),
                  _riskPieChart(),
                  const SizedBox(height: 20),
                  Text('Avg Vitals — 7 Days', style: AppTheme.subhead),
                  const SizedBox(height: 12),
                  _avgVitalsChart(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.pinkMuted.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: AppTheme.subhead.copyWith(color: color, fontSize: 22)),
            const SizedBox(height: 2),
            Text(label, style: AppTheme.caption),
          ],
        ),
      ),
    );
  }

  Widget _statsRow() {
    return Column(
      children: [
        Row(
          children: [
            _statTile('3', 'Patients', AppTheme.pinkLight),
            const SizedBox(width: 8),
            _statTile('2', 'Alerts Today', AppTheme.error),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _statTile('82', 'Avg HR', AppTheme.warning),
            const SizedBox(width: 8),
            _statTile('97%', 'Avg SpO₂', AppTheme.success),
          ],
        ),
      ],
    );
  }

  Widget _alertsBarChart() {
    final data = [2.0, 1.0, 3.0, 0.0, 2.0, 4.0, 2.0];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: BarChart(
        BarChartData(
          backgroundColor: Colors.transparent,
          gridData: FlGridData(
            drawHorizontalLine: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.pinkMuted.withOpacity(0.2), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: data.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value,
                  gradient: const LinearGradient(
                    colors: [AppTheme.pink, AppTheme.pinkMuted],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(days[v.toInt()], style: AppTheme.caption),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _riskPieChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: 1,
                    color: AppTheme.success,
                    title: 'Normal',
                    radius: 60,
                    titleStyle: AppTheme.caption,
                  ),
                  PieChartSectionData(
                    value: 1,
                    color: AppTheme.warning,
                    title: 'Warning',
                    radius: 60,
                    titleStyle: AppTheme.caption,
                  ),
                  PieChartSectionData(
                    value: 1,
                    color: AppTheme.error,
                    title: 'Critical',
                    radius: 60,
                    titleStyle: AppTheme.caption,
                  ),
                ],
                sectionsSpace: 3,
                centerSpaceRadius: 30,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legend(AppTheme.success, 'Normal (1)'),
              _legend(AppTheme.warning, 'Warning (1)'),
              _legend(AppTheme.error, 'Critical (1)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 12, height: 12,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Text(label, style: AppTheme.caption),
        ],
      ),
    );
  }

  Widget _avgVitalsChart() {
    final hrData = [78.0, 82.0, 79.0, 85.0, 80.0, 77.0, 81.0];
    final spots = hrData
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return Container(
      height: 140,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: LineChart(
        LineChartData(
          backgroundColor: Colors.transparent,
          gridData: FlGridData(
            getDrawingHorizontalLine: (_) => FlLine(
                color: AppTheme.pinkMuted.withOpacity(0.2), strokeWidth: 1),
            getDrawingVerticalLine: (_) => FlLine(
                color: AppTheme.pinkMuted.withOpacity(0.1), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.gold,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppTheme.gold.withOpacity(0.15), Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
