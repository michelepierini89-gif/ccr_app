import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/diagnostic_log_files_service.dart';
import '../../../core/theme/app_colors.dart';

/// Bug segnalato dopo il primo test sul campo di un allenamento (22/08/2026,
/// punto 2): l'export del log tecnico era raggiungibile solo dal riepilogo
/// post-gara, mai esistente in allenamento. Elenca tutti i log tecnici
/// locali (una sessione GPS = un file, gara o tentativo) — reso raggiungibile
/// "in ogni caso dalla pagina dell'evento" (come richiesto), non solo a
/// tentativo appena concluso: un pilota può voler riesportare il log di una
/// sessione di giorni prima.
class DiagnosticLogsScreen extends StatefulWidget {
  const DiagnosticLogsScreen({super.key});

  @override
  State<DiagnosticLogsScreen> createState() => _DiagnosticLogsScreenState();
}

class _DiagnosticLogsScreenState extends State<DiagnosticLogsScreen> {
  List<DiagnosticLogFile>? _files;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await DiagnosticLogFilesService.instance.listAll();
    if (mounted) setState(() => _files = files);
  }

  Future<void> _share(DiagnosticLogFile f) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.file.path)],
      subject: 'CCR — log tecnico',
    ));
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'it');
    final files = _files;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Log tecnici')),
      body: SafeArea(
        bottom: true,
        child: files == null
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent))
            : files.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nessun log tecnico locale. Un log viene creato ad '
                        'ogni sessione GPS (gara o tentativo di allenamento) '
                        'e resta su questo dispositivo.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: files.length,
                    itemBuilder: (ctx, i) {
                      final f = files[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.bug_report_outlined,
                                color: AppColors.accent, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(fmt.format(f.sessionStart),
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(_fmtSize(f.sizeBytes),
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _share(f),
                              icon: const Icon(Icons.ios_share,
                                  color: AppColors.accent, size: 20),
                              tooltip: 'Condividi',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
