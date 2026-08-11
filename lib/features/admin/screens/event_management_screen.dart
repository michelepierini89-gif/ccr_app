import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/route_variant_model.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/firebase_error_handler.dart';
import '../../../core/utils/gpx_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/screens/track_map_screen.dart';
import '../providers/admin_provider.dart';
import '../widgets/special_tile.dart';
import 'registrations_screen.dart';
import 'live_tracking_screen.dart';
import 'specials_editor_screen.dart';
import 'starting_order_screen.dart';
import '../../classifica/screens/classifica_screen.dart';
import '../../timing/screens/timing_screen.dart';

class EventManagementScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventManagementScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventManagementScreen> createState() =>
      _EventManagementScreenState();
}

class _EventManagementScreenState
    extends ConsumerState<EventManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isTrackLoading = false;
  // Percorso alternativo (10/08/2026) — cache per URL invece che per
  // singola variante: le due varianti hanno URL diversi (o B può non
  // averne ancora uno), quindi la cache resta valida indipendentemente da
  // quale sia in editing in un dato momento; String? _loadingUrl evita
  // ricariche concorrenti dello stesso URL.
  final Map<String, ParsedTrack> _trackCache = {};
  String? _loadingUrl;
  // Variante SELEZIONATA nell'editor — distinta da event.activeRouteId
  // (Parte 2: sono due concetti separati, mai confusi in UI). Di default
  // si apre sulla variante attiva, comodità per l'admin.
  String _editingRouteId = 'A';
  bool _editingRouteIdInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Tab _buildLockedTab(String text, bool locked) {
    if (!locked) return Tab(text: text);
    return Tab(
      child: Tooltip(
        message: 'Pubblica l\'evento per attivare questa sezione',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.lock_outline,
                size: 11, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Color _statusColor(EventStatus s) {
    switch (s) {
      case EventStatus.bozza:
        return AppColors.textSecondary;
      case EventStatus.aperto:
        return AppColors.success;
      case EventStatus.inCorso:
        return AppColors.accent;
      case EventStatus.concluso:
        return AppColors.warning;
      case EventStatus.archiviata:
        return AppColors.textSecondary;
    }
  }

  String _statusLabel(EventStatus s) {
    switch (s) {
      case EventStatus.bozza:
        return 'BOZZA';
      case EventStatus.aperto:
        return 'APERTO';
      case EventStatus.inCorso:
        return 'IN CORSO';
      case EventStatus.concluso:
        return 'CONCLUSO';
      case EventStatus.archiviata:
        return 'ARCHIVIATA';
    }
  }

  Future<void> _deleteEvent(BuildContext context, EventModel event) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Elimina evento',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Vuoi eliminare "${event.nome}"? Questa azione non può essere annullata.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continua',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Conferma eliminazione',
            style: TextStyle(color: AppColors.error)),
        content: const Text(
          'Sei sicuro? L\'evento e tutti i suoi dati verranno eliminati definitivamente.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Elimina definitivamente'),
          ),
        ],
      ),
    );
    if (second != true || !context.mounted) return;

    try {
      await ref.read(firestoreServiceProvider).deleteEvent(event.id);
      if (context.mounted) context.go('/admin');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FirebaseErrorHandler.getMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  /// Parte 3 — Duplica evento: copia tracciato, speciali (con checkpoint),
  /// punti pericolo, punto ristoro, zone velocità, dimensione squadra,
  /// tipologia punteggio e tempo massimo gara. NON copia iscrizioni,
  /// ordine di partenza, tracce GPS piloti, tempi o classifiche — sono
  /// tutte legate all'id del vecchio evento, mai toccate perché il nuovo
  /// evento nasce con un id proprio. Il nuovo evento nasce in bozza.
  Future<void> _duplicateEvent(BuildContext context, EventModel event) async {
    var pickedDate = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Duplica evento',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verrà creato "${event.nome} (copia)" in stato bozza, con '
                'tracciato, speciali, checkpoint, punti pericolo, punto '
                'ristoro, zone velocità, dimensione squadra, tipologia '
                'punteggio e tempo massimo gara copiati'
                '${event.routeB != null ? ' (inclusa la variante di percorso B)' : ''}. '
                'Il nuovo evento nasce sempre con il percorso principale (A) '
                'attivo, indipendentemente da quale fosse attivo qui. '
                'Iscrizioni, ordine di partenza, tracce GPS e classifiche '
                'non vengono copiate.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Data nuovo evento: ',
                      style: TextStyle(color: AppColors.textSecondary)),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: pickedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setDialogState(() => pickedDate = picked);
                      }
                    },
                    child: Text(
                        '${pickedDate.day.toString().padLeft(2, '0')}/'
                        '${pickedDate.month.toString().padLeft(2, '0')}/'
                        '${pickedDate.year}'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Duplica'),
            ),
          ],
        );
      }),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final uid = ref.read(authStateProvider).valueOrNull?.uid ?? event.createdBy;
      final svc = ref.read(firestoreServiceProvider);

      final newEvent = EventModel(
        id: '',
        nome: '${event.nome} (copia)',
        luogo: event.luogo,
        data: pickedDate,
        descrizione: event.descrizione,
        labelRouteA: event.labelRouteA,
        specialiRouteA: event.specialiRouteA,
        routeB: event.routeB,
        // Percorso alternativo, Parte 6 — sempre A attiva sul nuovo evento,
        // indipendentemente da quale fosse attiva sull'originale: un
        // evento appena creato in bozza non ha ancora avuto un motivo
        // (maltempo, impraticabilità) per partire su B.
        activeRouteId: 'A',
        stato: EventStatus.bozza,
        createdBy: uid,
        createdAt: DateTime.now(),
        minSquadra: event.minSquadra,
        maxSquadra: event.maxSquadra,
        tipologiaClassifica: event.tipologiaClassifica,
        fuelPointRouteA: event.fuelPointRouteA,
        maxRaceTimeMinutes: event.maxRaceTimeMinutes,
        dangerPointsRouteA: event.dangerPointsRouteA,
        speedZonesRouteA: event.speedZonesRouteA,
      );
      final newId = await svc.createEvent(newEvent);

      // Il tracciato è un file su Storage: si copia il contenuto sotto il
      // nuovo eventId invece di riusare lo stesso URL, così il nuovo
      // evento resta indipendente (regole Storage granulari future,
      // cancellazione dell'originale, ecc.) — per ENTRAMBE le varianti, se
      // presenti.
      String? newUrlA;
      RouteVariantModel? newRouteB = newEvent.routeB;
      if (event.trackUrlRouteA != null) {
        final bytes =
            await StorageService().downloadTrack(event.trackUrlRouteA!);
        final ext = event.trackUrlRouteA!.contains('.kml') ? 'kml' : 'gpx';
        newUrlA = await StorageService().uploadTrack(newId, bytes, ext);
      }
      if (event.routeB?.trackUrl != null) {
        final bytes =
            await StorageService().downloadTrack(event.routeB!.trackUrl!);
        final ext = event.routeB!.trackUrl!.contains('.kml') ? 'kml' : 'gpx';
        final newUrlB = await StorageService().uploadTrack(newId, bytes, ext);
        newRouteB = event.routeB!.copyWith(trackUrl: newUrlB);
      }
      if (newUrlA != null || newRouteB != event.routeB) {
        // `newEvent.copyWith` non permette di cambiare l'id (resta quello
        // vuoto passato a createEvent): si ricostruisce l'entità con l'id
        // reale assegnato da Firestore.
        await svc.updateEvent(EventModel(
          id: newId,
          nome: newEvent.nome,
          luogo: newEvent.luogo,
          data: newEvent.data,
          descrizione: newEvent.descrizione,
          labelRouteA: newEvent.labelRouteA,
          trackUrlRouteA: newUrlA ?? newEvent.trackUrlRouteA,
          specialiRouteA: newEvent.specialiRouteA,
          routeB: newRouteB,
          activeRouteId: newEvent.activeRouteId,
          stato: newEvent.stato,
          createdBy: newEvent.createdBy,
          createdAt: newEvent.createdAt,
          minSquadra: newEvent.minSquadra,
          maxSquadra: newEvent.maxSquadra,
          tipologiaClassifica: newEvent.tipologiaClassifica,
          fuelPointRouteA: newEvent.fuelPointRouteA,
          maxRaceTimeMinutes: newEvent.maxRaceTimeMinutes,
          dangerPointsRouteA: newEvent.dangerPointsRouteA,
          speedZonesRouteA: newEvent.speedZonesRouteA,
        ));
      }

      if (context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('"${newEvent.nome}" creato in bozza'),
          backgroundColor: AppColors.success,
        ));
        context.push('/admin/event/$newId');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(FirebaseErrorHandler.getMessage(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _updateStatus(
      BuildContext context, EventModel event, EventStatus newStatus) async {
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateEvent(event.copyWith(stato: newStatus));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(FirebaseErrorHandler.getMessage(e)),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _autoLoadTrack(String url) async {
    if (_isTrackLoading) return;
    setState(() {
      _isTrackLoading = true;
      _loadingUrl = url;
    });
    try {
      final bytes = await StorageService().downloadTrack(url);
      final content = utf8.decode(bytes);
      final ext = url.contains('track.kml') ? 'kml' : 'gpx';
      final parsed = ext == 'gpx'
          ? GpxParser.parseGpx(content)
          : GpxParser.parseKml(content);
      if (mounted) setState(() => _trackCache[url] = parsed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FirebaseErrorHandler.getMessage(e)),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Riprova',
            textColor: Colors.white,
            onPressed: () => _autoLoadTrack(url),
          ),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTrackLoading = false;
          _loadingUrl = null;
        });
      }
    }
  }

  /// Percorso alternativo — [routeId] decide se il nuovo URL va scritto sui
  /// campi RouteA dell'evento o dentro `event.routeB` (che deve già
  /// esistere: si crea da "Crea percorso alternativo", non da qui).
  Future<void> _pickAndUploadTrack(
      BuildContext context, EventModel event, String routeId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'kml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return;

    setState(() => _isTrackLoading = true);
    try {
      final content = utf8.decode(bytes);
      final ext = (picked.extension ?? 'gpx').toLowerCase();
      final parsed = ext == 'gpx'
          ? GpxParser.parseGpx(content)
          : GpxParser.parseKml(content);

      final url = await StorageService().uploadTrack(event.id, bytes, ext);
      final updated = routeId == 'B'
          ? event.copyWith(routeB: event.routeB!.copyWith(trackUrl: url))
          : event.copyWith(trackUrlRouteA: url);
      await ref.read(firestoreServiceProvider).updateEvent(updated);
      if (mounted) setState(() => _trackCache[url] = parsed);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tracciato caricato con successo!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FirebaseErrorHandler.getMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTrackLoading = false);
    }
  }

  /// Percorso alternativo — crea `event.routeB`, vuoto o come copia della
  /// variante A (Parte 2: "Copia dal percorso A come base"). Il tracciato
  /// (file su Storage) NON viene copiato automaticamente anche scegliendo
  /// "copia da A": è un file grezzo indipendente dal resto e l'admin lo
  /// carica esplicitamente per B, così le due varianti non condividono mai
  /// lo stesso URL (coerente con come "Duplica evento", Parte 6, gestisce
  /// già il tracciato per un nuovo evento).
  Future<void> _createRouteB(BuildContext context, EventModel event,
      {required bool copyFromA}) async {
    final variant = copyFromA
        ? RouteVariantModel(
            id: 'B',
            label: 'Percorso alternativo',
            speciali: event.specialiRouteA,
            dangerPoints: event.dangerPointsRouteA,
            speedZones: event.speedZonesRouteA,
            fuelPoint: event.fuelPointRouteA,
          )
        : const RouteVariantModel(id: 'B', label: 'Percorso alternativo');
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateEvent(event.copyWith(routeB: variant));
      if (mounted) setState(() => _editingRouteId = 'B');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(FirebaseErrorHandler.getMessage(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  /// Percorso alternativo — elimina `event.routeB`. Bloccato se B è
  /// attualmente la variante attiva per la gara: cambiare prima il
  /// percorso attivo (Parte 3, che ha già le proprie salvaguardie) evita di
  /// lasciare l'evento senza un percorso attivo valido.
  Future<void> _deleteRouteB(BuildContext context, EventModel event) async {
    if (event.isRouteBActive) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Il percorso B è attivo per la gara — torna al percorso '
            'principale prima di eliminarlo'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Eliminare il percorso alternativo?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Tracciato, speciali, checkpoint, punti pericolo, zone velocità '
          'e punto ristoro della variante B andranno persi.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continua',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Conferma eliminazione',
            style: TextStyle(color: AppColors.error)),
        content: const Text(
          'Sei sicuro? Il percorso alternativo verrà eliminato '
          'definitivamente.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Elimina definitivamente'),
          ),
        ],
      ),
    );
    if (second != true || !context.mounted) return;

    try {
      await ref
          .read(firestoreServiceProvider)
          .updateEvent(event.copyWith(clearRouteB: true));
      if (mounted) setState(() => _editingRouteId = 'A');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(FirebaseErrorHandler.getMessage(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));

    return eventAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child:
              Text('Errore: $e', style: const TextStyle(color: AppColors.error)),
        ),
      ),
      data: (event) {
        if (event == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(
              child: Text('Evento non trovato',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          );
        }

        // Percorso alternativo — di default l'editor si apre sulla
        // variante attiva (comodità: è quella su cui l'admin lavora più
        // spesso), una volta sola per apertura schermata.
        if (!_editingRouteIdInitialized) {
          _editingRouteIdInitialized = true;
          _editingRouteId = event.activeRouteId;
        }
        final editingUrl = _editingRouteId == 'B'
            ? event.routeB?.trackUrl
            : event.trackUrlRouteA;
        final parsedTrack =
            editingUrl != null ? _trackCache[editingUrl] : null;

        if (editingUrl != null &&
            parsedTrack == null &&
            _loadingUrl != editingUrl &&
            !_isTrackLoading) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _autoLoadTrack(editingUrl));
        }

        final statusColor = _statusColor(event.stato);
        final trackAvailable = parsedTrack != null || editingUrl != null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(event.nome),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Penalità evento',
                onPressed: () =>
                    context.push('/admin/event/${event.id}/penalty-settings'),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Duplica evento',
                onPressed: () => _duplicateEvent(context, event),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                tooltip: 'Elimina evento',
                onPressed: () => _deleteEvent(context, event),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              onTap: (index) {
                if (index > 0 && event.stato == EventStatus.bozza) {
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _tabController.animateTo(0));
                }
              },
              tabs: [
                const Tab(text: 'Tracciato'),
                _buildLockedTab('Iscrizioni', event.stato == EventStatus.bozza),
                _buildLockedTab('Live', event.stato == EventStatus.bozza),
                _buildLockedTab('Classifica', event.stato == EventStatus.bozza),
                _buildLockedTab('Tempi', event.stato == EventStatus.bozza),
              ],
            ),
          ),
          body: SafeArea(bottom: true, child: Column(
            children: [
              Container(
                color: AppColors.cardBackground,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      color: AppColors.textSecondary,
                                      size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat('dd/MM/yyyy')
                                        .format(event.data),
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.location_on,
                                      color: AppColors.textSecondary,
                                      size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      event.luogo,
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (event.stato == EventStatus.archiviata)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.35)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.archive_outlined,
                                    size: 13,
                                    color: AppColors.textSecondary),
                                SizedBox(width: 4),
                                Text(
                                  'ARCHIVIATA',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownButton<EventStatus>(
                            value: event.stato,
                            dropdownColor: AppColors.cardBackground,
                            style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                            underline: const SizedBox(),
                            items: EventStatus.values
                                .where(
                                    (s) => s != EventStatus.archiviata)
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        _statusLabel(s),
                                        style: TextStyle(
                                          color: _statusColor(s),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (s) {
                              if (s != null && s != event.stato) {
                                _updateStatus(context, event, s);
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _TracciatoTab(
                      event: event,
                      parsedTrack: parsedTrack,
                      trackAvailable: trackAvailable,
                      uploadingTrack: _isTrackLoading,
                      editingRouteId: _editingRouteId,
                      onEditingRouteChanged: (id) =>
                          setState(() => _editingRouteId = id),
                      onCreateRouteB: (copyFromA) =>
                          _createRouteB(context, event, copyFromA: copyFromA),
                      onDeleteRouteB: () => _deleteRouteB(context, event),
                      onPickTrack: () =>
                          _pickAndUploadTrack(context, event, _editingRouteId),
                      onManageSpecials: () {
                        if (parsedTrack != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SpecialsEditorScreen(
                                eventId: event.id,
                                parsedTrack: parsedTrack,
                                event: event,
                                routeId: _editingRouteId,
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Carica prima un tracciato GPX/KML'),
                            ),
                          );
                        }
                      },
                    ),
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      StartingOrderScreen(event: event),
                                ),
                              ),
                              icon: const Icon(Icons.flag_circle_outlined,
                                  color: AppColors.accent),
                              label: const Text('Ordine di partenza',
                                  style: TextStyle(color: AppColors.accent)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: AppColors.accent),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: RegistrationsScreen(
                            eventId: event.id,
                            minSquadra: event.minSquadra,
                            maxSquadra: event.maxSquadra,
                          ),
                        ),
                      ],
                    ),
                    LiveTrackingScreen(eventId: event.id),
                    ClassificaScreen(
                        eventId: event.id, showAppBar: false),
                    TimingScreen(
                        eventId: event.id, adminView: true),
                  ],
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}

