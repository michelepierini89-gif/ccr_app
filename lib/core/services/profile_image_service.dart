import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Selezione, ritaglio quadrato, ridimensionamento e upload dell'immagine
/// profilo (Step 42). Percorso per-utente in Storage, un file per upload
/// (timestamp nel nome) così l'URL cambia sempre — niente immagine vecchia
/// mostrata dalla cache dopo un aggiornamento — con cancellazione esplicita
/// del file precedente dopo l'upload del nuovo.
class ProfileImageService {
  static const int maxDimension = 512;

  final ImagePicker _picker = ImagePicker();

  /// Apre il picker (galleria o fotocamera), ritaglia al centro in
  /// quadrato e ridimensiona a [maxDimension]px prima di restituire i byte
  /// JPEG pronti per l'upload. Ritorna null se l'utente annulla la scelta.
  Future<Uint8List?> pickAndProcess(ImageSource source) async {
    final xfile = await _picker.pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
    );
    if (xfile == null) return null;
    final bytes = await xfile.readAsBytes();
    return _cropSquareAndResize(bytes);
  }

  Uint8List _cropSquareAndResize(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Formato immagine non riconosciuto');
    }
    final side =
        decoded.width < decoded.height ? decoded.width : decoded.height;
    final x = (decoded.width - side) ~/ 2;
    final y = (decoded.height - side) ~/ 2;
    final cropped =
        img.copyCrop(decoded, x: x, y: y, width: side, height: side);
    final resized = side > maxDimension
        ? img.copyResize(cropped, width: maxDimension, height: maxDimension)
        : cropped;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  Future<String> upload(String userId, Uint8List bytes) async {
    final path =
        'profile_images/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Best-effort: se il file precedente non esiste più o l'URL non è più
  /// valido, l'errore viene ignorato — non deve bloccare il flusso di
  /// upload della nuova immagine.
  Future<void> deleteIfExists(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
  }
}
