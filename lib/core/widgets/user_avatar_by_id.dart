import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'ccr_avatar.dart';

/// Avatar per uno userId qualunque (Step 42) — usato in liste che
/// conoscono solo l'id (iscrizioni admin, membri squadra, classifica). Le
/// iniziali di fallback si vedono subito da [fallbackNome]/[fallbackCognome]
/// (già noti dal documento che ha innescato la riga), la foto vera arriva
/// appena [userByIdProvider] risolve — Riverpod cachea per userId, quindi
/// scroll/rebuild della stessa lista non ripete la lettura.
class UserAvatarById extends ConsumerWidget {
  final String userId;
  final String fallbackNome;
  final String fallbackCognome;
  final double size;

  const UserAvatarById({
    super.key,
    required this.userId,
    required this.fallbackNome,
    required this.fallbackCognome,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userByIdProvider(userId));
    final user = userAsync.valueOrNull;
    return CcrAvatar(
      photoUrl: user?.photoUrl,
      nome: user?.nome ?? fallbackNome,
      cognome: user?.cognome ?? fallbackCognome,
      size: size,
    );
  }
}
