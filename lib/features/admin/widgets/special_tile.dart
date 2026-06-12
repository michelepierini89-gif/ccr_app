import 'package:flutter/material.dart';
import '../../../core/models/special_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../map/danger_marker_icon.dart';

class SpecialTile extends StatelessWidget {
  final SpecialModel special;
  final double? lengthKm;
  final int dangerCount;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleAnnulla;

  const SpecialTile({
    super.key,
    required this.special,
    this.lengthKm,
    this.dangerCount = 0,
    this.onEdit,
    this.onDelete,
    this.onToggleAnnulla,
  });

  @override
  Widget build(BuildContext context) {
    final annullata = special.annullata;
    final tileColor = annullata ? AppColors.textSecondary : special.color;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: annullata ? AppColors.error : AppColors.border,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tileColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: tileColor.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${special.ordine + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                special.nome,
                style: TextStyle(
                  color: annullata
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  decoration:
                      annullata ? TextDecoration.lineThrough : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (annullata) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ANNULLATA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.flag, color: AppColors.success, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Inizio: ${special.waypointInizio.nome}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.flag, color: AppColors.accent, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Fine: ${special.waypointFine.nome}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (lengthKm != null || special.controlPoints.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    lengthKm != null ? Icons.straighten : Icons.pin_drop,
                    color: AppColors.textSecondary,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      lengthKm != null
                          ? '${lengthKm!.toStringAsFixed(1)} km · ${special.controlPoints.length} punt${special.controlPoints.length == 1 ? "o" : "i"} di controllo'
                          : '${special.controlPoints.length} punt${special.controlPoints.length == 1 ? "o" : "i"} di controllo',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (dangerCount > 0) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const DangerMarkerIcon(size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Pericoli: $dangerCount',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onToggleAnnulla != null)
              IconButton(
                icon: Icon(
                  Icons.block,
                  color: annullata ? AppColors.error : AppColors.warning,
                  size: 20,
                ),
                tooltip: annullata ? 'Riattiva PS' : 'Annulla PS',
                onPressed: onToggleAnnulla,
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit, color: AppColors.textSecondary,
                    size: 20),
                onPressed: onEdit,
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                onPressed: onDelete,
              ),
          ],
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
