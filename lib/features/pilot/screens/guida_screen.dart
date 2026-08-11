import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/markdown_sections.dart';
import '../../../core/widgets/markdown_sections_view.dart';

/// Guida all'uso dell'app — contenuto statico incluso come asset,
/// disponibile offline. Stesso trattamento tipografico del Regolamento
/// (sezioni espandibili, prima aperta di default).
class GuidaScreen extends StatefulWidget {
  const GuidaScreen({super.key});

  @override
  State<GuidaScreen> createState() => _GuidaScreenState();
}

class _GuidaScreenState extends State<GuidaScreen> {
  MdDocument? _doc;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw =
          await rootBundle.loadString('assets/docs/guida_app_ccr.md');
      if (mounted) setState(() => _doc = parseMarkdownSections(raw));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Guida all\'uso')),
      body: SafeArea(
        bottom: true,
        child: _error != null
            ? Center(
                child: Text('Impossibile caricare la guida: $_error',
                    style: const TextStyle(color: AppColors.error)),
              )
            : _doc == null
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.accent))
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 16, 16,
                        16 + MediaQuery.paddingOf(context).bottom),
                    child: MarkdownSectionsView(document: _doc!),
                  ),
      ),
    );
  }
}
