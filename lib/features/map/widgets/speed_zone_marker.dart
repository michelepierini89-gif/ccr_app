import 'package:flutter/material.dart';

/// Simbolo "cartello limite di velocità" per le zone a velocità controllata:
/// cerchio bianco con bordo rosso e numero del limite in nero al centro,
/// come un vero cartello stradale — usato in tutte le mappe (editor admin,
/// navigazione pilota, riepilogo gara).
class SpeedZoneMarkerIcon extends StatelessWidget {
  final int speedLimit;
  final double size;

  const SpeedZoneMarkerIcon({
    super.key,
    required this.speedLimit,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.red, width: size * 3 / 40),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Text(
          '$speedLimit',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: speedLimit >= 100 ? size * 11 / 40 : size * 14 / 40,
          ),
        ),
      ),
    );
  }
}
