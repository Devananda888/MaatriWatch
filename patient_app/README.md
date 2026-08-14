# MaatriWatch patient companion

This Android-first Flutter app contains the existing prototype patient flow:
simple icon-led vitals, a local SOS confirmation, and a three-question
wellbeing check-in. It intentionally has no live backend, Twilio, or Bhashini
connection in this submission.

Run it from this folder with `flutter pub get` followed by `flutter run`.
The Android scaffold lives in `android/`; generated Android, Flutter, and build
artifacts are ignored by the repository-wide `.gitignore`.

The clinician web role picker reuses this exact `DemoPatientHome` widget during
demo mode, keeping the mock patient experience in one source location.