// ── Tracciato tab ─────────────────────────────────────────────────────────────

class _TracciatoTab extends ConsumerStatefulWidget {
  final EventModel event;
  final ParsedTrack? parsedTrack;
  final bool trackAvailable;
  final bool uploadingTrack;
  final VoidCallback onPickTrack;
  final VoidCallback onManageSpecials;

  /// Percorso alternativo (10/08/2026, Parte 2) — variante 'A'/'B'
  /// SELEZIONATA nell'editor: [parsedTrack]/[trackAvailable] e tutto ciò
  /// che questo tab mostra/modifica si riferiscono SEMPRE a questa
  /// variante, mai a `event.activeRouteId` (mostrato solo come indicatore,
  /// mai come sorgente dei dati in editing).
  final String editingRouteId;
  final ValueChanged<String> onEditingRouteChanged;
  final ValueChanged<bool> onCreateRouteB;
  final VoidCallback onDeleteRouteB;

  const _TracciatoTab({
    required this.event,
    required this.parsedTrack,
    required this.trackAvailable,
    required this.uploadingTrack,
    required this.onPickTrack,
    required this.onManageSpecials,
    required this.editingRouteId,
    required this.onEditingRouteChanged,
    required this.onCreateRouteB,
    required this.onDeleteRouteB,
  });

