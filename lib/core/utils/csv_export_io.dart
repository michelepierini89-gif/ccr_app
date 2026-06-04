import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> downloadCsvFile(String filename, String csvContent) async {
  final dir = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(csvContent);
}
