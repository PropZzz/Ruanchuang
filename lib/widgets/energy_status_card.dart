import 'package:flutter/material.dart';

import '../models/models.dart';
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
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.battery_charging_full_rounded,
                color: theme.colorScheme.tertiary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${AppStrings.of(context, 'focus_status_label')}$status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                '$battery%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: battery / 100,
              minHeight: 7,
              backgroundColor: theme.colorScheme.tertiary.withValues(
                alpha: 0.18,
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
            const SizedBox(height: 8),
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