  @override
  ConsumerState<_TracciatoTab> createState() => _TracciatoTabState();
}

class _TracciatoTabState extends ConsumerState<_TracciatoTab> {
  double? _totalLength;
  int _minSquadra = 1;
  int _maxSquadra = 4;
  TipologiaClassifica _tipologia = TipologiaClassifica.sommaTempi;
  int _maxRaceTimeH = 4;
  int _maxRaceTimeM = 30;
  Timer? _squadraDebounce;
  Timer? _tipologiaDebounce;
  Timer? _maxRaceDebounce;
  Timer? _disposizioniDebounce;
  final _disposizioniController = TextEditingController();

  /// Percorso alternativo — la variante SELEZIONATA nell'editor (mai quella
  /// attiva per la gara, vedi doc su [_TracciatoTab.editingRouteId]). Null
  /// solo se si sta "editando" B ma non è ancora stata creata.
  RouteVariantModel? get _editingVariant =>
      widget.event.routeVariant(widget.editingRouteId);

  @override
  void initState() {
    super.initState();
    _minSquadra = widget.event.minSquadra;
    _maxSquadra = widget.event.maxSquadra;
    _tipologia = widget.event.tipologiaClassifica;
    _maxRaceTimeH = widget.event.maxRaceTimeMinutes ~/ 60;
    _maxRaceTimeM = widget.event.maxRaceTimeMinutes % 60;
    _disposizioniController.text = widget.event.disposizioniParticolari ?? '';
    _totalLength = _computeTotalLength();
  }

