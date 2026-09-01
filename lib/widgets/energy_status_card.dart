import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import 'glass_surface.dart';

class EnergyStatusCard extends StatelessWidget {
  const EnergyStatusCard({
    super.key,
    required this.energy,
    required this.emotion,
  });

  final EnergyStatus? energy;
  final EmotionType? emotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final battery = (energy?.batteryPercent ?? 85).clamp(0, 100);
    final status =
        energy?.status ?? AppStrings.of(context, 'status_flow_value');
    final description =
        energy?.description ?? AppStrings.of(context, 'status_flow_desc');

    return GlassSurface(
      key: const ValueKey('focus-energy-status'),
      level: AppMaterialLevel.surface,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(18),
      tint: AppWindowTones.surface(context, AppWindowTone.focus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  AppStrings.of(context, 'focus_energy_label'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      '$battery',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 34,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '$battery%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            status,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: battery / 100,
              minHeight: 7,
              backgroundColor: theme.colorScheme.tertiary.withValues(
                alpha: 0.16,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.tertiary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          if (emotion != null) ...[
            const SizedBox(height: 7),
            Text(
              AppStrings.of(
                context,
                'focus_emotion_label',
                params: {'emotion': emotion!.label},
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                color: emotion!.color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
