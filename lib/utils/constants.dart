class AppConstants {
  // ── ALERT THRESHOLDS ──────────────────────────────────
  static const double hrHighThreshold     = 100.0;  // BPM
  static const double hrRiseThreshold     = 15.0;   // BPM from baseline
  static const double spo2LowThreshold    = 94.0;   // %
  static const double tempRiseThreshold   = 2.5;    // °C from baseline
  static const double tempDropThreshold   = 2.5;    // °C from baseline
  static const double freefallThreshold   = 0.3;    // g
  static const double impactThreshold     = 2.5;    // g
  static const double stillnessThreshold  = 0.1;    // g
  static const int    stillnessDuration   = 2000;   // ms
  static const int    alertCooldown       = 120000; // ms
  static const int    cancelWindow        = 3000;   // ms
  static const int    sosHoldDuration     = 3;      // seconds
  static const int    epdsHighThreshold   = 13;     // score

  // ── ALERT TYPES ───────────────────────────────────────
  static const String alertPphRisk         = 'PPH_RISK';
  static const String alertPreeclampsiaRisk= 'PREECLAMPSIA_RISK';
  static const String alertFallDetected    = 'FALL_DETECTED';
  static const String alertSosManual       = 'SOS_MANUAL';
  static const String alertInfectionRisk   = 'INFECTION_RISK';

  // ── ROLES ─────────────────────────────────────────────
  static const String roleDoctor  = 'doctor';
  static const String rolePatient = 'patient';

  // ── RISK LEVELS ───────────────────────────────────────
  static const String riskNormal   = 'normal';
  static const String riskWarning  = 'warning';
  static const String riskCritical = 'critical';

  // ── DEMO MODE ─────────────────────────────────────────
  static const String demoPatientName   = 'Priya Sharma';
  static const String demoDeviceId      = 'P001';
  static const int    demoAlertDelay    = 30; // seconds before PPH alert fires

  // ── NORMAL RANGES ─────────────────────────────────────
  static const String hrNormalRange   = '60 – 100 BPM';
  static const String spo2NormalRange = '95 – 100%';
  static const String tempNormalRange = '36.1 – 37.2°C';

  // ── AFFIRMATIONS (7 daily, rotating) ─────────────────
  static const List<String> affirmations = [
    'You are stronger than you know. Your body is doing something miraculous.',
    'Every breath you take is a gift — to yourself and to the life you carry.',
    'You are not alone. A whole team watches over you, every heartbeat.',
    'Rest is not weakness; it is the soil where healing grows.',
    'You have already shown more courage than you realise. Keep going.',
    'Your love for your child is the most powerful medicine in the world.',
    'Today, take one small step towards joy. You deserve it, completely.',
  ];

  // ── EPDS QUESTIONS ────────────────────────────────────
  static const List<String> epdsQuestions = [
    'I have been able to laugh and see the funny side of things.',
    'I have looked forward with enjoyment to things.',
    'I have blamed myself unnecessarily when things went wrong.',
    'I have been anxious or worried for no good reason.',
    'I have felt scared or panicky for no very good reason.',
    'Things have been getting on top of me.',
    'I have been so unhappy that I have had difficulty sleeping.',
    'I have felt sad or miserable.',
    'I have been so unhappy that I have been crying.',
    'The thought of harming myself has occurred to me.',
  ];

  // EPDS answer options per question (index maps to score)
  static const List<List<String>> epdsOptions = [
    ['As much as I always could', 'Not quite so much now', 'Definitely not so much now', 'Not at all'],
    ['As much as I ever did', 'Rather less than I used to', 'Definitely less than I used to', 'Hardly at all'],
    ['No, never', 'Not very often', 'Yes, some of the time', 'Yes, most of the time'],
    ['No, not at all', 'Hardly ever', 'Yes, sometimes', 'Yes, very often'],
    ['No, not at all', 'No, not much', 'Yes, sometimes', 'Yes, quite a lot'],
    ['No, I have been coping as well as ever', 'No, most of the time I have coped quite well', 'Yes, sometimes I haven\'t been coping as well as usual', 'Yes, most of the time I haven\'t been able to cope at all'],
    ['No, not at all', 'Not very often', 'Yes, sometimes', 'Yes, most of the time'],
    ['No, not at all', 'Not very often', 'Yes, quite often', 'Yes, most of the time'],
    ['No, never', 'Only occasionally', 'Yes, quite often', 'Yes, most of the time'],
    ['Never', 'Hardly ever', 'Sometimes', 'Yes, quite often'],
  ];

  // EPDS score interpretation
  static String epdsInterpretation(int score) {
    if (score <= 9) return 'Low likelihood of depression. Keep taking care of yourself.';
    if (score <= 12) return 'Some symptoms present. Consider speaking with your doctor.';
    return 'Elevated score. Please reach out to your healthcare provider.';
  }

  // ── BREATHING PHASES ──────────────────────────────────
  static const List<Map<String, dynamic>> breathPhases = [
    {'label': 'Breathe In',  'duration': 4, 'expand': true},
    {'label': 'Hold',        'duration': 4, 'expand': false},
    {'label': 'Breathe Out', 'duration': 4, 'expand': false},
    {'label': 'Rest',        'duration': 2, 'expand': false},
  ];
}
