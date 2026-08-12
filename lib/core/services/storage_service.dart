import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final _storage = FirebaseStorage.instance;

  /// Fix (bug test 18/08, "Carring CLO 3") — [routeId] ('A' o 'B') decide il
  /// path di Storage. PRIMA di questo fix il path era sempre
  /// `tracks/$eventId/track.$ext`, identico per entrambe le varianti:
  /// caricare un tracciato per B sovrascriveva silenziosamente il file di
  /// A (confermato sui dati reali dell'evento: `trackUrl` e
  /// `routeB.trackUrl` puntavano allo stesso file, solo con token di
  /// download diversi). La variante A mantiene il path invariato
  /// (`track.$ext`, nessuna migrazione per gli eventi esistenti); B ottiene
  /// un file separato (`track_B.$ext`).
  Future<String> uploadTrack(String eventId, Uint8List bytes, String ext,
      {String routeId = 'A'}) async {
    final fileName = routeId == 'B' ? 'track_B.$ext' : 'track.$ext';
    final ref = _storage.ref('tracks/$eventId/$fileName');
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<Uint8List> downloadTrack(String url) async {
    final ref = FirebaseStorage.instance.refFromURL(url);
    final bytes = await ref.getData();
    return bytes!;
  }
}
