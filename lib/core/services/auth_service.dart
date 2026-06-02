import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firebase_constants.dart';
import '../models/user_model.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserModel> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final model = await getUserModel(cred.user!.uid);
    return model!;
  }

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String nome,
    required String cognome,
    required UserRole role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = UserModel(
      id: cred.user!.uid,
      email: email.trim(),
      nome: nome,
      cognome: cognome,
      role: role,
      createdAt: DateTime.now(),
    );
    await _db
        .collection(FirebaseConstants.users)
        .doc(user.id)
        .set(user.toFirestore());
    return user;
  }

  Future<void> signOut() => _auth.signOut();

  Future<UserModel?> getUserModel(String uid) async {
    final doc =
        await _db.collection(FirebaseConstants.users).doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }
}
