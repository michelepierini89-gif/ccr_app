import '../models/event_model.dart';

/// Un evento è ancora "praticabile" (il pilota può iniziare/riprendere una
/// sessione GPS, il bottone GPS resta attivo) secondo criteri DIVERSI per
/// tipo — Step 51, bug "evento risulta chiuso al pilota ma aperto
/// all'admin": `GpsRecordingScreen` applicava lo stesso criterio a
/// entrambi, considerando conclusa qualunque `data` passata.
///
/// Per una gara `data` è il giorno di svolgimento: oltre la mezzanotte di
/// quel giorno la gara è conclusa, indipendentemente dallo stato.
/// Per un allenamento `data` è solo il giorno di APERTURA, non di
/// svolgimento: resta praticabile a tempo indeterminato finché l'admin non
/// lo chiude esplicitamente (`EventStatus.archiviata`) — nessun ruolo
/// della data.
bool isEventPracticable(EventModel event) {
  if (event.stato == EventStatus.archiviata) return false;
  if (event.isAllenamento) return true;
  return !event.data.toMidnight().isBefore(DateTime.now());
}
