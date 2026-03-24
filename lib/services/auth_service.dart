import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with email and password. Returns the user model or throws.
  Future<UserModel> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _fetchUserModel(cred.user!.uid);
  }

  /// Register a new user and write their record to Firebase.
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    final user = UserModel(
      uid: uid,
      name: name.trim(),
      role: role,
      email: email.trim(),
      phone: phone.trim(),
    );
    await _db.child('users/$uid').set(user.toMap());
    return user;
  }

  /// Fetch UserModel from Realtime DB for the given uid.
  Future<UserModel> _fetchUserModel(String uid) async {
    final snap = await _db.child('users/$uid').get();
    if (!snap.exists) throw Exception('User record not found in database.');
    return UserModel.fromMap(uid, snap.value as Map<dynamic, dynamic>);
  }

  /// Get the current user's profile from DB.
  Future<UserModel?> getCurrentUserModel() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await _fetchUserModel(user.uid);
    } catch (_) {
      return null;
    }
  }

  /// Send a password reset email.
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Sign out.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Check user role; returns 'doctor' or 'patient'.
  Future<String?> getUserRole(String uid) async {
    final snap = await _db.child('users/$uid/role').get();
    return snap.value as String?;
  }

  bool get isSignedIn => _auth.currentUser != null;
}
