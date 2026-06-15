import 'package:flutter/material.dart';

/// Marker pericolo a doppio layer: cerchio giallo con bordo nero e icona
/// di avviso centrata, usato in tutte le mappe (editor, riepiloghi, GPS).
class DangerMarkerIcon extends StatelessWidget {
  final double size;

  const DangerMarkerIcon({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final borderWidth = size <= 20 ? 1.0 : 2.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.amber,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.warning_amber_rounded,
          color: Colors.black,
          size: size * 22 / 36,
        ),
      ),
    );
  }
}
