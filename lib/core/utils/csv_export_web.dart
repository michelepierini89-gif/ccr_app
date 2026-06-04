// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> downloadCsvFile(String filename, String csvContent) async {
  final bytes = csvContent.codeUnits;
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