  @override
  void didUpdateWidget(_TracciatoTab old) {
    super.didUpdateWidget(old);
    if (old.parsedTrack != widget.parsedTrack) {
      setState(() => _totalLength = _computeTotalLength());
    }
    if (_squadraDebounce == null || !_squadraDebounce!.isActive) {
      if (widget.event.minSquadra != _minSquadra ||
          widget.event.maxSquadra != _maxSquadra) {
        setState(() {
          _minSquadra = widget.event.minSquadra;
          _maxSquadra = widget.event.maxSquadra;
        });
      }
    }
    if (_tipologiaDebounce == null || !_tipologiaDebounce!.isActive) {
      if (widget.event.tipologiaClassifica != _tipologia) {
        setState(() => _tipologia = widget.event.tipologiaClassifica);
      }
    }
    if (_maxRaceDebounce == null || !_maxRaceDebounce!.isActive) {
      final h = widget.event.maxRaceTimeMinutes ~/ 60;
      final m = widget.event.maxRaceTimeMinutes % 60;
      if (h != _maxRaceTimeH || m != _maxRaceTimeM) {
        setState(() {
          _maxRaceTimeH = h;
          _maxRaceTimeM = m;
        });
      }
    }
    if (_disposizioniDebounce == null || !_disposizioniDebounce!.isActive) {
      final incoming = widget.event.disposizioniParticolari ?? '';
      if (incoming != _disposizioniController.text) {
        _disposizioniController.text = incoming;
      }
    }
  }

  @override
  void dispose() {
    _squadraDebounce?.cancel();
    _tipologiaDebounce?.cancel();
    _maxRaceDebounce?.cancel();
    _disposizioniDebounce?.cancel();
    _disposizioniController.dispose();
    super.dispose();
  }

