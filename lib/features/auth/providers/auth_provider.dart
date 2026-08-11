import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserModelProvider = FutureProvider<UserModel?>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState == null) return null;
  return ref.watch(authServiceProvider).getUserModel(authState.uid);
});

/// Profilo di un utente qualunque per id — usato per mostrare l'avatar
/// (Step 42) in liste che conoscono solo lo userId (iscrizioni, membri
/// squadra, classifica): il cognome/nome nel documento registrazione/team
/// è uno snapshot al momento dell'iscrizione, la foto profilo invece deve
/// riflettere quella attuale, quindi va letta dal profilo live.
final userByIdProvider =
    FutureProvider.family<UserModel?, String>((ref, uid) {
  return ref.watch(authServiceProvider).getUserModel(uid);
});
