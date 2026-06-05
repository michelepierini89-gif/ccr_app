import 'package:firebase_auth/firebase_auth.dart';

class FirebaseErrorHandler {
  static String getMessage(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'wrong-password' ||
        'user-not-found' ||
        'invalid-credential' ||
        'INVALID_LOGIN_CREDENTIALS' =>
          'Email o password non corretti.',
        'email-already-in-use' => 'Email già registrata.',
        'weak-password' => 'Password troppo debole (minimo 6 caratteri).',
        'network-request-failed' => 'Connessione assente, riprova tra poco.',
        'too-many-requests' =>
          'Troppi tentativi di accesso, riprova tra qualche minuto.',
        'user-disabled' => 'Account disabilitato. Contatta l\'organizzatore.',
        'operation-not-allowed' => 'Operazione non permessa.',
        _ => 'Errore di autenticazione: ${e.message ?? e.code}',
      };
    }
    if (e is FirebaseException) {
      return switch (e.code) {
        'permission-denied' => 'Non hai i permessi per questa operazione.',
        'unavailable' => 'Connessione assente, riprova tra poco.',
        'not-found' => 'Dato non trovato.',
        'already-exists' => 'Il dato esiste già.',
        'unauthenticated' => 'Sessione scaduta, effettua di nuovo il login.',
        'deadline-exceeded' => 'Operazione scaduta, riprova.',
        'cancelled' => 'Operazione annullata.',
        'resource-exhausted' =>
          'Troppe richieste al server, riprova tra poco.',
        'aborted' => 'Operazione interrotta, riprova.',
        'data-loss' => 'Errore interno, contatta il supporto.',
        _ => 'Errore Firebase: ${e.message ?? e.code}',
      };
    }
    final msg = e.toString();
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Connessione assente, riprova tra poco.';
    }
    return msg.replaceFirst('Exception: ', '');
  }
}
