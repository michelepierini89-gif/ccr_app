import 'dart:math';

/// Fix 6 (09/08/2026) — calcolo puro delle due rotazioni in gioco quando si
/// naviga con la mappa in modalità rotante (HEADING): l'angolo esplicito
/// della freccia (per `Transform.rotate`, radianti) e la rotazione da
/// applicare alla mappa (gradi, per `MapController.rotate`). Estratte a
/// funzioni pure indipendenti dal widget tree per poterle testare in
/// isolamento (vedi `test/core/utils/heading_display_utils_test.dart`) senza
/// montare l'intero `GpsRecordingScreen` — il test fallisce se in futuro
/// viene reintrodotta una doppia rotazione (freccia E mappa che ruotano
/// entrambe in base allo stesso heading).
class HeadingDisplayUtils {
  HeadingDisplayUtils._();

  /// Angolo (radianti) da passare a `Transform.rotate` per l'icona della
  /// freccia. In modalità HEADING deve essere SEMPRE zero: la freccia resta
  /// visivamente fissa verso l'alto, la rotazione la fa la mappa (vedi
  /// [mapRotationDeg]). Il `Marker` di flutter_map viene creato con
  /// `rotate: headingMode`, che cancella GIÀ la rotazione della mappa per
  /// questo marker (vedi flutter_map `Marker.rotate`) — un valore diverso
  /// da zero qui, sommato a quella cancellazione, produrrebbe una doppia
  /// rotazione variabile.
  static double arrowAngleRad(bool headingMode, double displayHeadingDeg) =>
      headingMode ? 0.0 : displayHeadingDeg * pi / 180;

  /// Rotazione (gradi, per `MapController.rotate`) da applicare alla mappa.
  /// In modalità NORD la mappa non ruota mai (0°, fisso); in modalità
  /// HEADING ruota dell'OPPOSTO dell'heading di display, così la direzione
  /// di marcia punta sempre verso l'alto sullo schermo.
  static double mapRotationDeg(bool headingMode, double displayHeadingDeg) =>
      headingMode ? -displayHeadingDeg : 0.0;
}
