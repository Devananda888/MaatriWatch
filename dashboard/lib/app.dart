import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:maatriwatch_patient_app/core/app_theme.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';

import 'core/api_client.dart';
import 'core/models.dart';
import 'features/auth/login_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/demo/demo_mode.dart';

class MaatriWatchApp extends StatelessWidget {
  const MaatriWatchApp({super.key, required this.firebaseReady, required this.demoMode, this.initializationError});

  final bool firebaseReady;
  final bool demoMode;
  final String? initializationError;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MaatriWatch Clinician',
        debugShowCheckedModeBanner: false,
        theme: maatriTheme(),
        home: demoMode
            ? const DemoRolePicker()
            : !firebaseReady
            ? _UnavailableHome(message: initializationError)
            : StreamBuilder<User?>(
                stream: FirebaseAuth.instance.authStateChanges(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _LoadingScreen();
                  }
                  if (snapshot.data == null) return const LoginPage(firebaseConfigured: true);
                  return _ClinicianGate(key: ValueKey(snapshot.data!.uid));
                },
              ),
      );
}

class _ClinicianGate extends StatefulWidget {
  const _ClinicianGate({super.key});

  @override
  State<_ClinicianGate> createState() => _ClinicianGateState();
}

class _ClinicianGateState extends State<_ClinicianGate> {
  final _api = ApiClient();
  late Future<List<HospitalMembership>> _membershipRequest;

  @override
  void initState() {
    super.initState();
    _membershipRequest = _loadMemberships();
  }

  Future<List<HospitalMembership>> _loadMemberships() async {
    final response = await _api.me();
    return (response['hospital_memberships'] as List<dynamic>? ?? const [])
        .map((item) => HospitalMembership.fromJson(asMap(item)))
        .where((membership) => membership.role == 'clinician')
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<HospitalMembership>>(
        future: _membershipRequest,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const _LoadingScreen();
          if (snapshot.hasError) {
            return _RetryScreen(
              message: snapshot.error is ApiException
                  ? (snapshot.error as ApiException).message
                  : 'We could not load your hospital access. Check your connection and try again.',
              onRetry: () => setState(() => _membershipRequest = _loadMemberships()),
            );
          }
          if (snapshot.data!.isEmpty) return const _NoClinicianAccess();
          return DashboardPage(
            api: _api,
            memberships: snapshot.data!,
            onSignOut: FirebaseAuth.instance.signOut,
          );
        },
      );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _UnavailableHome extends StatelessWidget {
  const _UnavailableHome({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(MaatriTokens.space24),
                  child: Text(message ?? 'Firebase web configuration is required. See dashboard/README.md.'),
                ),
              ),
            ),
          ),
        ),
      );
}

class _RetryScreen extends StatelessWidget {
  const _RetryScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(MaatriTokens.space24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, color: MaatriTokens.warning, size: 40),
                      const SizedBox(height: MaatriTokens.space16),
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: MaatriTokens.space16),
                      OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _NoClinicianAccess extends StatelessWidget {
  const _NoClinicianAccess();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(MaatriTokens.space24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, color: MaatriTokens.warning, size: 40),
                      const SizedBox(height: MaatriTokens.space16),
                      const Text('Clinician access is not assigned to this account.', textAlign: TextAlign.center),
                      const SizedBox(height: MaatriTokens.space16),
                      OutlinedButton(
                        onPressed: FirebaseAuth.instance.signOut,
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
