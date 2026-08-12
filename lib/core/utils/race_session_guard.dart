/// Fix (bug test 18/08, "Carring CLO 3") — funzioni pure, senza dipendenze da
/// Flutter/Firestore, che centralizzano le due protezioni contro una gara
/// conclusa nei primi minuti dall'avvio o per stato locale corrotto:
///
/// 1. [canAutoConcludeRace]: nessuna conclusione — automatica (timeout) o
///    tramite il pulsante FINE GARA (via completamento speciali o "vicino
///    alla partenza") — può avvenire prima di [minRaceProtection] dall'inizio
///    REALE della registrazione (`GpsService.recordingStart`). Protegge dal
///    sintomo: anche con stato residuo che soddisfa le condizioni di
///    completamento, una gara appena iniziata non può chiudersi da sola.
///
/// 2. [isOrphanLocalSession]: `GpsService` è un provider globale mai
///    disposato — se una sessione precedente non è mai stata chiusa con
///    STOP/FINE GARA/RITIRO, il suo stato locale (`_isRecording`,
///    `_specialEntries`, ...) sopravvive alla navigazione. La fonte di
///    verità su "questa gara è in corso" deve essere il documento
///    `tracking/{eventId}/pilots/{userId}` su Firestore, non la variabile in
///    memoria: se quel documento non mostra `raceStatus == 'racing'` per
///    l'evento che si sta aprendo, uno stato locale che dice "in
///    registrazione" è orfano e va scartato.
library;

const Duration minRaceProtection = Duration(minutes: 3);

/// True se è passato abbastanza tempo da [recordingStart] perché una
/// conclusione (automatica o via pulsante) sia legittima.
bool canAutoConcludeRace({
  required DateTime recordingStart,
  required DateTime now,
}) =>
    now.difference(recordingStart) >= minRaceProtection;

/// True se lo stato locale "in registrazione" non trova riscontro nel
/// documento di tracking Firestore per l'evento corrente — cioè è residuo di
/// una sessione precedente mai chiusa correttamente (stesso evento non
/// avviato su Firestore, o evento diverso).
///
/// [firestoreRaceStatus] è il campo `raceStatus` del documento
/// `tracking/{eventId}/pilots/{userId}` per l'evento e l'utente correnti
/// (null se il documento non esiste o non è ancora stato letto).
bool isOrphanLocalSession({
  required bool localIsRecording,
  required String? firestoreRaceStatus,
}) =>
    localIsRecording && firestoreRaceStatus != 'racing';
