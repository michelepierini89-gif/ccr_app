import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Avatar circolare condiviso: immagine profilo con cache se [photoUrl] è
/// presente, iniziali del nome come fallback altrimenti — usato in
/// profilo, elenco iscrizioni admin, membri squadra e classifica (Step 42).
/// La cache evita di rallentare le liste: ogni avatar scarica una volta
/// sola, i re-render successivi (scroll, rebuild) sono istantanei.
class CcrAvatar extends StatelessWidget {
  final String? photoUrl;
  final String nome;
  final String cognome;
  final double size;

  const CcrAvatar({
    super.key,
    required this.photoUrl,
    required this.nome,
    required this.cognome,
    this.size = 40,
  });

  String get _initials =>
      '${nome.isNotEmpty ? nome[0] : ''}${cognome.isNotEmpty ? cognome[0] : ''}'
          .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) {
      return _InitialsCircle(initials: _initials, size: size);
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, _) =>
            _InitialsCircle(initials: _initials, size: size),
        errorWidget: (context, _, _) =>
            _InitialsCircle(initials: _initials, size: size),
        fadeInDuration: const Duration(milliseconds: 150),
        memCacheWidth: (size * 2).round(),
      ),
    );
  }
}

class _InitialsCircle extends StatelessWidget {
  final String initials;
  final double size;
  const _InitialsCircle({required this.initials, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
