/// Stili di tile selezionabili per la mappa di navigazione (Step 49).
///
/// Un solo posto dove vivono URL/subdomini/zoom nativo/attribuzione per
/// stile, usato sia dal `TileLayer` (rendering) sia da `OfflineTileService`
/// (download/cache) — evita che i due si disallineino silenziosamente.
enum MapStyle {
  osm(
    id: 'osm',
    label: 'OSM Standard',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    subdomains: [],
    maxNativeZoom: 19,
    attribution: '© OpenStreetMap contributors',
  ),
  // Verificato empiricamente (Step 49, curl su tile reali): z18 e z19
  // restituiscono byte-per-byte lo stesso PNG di un upscale server-side —
  // 17 è il livello nativo massimo. `maxNativeZoom: 17` con `maxZoom: 19`
  // sul TileLayer fa fare a flutter_map lo stesso upscale client-side (una
  // sola richiesta/tile in cache invece di scaricare duplicati identici a
  // z18/z19).
  openTopoMap(
    id: 'opentopomap',
    label: 'OpenTopoMap',
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    maxNativeZoom: 17,
    attribution:
        'Dati mappa: © OpenStreetMap contributors, SRTM  ·  Stile: © OpenTopoMap (CC-BY-SA)',
  );

  final String id;
  final String label;
  final String urlTemplate;
  final List<String> subdomains;
  final int maxNativeZoom;
  final String attribution;

  const MapStyle({
    required this.id,
    required this.label,
    required this.urlTemplate,
    required this.subdomains,
    required this.maxNativeZoom,
    required this.attribution,
  });

  /// Zoom massimo a cui il TileLayer può arrivare (con upscale client-side
  /// oltre [maxNativeZoom]) — fisso a 19 per entrambi gli stili così lo
  /// zoom UI si comporta allo stesso modo indipendentemente dallo stile
  /// attivo.
  static const int maxUiZoom = 19;

  static MapStyle fromId(String? id) =>
      MapStyle.values.firstWhere((s) => s.id == id, orElse: () => MapStyle.osm);
}
