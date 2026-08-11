import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/cp_dispute_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/providers/admin_provider.dart';

/// Schermata di segnalazione CP mancati (Step 42) — selezione granulare:
/// il pilota sceglie esplicitamente quali CP contestare (nessuna selezione
/// predefinita), con nota opzionale per ciascuno oltre a una nota
/// generale. Sostituisce il vecchio dialog che segnalava in blocco tutti i
/// CP mancati senza possibilità di scelta.
class CpDisputeScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String userId;
  final String pilotName;
  final String teamName;

  /// CP mancati candidati, già arricchiti con [DisputedCp.distanceMeters]
  /// (distanza minima tra la traccia registrata e il punto — calcolata dal
  /// chiamante sulla traccia già caricata per la mappa risultati, così qui
  /// non serve ricaricare nulla).
  final List<DisputedCp> candidates;

  const CpDisputeScreen({
    super.key,
    required this.eventId,
    required this.userId,
    required this.pilotName,
    required this.teamName,
    required this.candidates,
  });

  @override
  ConsumerState<CpDisputeScreen> createState() => _CpDisputeScreenState();
}

class _CpDisputeScreenState extends ConsumerState<CpDisputeScreen> {
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _noteControllers = {};
  final _generalNoteCtrl = TextEditingController();
  bool _sending = false;

  String _key(DisputedCp cp) => '${cp.specialeId}_${cp.cpId}';

  @override
  void dispose() {
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    _generalNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final chosen = widget.candidates
          .where((cp) => _selected.contains(_key(cp)))
          .map((cp) => DisputedCp(
                specialeId: cp.specialeId,
                specialeNome: cp.specialeNome,
                cpId: cp.cpId,
                cpNome: cp.cpNome,
                position: cp.position,
                distanceMeters: cp.distanceMeters,
                pilotNote: _noteControllers[_key(cp)]?.text.trim().isEmpty ??
                        true
                    ? null
                    : _noteControllers[_key(cp)]!.text.trim(),
              ))
          .toList();
      await ref.read(firestoreServiceProvider).createCpDispute(
            eventId: widget.eventId,
            pilotId: widget.userId,
            pilotName: widget.pilotName,
            teamName: widget.teamName,
            missedCps: chosen,
            pilotNote: _generalNoteCtrl.text.trim().isEmpty
                ? null
                : _generalNoteCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore invio segnalazione: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _distanceLabel(double? m) {
    if (m == null) return 'distanza non disponibile';
    if (m < 1000) return 'passato a ${m.round()} m dal punto';
    return 'passato a ${(m / 1000).toStringAsFixed(1)} km dal punto';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Segnala CP mancati')),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: AppColors.cardBackground,
              child: const Text(
                'Seleziona solo i checkpoint che ritieni di aver davvero '
                'passato. La distanza indicata è quella minima a cui la '
                'tua traccia GPS è transitata dal punto: aiuta a capire se '
                'ci sei passato vicino o no.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
                itemCount: widget.candidates.length,
                itemBuilder: (ctx, i) {
                  final cp = widget.candidates[i];
                  final key = _key(cp);
                  final isSelected = _selected.contains(key);
                  _noteControllers.putIfAbsent(
                      key, () => TextEditingController());
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() {
                            if (isSelected) {
                              _selected.remove(key);
                            } else {
                              _selected.add(key);
                            }
                          }),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: isSelected,
                                activeColor: AppColors.accent,
                                onChanged: (_) => setState(() {
                                  if (isSelected) {
                                    _selected.remove(key);
                                  } else {
                                    _selected.add(key);
                                  }
                                }),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${cp.specialeNome} — P${cp.position}'
                                        ' (${cp.cpNome})',
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _distanceLabel(cp.distanceMeters),
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 40, top: 4),
                            child: TextField(
                              controller: _noteControllers[key],
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 12),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'Nota per questo CP (opzionale)',
                                hintStyle:
                                    TextStyle(color: AppColors.textSecondary),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: AppColors.cardBackground,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _generalNoteCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Nota generale per l\'organizzatore (opzionale)',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed:
                          _selected.isEmpty || _sending ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, size: 18),
                      label: Text(_selected.isEmpty
                          ? 'Seleziona almeno un CP'
                          : 'Invia segnalazione (${_selected.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
