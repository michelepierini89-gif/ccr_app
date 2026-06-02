import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final _storage = FirebaseStorage.instance;

  Future<String> uploadTrack(String eventId, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final ref = _storage.ref('tracks/$eventId/track.$ext');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }
}