  // ── Percorso alternativo — attivazione (Parte 3) ───────────────────────────

  Future<void> _activateRoute(String targetRouteId) async {
    final event = widget.event;
    final target = event.routeVariant(targetRouteId);
    if (target == null) return;

    // ── Vincolo di sicurezza: nessun cambio a gara iniziata ──
    final hasTracking =
        await ref.read(firestoreServiceProvider).hasAnyTrackingData(event.id);
    if (!mounted) return;
    if (hasTracking) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Cambio percorso bloccato',
              style: TextStyle(color: AppColors.error)),
          content: const Text(
            'Almeno un pilota ha già avviato la registrazione per questo '
            'evento: cambiare percorso ora renderebbe incoerenti i '
            'rilevamenti già effettuati.\n\nSe si tratta di tracce di '
            'test da cancellare, resetta prima i dati gara di questo '
            'evento, poi riprova.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ho capito'),
            ),
          ],
        ),
      );
      return;
    }

    // ── Riepilogo diff + doppia conferma ──
    // La lunghezza è nota solo se il tracciato di questa variante è già
    // stato caricato in questa sessione (cache per URL nello screen
    // padre) — altrimenti si mostra il resto del riepilogo comunque,
    // senza bloccare il flusso per un ricaricamento.
    final lengthLabel = (targetRouteId == widget.editingRouteId &&
            widget.parsedTrack != null)
        ? '${target.totalLengthKm(widget.parsedTrack!.points).toStringAsFixed(1)} km'
        : 'apri "Gestisci Speciali" su questa variante per vederla';

    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text('Attivare "${target.label}"?',
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diventerà il percorso in vigore per la gara al posto di '
              '"${event.activeLabel}".',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _DiffRow('Speciali attive', '${target.specialiAttiveCount}'),
            _DiffRow('Lunghezza', lengthLabel),
            _DiffRow('Punti pericolo', '${target.dangerPoints.length}'),
            _DiffRow('Zone velocità', '${target.speedZones.length}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Conferma cambio percorso',
            style: TextStyle(color: AppColors.warning)),
        content: Text(
          'Tutti i piloti iscritti e approvati riceveranno una notifica. '
          'Confermi di voler attivare "${target.label}"?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Conferma attivazione'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final authUser = ref.read(authStateProvider).valueOrNull;
      final userModel = await ref.read(currentUserModelProvider.future);
      final changedByName = userModel != null
          ? '${userModel.nome} ${userModel.cognome}'.trim()
          : (authUser?.email ?? authUser?.uid ?? 'admin');

      final logEntry = RouteChangeLogEntry(
        changedByUid: authUser?.uid ?? '',
        changedByName:
            changedByName.isEmpty ? (authUser?.uid ?? 'admin') : changedByName,
        timestamp: DateTime.now(),
        fromRouteId: event.activeRouteId,
        toRouteId: targetRouteId,
      );
      final updated = event.copyWith(
        activeRouteId: targetRouteId,
        routeChangeLog: [...event.routeChangeLog, logEntry],
      );
      final svc = ref.read(firestoreServiceProvider);
      await svc.updateEvent(updated);
      await svc.notifyRouteChanged(event.id, target.label);

      messenger.showSnackBar(SnackBar(
        content: Text('"${target.label}" attivato — piloti notificati'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(FirebaseErrorHandler.getMessage(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ── Percorso alternativo — pannello selettore + stato (Parte 2/3) ──────────

  /// Sempre visibile in cima al tab Tracciato: quale variante è in editing
  /// (selettore A/B) e quale è attiva per la gara — i due concetti NON
  /// vanno mai confusi, per questo restano su due righe distinte con
  /// colori diversi invece che un solo indicatore ambiguo.
  Widget _buildRouteVariantPanel(EventModel event) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              const Text('In modifica:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Etichette dei segmenti volutamente corte (solo "A"/"B") per
              // non rischiare overflow su schermi stretti — la label
              // completa della variante selezionata è mostrata accanto, in
              // un Expanded che si comprime con l'ellissi invece di
              // sforare il layout.
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'A', label: Text('A')),
                  ButtonSegment(value: 'B', label: Text('B')),
                ],
                selected: {widget.editingRouteId},
                onSelectionChanged: (s) => widget.onEditingRouteChanged(s.first),
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.editingRouteId == 'B'
                      ? (event.routeB?.label ?? 'non creato')
                      : event.labelRouteA,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.flag_circle_outlined,
                  size: 14,
                  color: event.isRouteBActive
                      ? AppColors.warning
                      : AppColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Attivo per la gara: Percorso ${event.activeRouteId} — '
                  '${event.activeLabel}',
                  style: TextStyle(
                    color: event.isRouteBActive
                        ? AppColors.warning
                        : AppColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (event.lastRouteChangeAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Ultimo cambio: '
              '${event.lastRouteChangeAt!.day.toString().padLeft(2, '0')}/'
              '${event.lastRouteChangeAt!.month.toString().padLeft(2, '0')}/'
              '${event.lastRouteChangeAt!.year} — '
              '${event.routeChangeLog.last.changedByName}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: event.routeB == null
                      ? null
                      : () => _activateRoute(
                          event.isRouteBActive ? 'A' : 'B'),
                  icon: Icon(event.isRouteBActive
                      ? Icons.u_turn_left
                      : Icons.swap_horiz),
                  label: Text(event.isRouteBActive
                      ? 'Torna al percorso principale'
                      : 'Attiva percorso alternativo'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              if (event.routeB != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Elimina percorso alternativo',
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error, size: 20),
                  onPressed: widget.onDeleteRouteB,
                ),
              ],
            ],
          ),
          if (event.routeChangeLog.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _showRouteChangeLog(context, event),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Storico cambi percorso (${event.routeChangeLog.length})',
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      decoration: TextDecoration.underline),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showRouteChangeLog(BuildContext context, EventModel event) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Storico cambi percorso',
            style: TextStyle(color: AppColors.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: event.routeChangeLog.reversed.map((e) {
              final d = e.timestamp;
              final ts = '${d.day.toString().padLeft(2, '0')}/'
                  '${d.month.toString().padLeft(2, '0')}/${d.year} '
                  '${d.hour.toString().padLeft(2, '0')}:'
                  '${d.minute.toString().padLeft(2, '0')}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '$ts — ${e.changedByName}: ${e.fromRouteId} → ${e.toRouteId}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  // ── Geometry helpers ───────────────────────────────────────────────────────

  double _haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final aVal =
        sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
    return R * 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
  }

  double? _computeTotalLength() {
    final pts = widget.parsedTrack?.points;
    if (pts == null || pts.length < 2) return null;
    double total = 0.0;
    for (int i = 1; i < pts.length; i++) {
      total += _haversineMeters(pts[i - 1], pts[i]);
    }
    return total / 1000.0;
  }

  double _sectionLength(int startIdx, int endIdx) {
    final pts = widget.parsedTrack!.points;
    final a = min(startIdx, endIdx);
    final b = max(startIdx, endIdx);
    if (a < 0 || b >= pts.length || a == b) return 0.0;
    double total = 0.0;
    for (int i = a; i < b; i++) {
      total += _haversineMeters(pts[i], pts[i + 1]);
    }
    return total / 1000.0;
  }

  int _ensureTrackIdx(WaypointModel wp) {
    final m = RegExp(r'track_pt_(\d+)$').firstMatch(wp.id);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    final pts = widget.parsedTrack!.points;
    var minDist = double.infinity;
    var minIdx = 0;
    for (var i = 0; i < pts.length; i++) {
      final dlat = wp.lat - pts[i].latitude;
      final dlng = wp.lng - pts[i].longitude;
      final d = dlat * dlat + dlng * dlng;
      if (d < minDist) {
        minDist = d;
        minIdx = i;
      }
    }
    return minIdx;
  }

  // ── Debounced saves ────────────────────────────────────────────────────────

  void _onSquadraChanged() {
    _squadraDebounce?.cancel();
    _squadraDebounce = Timer(const Duration(milliseconds: 800), () {
      ref
          .read(firestoreServiceProvider)
          .updateEvent(widget.event
              .copyWith(minSquadra: _minSquadra, maxSquadra: _maxSquadra))
          .catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(FirebaseErrorHandler.getMessage(e)),
            backgroundColor: AppColors.error,
          ));
        }
      });
    });
  }

  void _onMaxRaceTimeChanged() {
    _maxRaceDebounce?.cancel();
    _maxRaceDebounce = Timer(const Duration(milliseconds: 800), () {
      final totalMinutes = _maxRaceTimeH * 60 + _maxRaceTimeM;
      if (totalMinutes < 30) return;
      ref
          .read(firestoreServiceProvider)
          .updateEvent(widget.event
              .copyWith(maxRaceTimeMinutes: totalMinutes))
          .catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(FirebaseErrorHandler.getMessage(e)),
            backgroundColor: AppColors.error,
          ));
        }
      });
    });
  }

  void _onDisposizioniChanged() {
    _disposizioniDebounce?.cancel();
    _disposizioniDebounce = Timer(const Duration(milliseconds: 800), () {
      final text = _disposizioniController.text.trim();
      ref
          .read(firestoreServiceProvider)
          .updateEvent(widget.event.copyWith(
              disposizioniParticolari: text.isEmpty ? null : text,
              clearDisposizioniParticolari: text.isEmpty))
          .catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(FirebaseErrorHandler.getMessage(e)),
            backgroundColor: AppColors.error,
          ));
        }
      });
    });
  }

  void _onTipologiaChanged(TipologiaClassifica t) {
    setState(() => _tipologia = t);
    _tipologiaDebounce?.cancel();
    _tipologiaDebounce = Timer(const Duration(milliseconds: 800), () {
      ref
          .read(firestoreServiceProvider)
          .updateEvent(
              widget.event.copyWith(tipologiaClassifica: _tipologia))
          .catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(FirebaseErrorHandler.getMessage(e)),
            backgroundColor: AppColors.error,
          ));
        }
      });
    });
  }

  // ── Fuel point ─────────────────────────────────────────────────────────────

  /// Ricostruisce [widget.event] scrivendo su RouteA o su `routeB` a
  /// seconda della variante in editing — stesso principio di
  /// `SpecialsEditorScreen._buildUpdatedEvent`.
  EventModel _withEditingFuelPoint(WaypointModel? fuelPoint,
          {bool clear = false}) =>
      widget.editingRouteId == 'B'
          ? widget.event.copyWith(
              routeB: widget.event.routeB!
                  .copyWith(fuelPoint: fuelPoint, clearFuelPoint: clear))
          : widget.event.copyWith(
              fuelPointRouteA: fuelPoint, clearFuelPointRouteA: clear);

  Future<void> _showFuelPointDialog() async {
    final pts = widget.parsedTrack?.points ?? [];
    final result = await showDialog<LatLng>(
      context: context,
      builder: (_) => _FuelPointDialog(
        trackPoints: pts,
        initial: _editingVariant?.fuelPoint?.latLng,
      ),
    );
    if (result == null || !mounted) return;
    final wp = WaypointModel(
      id: 'fuel_point',
      nome: 'Punto ristoro',
      lat: result.latitude,
      lng: result.longitude,
      type: WaypointType.intermedio,
    );
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateEvent(_withEditingFuelPoint(wp));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore salvataggio: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _removeFuelPoint() async {
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateEvent(_withEditingFuelPoint(null, clear: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FirebaseErrorHandler.getMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  // ── Map widget ─────────────────────────────────────────────────────────────

  Widget _mapWidget() {
    final variant = _editingVariant;
    if (widget.parsedTrack != null && variant != null) {
      return TrackMapScreen(
        trackPoints: widget.parsedTrack!.points,
        specials: variant.speciali,
        waypoints: [
          ...widget.parsedTrack!.waypoints,
          ...variant.speciali.expand((s) => [s.waypointInizio, s.waypointFine]),
        ],
        fuelPoint: variant.fuelPoint,
        dangerPoints: variant.dangerPoints,
        interactive: true,
      );
    }
    return Container(
      color: AppColors.cardBackground,
      child: Center(
        child: widget.uploadingTrack
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.accent),
                  SizedBox(height: 12),
                  Text('Caricamento tracciato...',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              )
            : widget.trackAvailable
                // URL present but parse failed
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 40),
                      const SizedBox(height: 12),
                      const Text('Errore caricamento',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: widget.onPickTrack,
                        child: const Text('Carica manualmente',
                            style: TextStyle(color: AppColors.accent)),
                      ),
                    ],
                  )
                // No track at all
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined,
                          color: AppColors.textSecondary, size: 48),
                      SizedBox(height: 8),
                      Text('Nessun tracciato',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
      ),
    );
  }

  // ── Controls column ────────────────────────────────────────────────────────

  Widget _buildControlsColumn() {
    final parsedTrack = widget.parsedTrack;
    final event = widget.event;
    final variant = _editingVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRouteVariantPanel(event),
        const SizedBox(height: 16),
        if (variant == null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Il percorso alternativo non esiste ancora per questo '
                  'evento.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => widget.onCreateRouteB(false),
                  icon: const Icon(Icons.add_road),
                  label: const Text('Crea percorso alternativo'),
                  style:
                      ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => widget.onCreateRouteB(true),
                  icon: const Icon(Icons.content_copy),
                  label: const Text('Copia dal percorso A come base'),
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
              ],
            ),
          ),
        ] else ...[
        // ── Track actions ──
        ElevatedButton.icon(
          onPressed: parsedTrack != null ? widget.onManageSpecials : null,
          icon: const Icon(Icons.edit_location_alt),
          label: const Text('Gestisci Speciali'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: widget.uploadingTrack ? null : widget.onPickTrack,
          icon: const Icon(Icons.upload_file),
          label: Text(parsedTrack != null
              ? 'Sostituisci tracciato'
              : 'Carica tracciato GPX/KML'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
        ),

        // ── Track stats ──
        if (parsedTrack != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.route,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('${parsedTrack.points.length} punti GPS',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                if (_totalLength != null) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${_totalLength!.toStringAsFixed(1)} km totali',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        // ── Punto ristoro ──
        const SizedBox(height: 16),
        _SectionLabel('Punto ristoro'),
        const SizedBox(height: 8),
        if (variant.fuelPoint != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.local_gas_station,
                    color: Colors.amber.shade600, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${variant.fuelPoint!.lat.toStringAsFixed(5)}, '
                    '${variant.fuelPoint!.lng.toStringAsFixed(5)}',
                    style: TextStyle(
                        color: Colors.amber.shade200, fontSize: 11),
                  ),
                ),
                InkWell(
                  onTap: _showFuelPointDialog,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit,
                        size: 16, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: _removeFuelPoint,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 16, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        OutlinedButton.icon(
          onPressed: _showFuelPointDialog,
          icon: Icon(Icons.local_gas_station,
              color: Colors.amber.shade600, size: 18),
          label: Text(
            variant.fuelPoint != null
                ? 'Modifica punto ristoro'
                : 'Aggiungi punto ristoro',
            style: TextStyle(color: Colors.amber.shade600),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
            minimumSize: const Size(0, 44),
          ),
        ),

        // ── Configurazione evento ──
        const SizedBox(height: 20),
        _SectionLabel('Dimensione squadra'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StepperField(
                label: 'Minimo',
                value: _minSquadra,
                min: 1,
                max: _maxSquadra,
                onChanged: (v) {
                  setState(() => _minSquadra = v);
                  _onSquadraChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StepperField(
                label: 'Massimo',
                value: _maxSquadra,
                min: _minSquadra,
                max: 4,
                onChanged: (v) {
                  setState(() => _maxSquadra = v);
                  _onSquadraChanged();
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _SectionLabel('Tipologia punteggio'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButton<TipologiaClassifica>(
            value: _tipologia,
            isExpanded: true,
            dropdownColor: AppColors.cardBackground,
            underline: const SizedBox(),
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13),
            items: TipologiaClassifica.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.label,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                    ))
                .toList(),
            onChanged: (t) {
              if (t != null) _onTipologiaChanged(t);
            },
          ),
        ),

        // ── Tempo massimo gara ──
        const SizedBox(height: 16),
        _SectionLabel('Tempo massimo gara'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StepperField(
                label: 'Ore',
                value: _maxRaceTimeH,
                min: 0,
                max: 12,
                onChanged: (v) {
                  setState(() => _maxRaceTimeH = v);
                  _onMaxRaceTimeChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StepperField(
                label: 'Min (×5)',
                value: _maxRaceTimeM,
                min: 0,
                max: 55,
                step: 5,
                onChanged: (v) {
                  setState(() => _maxRaceTimeM = v);
                  _onMaxRaceTimeChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_maxRaceTimeH}h ${_maxRaceTimeM.toString().padLeft(2, '0')}min'
          ' — ${_maxRaceTimeH * 60 + _maxRaceTimeM} min totali',
          style: const TextStyle(color: AppColors.accent, fontSize: 11),
        ),

        // ── Disposizioni particolari (Step 42) ──
        const SizedBox(height: 20),
        _SectionLabel('Disposizioni particolari'),
        const SizedBox(height: 4),
        const Text(
          'Ritrovo, orari, pranzo, rinvio maltempo… Comparirà nel '
          'Regolamento lato pilota, prima del regolamento generale. '
          'Lascia vuoto per non mostrare nulla.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _disposizioniController,
          maxLines: 5,
          minLines: 3,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Es. Ritrovo ore 8:00 presso il bar Da Mario…',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.cardBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
          onChanged: (_) => _onDisposizioniChanged(),
        ),

        // ── Specials list ──
        if (variant.speciali.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Speciali',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              if (_totalLength != null) ...[
                const Spacer(),
                Text(
                  '${variant.speciali.length} prove',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...variant.speciali.map((s) {
            double? len;
            var dangerCount = 0;
            if (parsedTrack != null && parsedTrack.points.isNotEmpty) {
              final a = _ensureTrackIdx(s.waypointInizio);
              final b = _ensureTrackIdx(s.waypointFine);
              len = _sectionLength(a, b);
              dangerCount = GpxUtils.countDangerPointsInSpecial(
                  s, variant.dangerPoints, parsedTrack.points);
            }
            return SpecialTile(special: s, lengthKm: len, dangerCount: dangerCount);
          }),
        ],
        ],
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final isWide = constraints.maxWidth >= 600;
      final mapSide = isWide
          ? (constraints.maxWidth * 0.6).clamp(200.0, 700.0)
          : constraints.maxWidth;
      // Map height for mobile: compact when no track, full when available
      final mapH = widget.trackAvailable
          ? (constraints.maxWidth * 0.75).clamp(220.0, 420.0)
          : 160.0;

      if (!isWide) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: mapSide, height: mapH, child: _mapWidget()),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildControlsColumn()),
            ],
          ),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: constraints.maxWidth - mapSide,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildControlsColumn(),
            ),
          ),
          SizedBox(width: mapSide, height: mapSide, child: _mapWidget()),
        ],
      );
    });
  }
}

