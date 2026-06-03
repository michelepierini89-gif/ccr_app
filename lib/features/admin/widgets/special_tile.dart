import 'package:flutter/material.dart';
import '../../../core/models/special_model.dart';
import '../../../core/theme/app_colors.dart';

class SpecialTile extends StatelessWidget {
  final SpecialModel special;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const SpecialTile({
    super.key,
    required this.special,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: special.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: special.color.withValues(alpha: 0.4),
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
        title: Text(
          special.nome,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.flag, color: AppColors.success, size: 14),
                const SizedBox(width: 4),
                Expanded(
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
                Expanded(
                  child: Text(
                    'Fine: ${special.waypointFine.nome}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (special.controlPoints.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.pin_drop,
                      color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${special.controlPoints.length} punt${special.controlPoints.length == 1 ? "o" : "i"} di controllo',
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
