/// Fix 2 (09/08/2026) — unica funzione da usare per formattare un tempo di
/// gara ovunque compaia (classifica, tempi pilota/admin, riepilogo
/// post-gara, export CSV): prima di questo fix ogni schermata aveva la sua
/// copia locale di `m.toString().padLeft(2,'0')` con `m = tempo.inMinutes`,
/// che per tempi totali oltre l'ora produceva minuti cumulati illeggibili
/// (es. "268:37.29" invece di "4:28:37.29"). Non duplicare questa logica
/// localmente: importare e usare [TimeFormatUtils.formatRaceTime].
class TimeFormatUtils {
  TimeFormatUtils._();

  /// Formatta [d] come `mm:ss.dd` sotto l'ora, `h:mm:ss.dd` da un'ora in
  /// su (ore senza zero iniziale, minuti/secondi/decimi sempre a 2 cifre).
  static String formatRaceTime(Duration d) {
    final sign = d.isNegative ? '-' : '';
    final totalMs = d.inMilliseconds.abs();
    final hours = totalMs ~/ 3600000;
    final minutes = (totalMs % 3600000) ~/ 60000;
    final seconds = (totalMs % 60000) ~/ 1000;
    final centis = (totalMs % 1000) ~/ 10;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    final cc = centis.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$sign$hours:$mm:$ss.$cc';
    }
    return '$sign$minutes:$ss.$cc';
  }
}
