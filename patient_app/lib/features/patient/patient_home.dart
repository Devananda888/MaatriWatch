import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// Patient companion experience for readings, help requests and check-ins.
class PatientHome extends StatefulWidget {
  const PatientHome({super.key});

  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  var _screening = false;
  var _submitted = false;
  int _questionOne = 0;
  int _questionTwo = 0;
  int _questionThree = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('MaatriWatch')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space16),
            child: _screening ? _screeningView(context) : _homeView(context),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _screening ? 1 : 0,
          onDestinationSelected: (index) => setState(() => _screening = index == 1),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Check-in'),
          ],
        ),
      );

  Widget _homeView(BuildContext context) => ListView(
        children: [
          Text('Hello, Asha', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: MaatriTokens.space8),
          Text('Your latest wearable readings look stable.', style: MaatriTokens.type(size: MaatriTokens.type16, color: MaatriTokens.textMuted)),
          const SizedBox(height: MaatriTokens.space24),
          const _PatientVitalTile(icon: Icons.favorite_outline_rounded, label: 'Heart', detail: 'Normal'),
          const SizedBox(height: MaatriTokens.space12),
          const _PatientVitalTile(icon: Icons.air_rounded, label: 'Oxygen', detail: 'Good'),
          const SizedBox(height: MaatriTokens.space12),
          const _PatientVitalTile(icon: Icons.thermostat_outlined, label: 'Temperature', detail: 'Normal'),
          const SizedBox(height: MaatriTokens.space32),
          SizedBox(
            height: 80,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: MaatriTokens.critical, 
                foregroundColor: Colors.white,
                textStyle: MaatriTokens.type(size: 24, weight: FontWeight.w900, color: Colors.white),
                elevation: 6,
                shadowColor: MaatriTokens.critical.withValues(alpha: 0.5),
              ),
              icon: const Icon(Icons.sos_rounded, size: 36),
              label: const Text('SOS - I need help'),
              onPressed: _confirmSos,
            ),
          ),
          const SizedBox(height: MaatriTokens.space12),
          Text('Press SOS any time you need urgent help.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Widget _screeningView(BuildContext context) {
    if (_submitted) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: MaatriTokens.success, size: 52),
                const SizedBox(height: MaatriTokens.space16),
                Text('Thank you', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: MaatriTokens.space8),
                const Text('Your check-in has been saved.'),
              ],
            ),
          ),
        ),
      );
    }
    return ListView(
      children: [
        Text('How are you feeling?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: MaatriTokens.space8),
        const Text('A short wellbeing check-in. You can skip any question.'),
        const SizedBox(height: MaatriTokens.space24),
        _QuestionCard(
          number: 1,
          question: 'In the last week, have you felt able to enjoy things?',
          value: _questionOne,
          onChanged: (value) => setState(() => _questionOne = value),
        ),
        const SizedBox(height: MaatriTokens.space12),
        _QuestionCard(
          number: 2,
          question: 'In the last week, have you felt worried or overwhelmed?',
          value: _questionTwo,
          onChanged: (value) => setState(() => _questionTwo = value),
        ),
        const SizedBox(height: MaatriTokens.space12),
        _QuestionCard(
          number: 3,
          question: 'Would you like someone from your care team to call you?',
          value: _questionThree,
          onChanged: (value) => setState(() => _questionThree = value),
        ),
        const SizedBox(height: MaatriTokens.space24),
        ElevatedButton(onPressed: () => setState(() => _submitted = true), child: const Text('Finish check-in')),
      ],
    );
  }

  void _confirmSos() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help request confirmed'),
        content: const Text('Your care team has been notified. Please stay somewhere safe while you wait for support.'),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Okay'))],
      ),
    );
  }
}

class _PatientVitalTile extends StatelessWidget {
  const _PatientVitalTile({required this.icon, required this.label, required this.detail});

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space24),
          child: Row(
            children: [
              Icon(icon, color: MaatriTokens.primary, size: 48),
              const SizedBox(width: MaatriTokens.space24),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.titleLarge)),
              Text(detail, style: MaatriTokens.type(size: MaatriTokens.type16, weight: FontWeight.w700, color: MaatriTokens.success)),
            ],
          ),
        ),
      );
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.number, required this.question, required this.value, required this.onChanged});

  final int number;
  final String question;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          child: RadioGroup<int>(
            groupValue: value,
            onChanged: (item) => onChanged(item ?? 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$number. $question', style: Theme.of(context).textTheme.titleMedium),
                const RadioListTile<int>(title: Text('Not at all'), value: 0),
                const RadioListTile<int>(title: Text('Sometimes'), value: 1),
                const RadioListTile<int>(title: Text('Often'), value: 2),
              ],
            ),
          ),
        ),
      );
}
