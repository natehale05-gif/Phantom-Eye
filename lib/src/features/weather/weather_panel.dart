import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../models/unit_system.dart';
import '../../models/weather.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import 'weather_icons.dart';

/// Full-screen forecast panel opened by tapping the map's weather chip:
/// current-conditions hero, °F/mph ⇄ °C/km/h unit toggle (persisted), 24h
/// hourly strip, 7-day forecast with temp-range bars, and a details grid
/// (humidity, wind+direction, UV, precip chance, sunrise/sunset). Handles
/// loading and error (with Retry) states.
class WeatherPanel extends ConsumerWidget {
  const WeatherPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(weatherSnapshotProvider);
    final units = ref.watch(unitSystemProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: _UnitToggle(units: units, onChanged: (u) => ref.read(unitSystemProvider.notifier).set(u)),
          ),
        ],
      ),
      body: snapshotAsync.when(
        data: (snapshot) {
          if (snapshot == null) {
            return const _WeatherEmptyState(message: 'Pan the map to load weather for that area.');
          }
          return _WeatherContent(snapshot: snapshot, units: units);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _WeatherErrorState(
          onRetry: () => ref.invalidate(weatherSnapshotProvider),
        ),
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.units, required this.onChanged});
  final UnitSystem units;
  final void Function(UnitSystem) onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControlStub(
      isImperial: units.isImperial,
      onChanged: (isImperial) => onChanged(isImperial ? UnitSystem.imperial : UnitSystem.metric),
    );
  }
}

/// A minimal segmented toggle so this file doesn't need to pull in
/// `cupertino.dart` wholesale just for one control.
class CupertinoSlidingSegmentedControlStub extends StatelessWidget {
  const CupertinoSlidingSegmentedControlStub({super.key, required this.isImperial, required this.onChanged});

  final bool isImperial;
  final void Function(bool isImperial) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.glass.raised2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, '°F', isImperial, () => onChanged(true)),
          _segment(context, '°C', !isImperial, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : null, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({required this.snapshot, required this.units});

  final WeatherSnapshot snapshot;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final current = snapshot.current;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // --- Hero ---
        Column(
          children: [
            Icon(weatherIconFor(current.condition, isDay: current.isDay), size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(Formatters.temperature(current.temperatureC, units), style: AppTypography.metric.copyWith(fontSize: 64)),
            Text(current.condition.label, style: AppTypography.title3),
            Text(
              'Feels like ${Formatters.temperature(current.feelsLikeC, units)}',
              style: AppTypography.callout.copyWith(color: context.glass.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),

        // --- 24h hourly strip ---
        Text('Hourly', style: AppTypography.headline),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: snapshot.hourly.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final h = snapshot.hourly[i];
              return SizedBox(
                width: 44,
                child: Column(
                  children: [
                    Text(i == 0 ? 'Now' : DateFormat.j().format(h.time), style: AppTypography.caption1),
                    const SizedBox(height: AppSpacing.sm),
                    Icon(weatherIconFor(h.condition), size: 22),
                    const SizedBox(height: AppSpacing.sm),
                    Text(Formatters.temperature(h.temperatureC, units), style: AppTypography.callout),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: AppSpacing.xxl),

        // --- 7 day forecast ---
        Text('7-Day Forecast', style: AppTypography.headline),
        const SizedBox(height: AppSpacing.sm),
        _WeekForecast(daily: snapshot.daily, units: units),
        const Divider(height: AppSpacing.xxl),

        // --- Details grid ---
        Text('Details', style: AppTypography.headline),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 2.4,
          children: [
            _DetailTile(icon: Icons.water_drop_outlined, label: 'Humidity', value: '${current.humidityPercent}%'),
            _DetailTile(
              icon: Icons.air_rounded,
              label: 'Wind',
              value: '${Formatters.speed(current.windSpeedKmh / 3.6, units)} ${Formatters.compassDirection(current.windDirectionDeg)}',
            ),
            _DetailTile(icon: Icons.wb_sunny_outlined, label: 'UV Index', value: current.uvIndex.toStringAsFixed(0)),
            _DetailTile(icon: Icons.umbrella_outlined, label: 'Precipitation', value: '${current.precipitationChancePercent}%'),
            _DetailTile(icon: Icons.wb_twilight_rounded, label: 'Sunrise', value: DateFormat.jm().format(current.sunrise)),
            _DetailTile(icon: Icons.nights_stay_outlined, label: 'Sunset', value: DateFormat.jm().format(current.sunset)),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

class _WeekForecast extends StatelessWidget {
  const _WeekForecast({required this.daily, required this.units});
  final List<DailyForecast> daily;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const SizedBox.shrink();
    final minOfAll = daily.map((d) => d.lowC).reduce((a, b) => a < b ? a : b);
    final maxOfAll = daily.map((d) => d.highC).reduce((a, b) => a > b ? a : b);
    final range = (maxOfAll - minOfAll).abs() < 1 ? 1.0 : maxOfAll - minOfAll;

    return Column(
      children: [
        for (var i = 0; i < daily.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    i == 0 ? 'Today' : DateFormat.E().format(daily[i].date),
                    style: AppTypography.callout,
                  ),
                ),
                Icon(weatherIconFor(daily[i].condition), size: 18),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 34,
                  child: Text(Formatters.temperature(daily[i].lowC, units), textAlign: TextAlign.right, style: AppTypography.footnote),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _TempRangeBar(
                    low: (daily[i].lowC - minOfAll) / range,
                    high: (daily[i].highC - minOfAll) / range,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 34,
                  child: Text(Formatters.temperature(daily[i].highC, units), style: AppTypography.footnote.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TempRangeBar extends StatelessWidget {
  const _TempRangeBar({required this.low, required this.high});
  final double low;
  final double high;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(color: context.glass.raised2, borderRadius: BorderRadius.circular(2)),
            ),
            Positioned(
              left: width * low.clamp(0, 1),
              width: (width * (high - low)).clamp(6, width),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.elevationLoss, AppColors.elevationGain]),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: context.glass.raised, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          Icon(icon, size: 22, color: context.glass.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: AppTypography.caption1.copyWith(color: context.glass.textTertiary)),
              Text(value, style: AppTypography.headline),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeatherEmptyState extends StatelessWidget {
  const _WeatherEmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_outlined, size: 48, color: context.glass.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _WeatherErrorState extends StatelessWidget {
  const _WeatherErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.danger),
            const SizedBox(height: AppSpacing.md),
            const Text('Could not load weather.', textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
