import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final _storage = FirebaseStorage.instance;

  Future<String> uploadTrack(String eventId, Uint8List bytes, String ext) async {
    final ref = _storage.ref('tracks/$eventId/track.$ext');
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<Uint8List> downloadTrack(String url) async {
    final ref = FirebaseStorage.instance.refFromURL(url);
    final bytes = await ref.getData();
    return bytes!;
  }
}