// ── Fuel point dialog ─────────────────────────────────────────────────────────

class _FuelPointDialog extends StatefulWidget {
  final List<LatLng> trackPoints;
  final LatLng? initial;

  const _FuelPointDialog({required this.trackPoints, this.initial});

  @override
  State<_FuelPointDialog> createState() => _FuelPointDialogState();
}

class _FuelPointDialogState extends State<_FuelPointDialog> {
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  void _onMapTap(LatLng ll) {
    if (widget.trackPoints.isEmpty) {
      setState(() => _picked = ll);
      return;
    }
    final snapped = GpxUtils.snapToTrack(ll, widget.trackPoints);
    final distance = GpxUtils.distanceToTrack(ll, snapped);
    if (distance > AppConstants.trackSnapMaxDistanceMeters) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Il punto deve essere vicino al percorso'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _picked = snapped);
  }

  MapOptions get _mapOptions {
    if (widget.trackPoints.isNotEmpty) {
      return MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(widget.trackPoints),
          padding: const EdgeInsets.all(32),
        ),
        onTap: (_, ll) => _onMapTap(ll),
      );
    }
    return MapOptions(
      initialCenter: const LatLng(44.0, 11.0),
      initialZoom: 13,
      onTap: (_, ll) => _onMapTap(ll),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        height: screenH * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.local_gas_station,
                      color: Colors.amber.shade600, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Punto ristoro',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _picked == null
                    ? 'Clicca sulla mappa per posizionare il punto ristoro'
                    : 'Punto selezionato — clicca di nuovo per spostarlo',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Map
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: FlutterMap(
                  options: _mapOptions,
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ccr.ccr_app',
                    ),
                    if (widget.trackPoints.isNotEmpty)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: widget.trackPoints,
                          color: AppColors.accent,
                          strokeWidth: 3,
                        ),
                      ]),
                    if (_picked != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _picked!,
                          width: 44,
                          height: 52,
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade700,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.amber
                                            .withValues(alpha: 0.6),
                                        blurRadius: 8)
                                  ],
                                ),
                                child: const Icon(Icons.local_gas_station,
                                    color: Colors.white, size: 20),
                              ),
                              const Text('Ristoro',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black54,
                                            blurRadius: 2)
                                      ])),
                            ],
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _picked != null
                          ? () => Navigator.of(context).pop(_picked)
                          : null,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent),
                      child: const Text('Conferma'),
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

// ── Shared widgets ────────────────────────────────────────────────────────────

class _DiffRow extends StatelessWidget {
  final String label;
  final String value;
  const _DiffRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3),
      );
}

class _StepperField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final void Function(int) onChanged;

  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: value > min ? () => onChanged(value - step) : null,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value > min
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.border,
                  ),
                  child: Icon(Icons.remove,
                      size: 16,
                      color: value > min
                          ? AppColors.accent
                          : AppColors.textSecondary),
                ),
              ),
              Text('$value',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              InkWell(
                onTap: value < max ? () => onChanged(value + step) : null,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value < max
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.border,
                  ),
                  child: Icon(Icons.add,
                      size: 16,
                      color: value < max
                          ? AppColors.accent
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
