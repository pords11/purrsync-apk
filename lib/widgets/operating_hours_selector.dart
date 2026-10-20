import 'package:flutter/material.dart';
import '../utils/time_utils.dart';
import '../models/provider_profile.dart';
import '../utils/app_theme.dart';

class OperatingHoursSelector extends StatelessWidget {
  final String openTime;
  final String closeTime;
  final List<int> openDays;
  final ValueChanged<String> onOpenTimeChanged;
  final ValueChanged<String> onCloseTimeChanged;
  final ValueChanged<List<int>> onOpenDaysChanged;

  const OperatingHoursSelector({
    super.key,
    required this.openTime,
    required this.closeTime,
    required this.openDays,
    required this.onOpenTimeChanged,
    required this.onCloseTimeChanged,
    required this.onOpenDaysChanged,
  });

  Future<void> _pickTime(BuildContext context, bool isOpen) async {
    final currentHm = isOpen ? openTime : closeTime;
    final initial = TimeUtils.parseHm(currentHm);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.dialOnly,
    );

    if (picked != null) {
      final hm = TimeUtils.toHm(picked);
      if (isOpen) {
        onOpenTimeChanged(hm);
      } else {
        onCloseTimeChanged(hm);
      }
    }
  }

  void _toggleDay(int day) {
    final updated = List<int>.from(openDays);
    if (updated.contains(day)) {
      if (updated.length > 1) {
        updated.remove(day);
      }
    } else {
      updated.add(day);
    }
    updated.sort();
    onOpenDaysChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final openVal = TimeUtils.parseHm(openTime);
    final closeVal = TimeUtils.parseHm(closeTime);
    final isInvalidTime = (closeVal.hour * 60 + closeVal.minute) <= (openVal.hour * 60 + openVal.minute);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operating / Available Hours',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _pickTime(context, true),
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Opens (Clock)',
                    prefixIcon: Icon(Icons.access_time, color: AppTheme.primaryTeal),
                  ),
                  child: Text(
                    ProviderProfile.format12Hour(openTime),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => _pickTime(context, false),
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Closes (Clock)',
                    prefixIcon: Icon(Icons.access_time_filled, color: AppTheme.primaryTeal),
                  ),
                  child: Text(
                    ProviderProfile.format12Hour(closeTime),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (isInvalidTime) ...[
          const SizedBox(height: 6),
          const Text(
            'Closing time must be after opening time.',
            style: TextStyle(color: Color(0xFFC62828), fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Days Open:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: List.generate(7, (index) {
            final dayInt = index + 1; // 1=Mon .. 7=Sun
            final dayName = TimeUtils.dayNames[index];
            final isSelected = openDays.contains(dayInt);
            return FilterChip(
              label: Text(
                dayName,
                style: TextStyle(
                  color: isSelected ? AppTheme.primaryTealDark : AppTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
              selected: isSelected,
              selectedColor: AppTheme.primaryTealLight,
              checkmarkColor: AppTheme.primaryTeal,
              backgroundColor: AppTheme.surfaceMuted,
              side: BorderSide(
                color: isSelected ? AppTheme.primaryTeal : AppTheme.borderLight,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onSelected: (_) => _toggleDay(dayInt),
            );
          }),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primaryTealLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppTheme.primaryTeal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ProviderProfile.computeHoursLabel(openDays, openTime, closeTime),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryTealDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
