# MaatriWatch patient companion

This Android-first Flutter app provides four workspaces: User, Patient, Doctor,
and Admin. It includes wearable readings, SOS support, wellbeing check-ins,
patient review, and hospital operations screens.

Run it from this folder with `flutter pub get` followed by `flutter run`.
The Android scaffold lives in `android/`; generated Android, Flutter, and build
artifacts are ignored by the repository-wide `.gitignore`.

The clinician web role picker reuses the same `PatientHome` widget, keeping the
patient experience consistent across Flutter targets.
