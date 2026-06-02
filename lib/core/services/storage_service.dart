import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

class StorageService {
  final _storage = FirebaseStorage.instance;

  Future<String> uploadTrack(String eventId, Uint8List bytes, String ext) async {
    final ref = _storage.ref('tracks/$eventId/track.$ext');
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<Uint8List> downloadTrack(String url) async {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Download fallito (HTTP ${response.statusCode})');
    }
    return response.bodyBytes;
  }
}
