import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _tzInitialized = false;

void ensureTimeZonesInitialized() {
  if (_tzInitialized) {
    return;
  }
  tzdata.initializeTimeZones();
  _tzInitialized = true;
}

Future<String> getDefaultTimeZone() async {
  ensureTimeZonesInitialized();
  final TimezoneInfo deviceInfo = await FlutterTimezone.getLocalTimezone();
  final deviceName = deviceInfo.identifier;
  final resolved = resolveTimeZoneName(deviceName);
  if (resolved != null &&
      resolved.isNotEmpty &&
      resolved.toUpperCase() != 'UTC') {
    return mapToValidTimeZone(resolved);
  }
  final tzName = tz.local.name;
  final fallback =
      resolveTimeZoneName(tzName) ?? _resolveDeviceTimeZone() ?? tzName;
  return mapToValidTimeZone(fallback);
}

String? resolveTimeZoneName(String name) {
  if (name.isEmpty) {
    return null;
  }
  if (tz.timeZoneDatabase.locations.containsKey(name)) {
    return name;
  }
  final lower = name.toLowerCase();
  final directMatch = tz.timeZoneDatabase.locations.keys.firstWhere(
    (zone) => zone.toLowerCase() == lower,
    orElse: () => '',
  );
  if (directMatch.isNotEmpty) {
    return directMatch;
  }
  final suffixMatch = tz.timeZoneDatabase.locations.keys.firstWhere(
    (zone) => zone.toLowerCase().endsWith('/$lower'),
    orElse: () => '',
  );
  if (suffixMatch.isNotEmpty) {
    return suffixMatch;
  }
  return _matchByAbbreviation(name);
}

String? _resolveDeviceTimeZone() {
  final deviceName = DateTime.now().timeZoneName;
  final locations = tz.timeZoneDatabase.locations.keys;
  if (deviceName.isEmpty) {
    return null;
  }
  if (deviceName.contains('/')) {
    final directMatch = locations.firstWhere(
      (zone) => zone.toLowerCase() == deviceName.toLowerCase(),
      orElse: () => '',
    );
    if (directMatch.isNotEmpty) {
      return directMatch;
    }
  }
  final suffixMatch = locations.firstWhere(
    (zone) => zone.toLowerCase().endsWith('/${deviceName.toLowerCase()}'),
    orElse: () => '',
  );
  if (suffixMatch.isNotEmpty) {
    return suffixMatch;
  }
  return _matchByAbbreviation(deviceName);
}

String? _matchByAbbreviation(String abbreviation) {
  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  final matches = <String>[];
  for (final entry in tz.timeZoneDatabase.locations.entries) {
    try {
      final zoneNow = tz.TZDateTime.now(entry.value);
      if (zoneNow.timeZoneOffset == offset &&
          zoneNow.timeZoneName.toUpperCase() == abbreviation.toUpperCase()) {
        matches.add(entry.key);
      }
    } catch (_) {
      // Skip invalid timezone entries
      continue;
    }
  }
  return matches.isNotEmpty ? matches.first : null;
}

/// Validates if a timezone identifier is valid and can be used.
/// Returns true if the timezone is valid, false otherwise.
bool _isValidTimeZone(String timeZone) {
  if (timeZone.isEmpty) return false;

  try {
    // Try to get the location - if it throws, the timezone is invalid
    final location = tz.getLocation(timeZone);
    // Try to create a TZDateTime to ensure it's actually usable
    tz.TZDateTime.now(location);
    return true;
  } catch (_) {
    return false;
  }
}

/// Filters out invalid or deprecated timezones from a list.
List<String> _filterValidTimeZones(List<String> timeZones) {
  return timeZones.where(_isValidTimeZone).toList();
}

/// Maps a device timezone to a valid timezone from the whitelist.
/// If the timezone is already valid, returns it. Otherwise, finds the best
/// matching valid timezone based on UTC offset and DST behavior.
String mapToValidTimeZone(String deviceTimeZone) {
  if (deviceTimeZone.isEmpty) {
    return 'UTC';
  }

  // First, try to resolve the timezone name
  final resolved = resolveTimeZoneName(deviceTimeZone);
  if (resolved == null || resolved.isEmpty) {
    return _findBestMatchByOffset(deviceTimeZone) ?? 'UTC';
  }

  // Check if the resolved timezone is already in our valid list
  if (validTimeZones.contains(resolved) && _isValidTimeZone(resolved)) {
    return resolved;
  }

  // Try to find a match from the valid timezones list
  return _findBestMatchFromValidList(resolved) ?? 'UTC';
}

/// Finds the best matching valid timezone based on UTC offset and DST behavior.
String? _findBestMatchFromValidList(String targetTimeZone) {
  try {
    final targetLocation = tz.getLocation(targetTimeZone);
    final now = DateTime.now();
    final targetNow = tz.TZDateTime.from(now, targetLocation);
    final targetOffset = targetNow.timeZoneOffset;

    // Check multiple time points to verify DST behavior
    final summerDate = DateTime(now.year, 7, 15); // Mid-summer
    final winterDate = DateTime(now.year, 1, 15); // Mid-winter
    final targetSummer = tz.TZDateTime.from(summerDate, targetLocation);
    final targetWinter = tz.TZDateTime.from(winterDate, targetLocation);
    final targetSummerOffset = targetSummer.timeZoneOffset;
    final targetWinterOffset = targetWinter.timeZoneOffset;

    String? bestMatch;
    int bestScore = -1;

    // Try to match by region prefix first (e.g., America/ -> America/)
    final targetPrefix = targetTimeZone.split('/').first;
    final sameRegionMatches = <String>[];

    for (final validTz in validTimeZones) {
      if (!_isValidTimeZone(validTz)) continue;

      try {
        final validLocation = tz.getLocation(validTz);
        final validNow = tz.TZDateTime.from(now, validLocation);
        final validOffset = validNow.timeZoneOffset;

        // Must match current offset
        if (validOffset != targetOffset) continue;

        // Check DST behavior
        final validSummer = tz.TZDateTime.from(summerDate, validLocation);
        final validWinter = tz.TZDateTime.from(winterDate, validLocation);
        final validSummerOffset = validSummer.timeZoneOffset;
        final validWinterOffset = validWinter.timeZoneOffset;

        int score = 0;

        // Perfect match: same offsets at all times
        if (validSummerOffset == targetSummerOffset &&
            validWinterOffset == targetWinterOffset) {
          score = 100;

          // Bonus for same region
          if (validTz.startsWith('$targetPrefix/')) {
            score += 50;
            sameRegionMatches.add(validTz);
          }

          if (score > bestScore) {
            bestScore = score;
            bestMatch = validTz;
          }
        }
      } catch (_) {
        continue;
      }
    }

    // Prefer same region matches
    if (sameRegionMatches.isNotEmpty) {
      return sameRegionMatches.first;
    }

    return bestMatch;
  } catch (_) {
    return null;
  }
}

/// Finds a valid timezone match based on current UTC offset when the
/// timezone cannot be resolved.
String? _findBestMatchByOffset(String deviceTimeZone) {
  try {
    final now = DateTime.now();
    final deviceOffset = now.timeZoneOffset;

    // Find any valid timezone with matching offset
    for (final validTz in validTimeZones) {
      if (!_isValidTimeZone(validTz)) continue;

      try {
        final location = tz.getLocation(validTz);
        final tzNow = tz.TZDateTime.from(now, location);
        if (tzNow.timeZoneOffset == deviceOffset) {
          return validTz;
        }
      } catch (_) {
        continue;
      }
    }
  } catch (_) {
    // Fall through
  }
  return null;
}

Future<void> showScheduleTimeZoneSheet(
  BuildContext context, {
  required String selectedTimeZone,
  required ValueChanged<String> onSelect,
  String? deviceTimeZone,
}) {
  ensureTimeZonesInitialized();
  // Map selected timezone to valid one
  final resolvedSelectedTimeZone = mapToValidTimeZone(selectedTimeZone);

  // Map device timezone to valid one
  final deviceTz = deviceTimeZone?.isNotEmpty == true
      ? deviceTimeZone!
      : tz.local.name;
  final resolvedDeviceTimeZone = mapToValidTimeZone(deviceTz);

  // Use whitelist of valid timezones and filter to ensure they're still valid
  final allTimeZones = _filterValidTimeZones(validTimeZones)..sort();

  // Ensure device and selected timezones are in the list (they should be, but be safe)
  final allTimeZonesSet = allTimeZones.toSet()
    ..add(resolvedDeviceTimeZone)
    ..add(resolvedSelectedTimeZone);
  final allTimeZonesWithDevice = allTimeZonesSet.toList()..sort();

  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: context.height * 0.8),
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _ScheduleTimeZoneSheet(
      deviceTimeZone: resolvedDeviceTimeZone,
      selectedTimeZone: resolvedSelectedTimeZone,
      allTimeZones: allTimeZonesWithDevice,
      onSelect: onSelect,
    ),
  );
}

class _ScheduleTimeZoneSheet extends StatefulWidget {
  const _ScheduleTimeZoneSheet({
    required this.deviceTimeZone,
    required this.selectedTimeZone,
    required this.allTimeZones,
    required this.onSelect,
  });

  final String deviceTimeZone;
  final String selectedTimeZone;
  final List<String> allTimeZones;
  final ValueChanged<String> onSelect;

  @override
  State<_ScheduleTimeZoneSheet> createState() => _ScheduleTimeZoneSheetState();
}

class _ScheduleTimeZoneSheetState extends State<_ScheduleTimeZoneSheet> {
  late final TextEditingController _searchCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? List<String>.from(widget.allTimeZones)
        : widget.allTimeZones
              .where((zone) => zone.toLowerCase().contains(normalizedQuery))
              .toList();
    filtered
      ..remove(widget.deviceTimeZone)
      ..remove(widget.selectedTimeZone);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.backgroundNorm,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: context.local.schedule_time_zone_search_hint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                  ),
                ),
                _buildSectionLabel(
                  context,
                  context.local.schedule_time_zone_current,
                ),
                _buildTimeZoneTile(
                  context,
                  zone: widget.deviceTimeZone,
                  isSelected: widget.deviceTimeZone == widget.selectedTimeZone,
                ),
                if (widget.selectedTimeZone != widget.deviceTimeZone) ...[
                  const SizedBox(height: 8),
                  _buildSectionLabel(
                    context,
                    context.local.schedule_time_zone_selected,
                  ),
                  _buildTimeZoneTile(
                    context,
                    zone: widget.selectedTimeZone,
                    isSelected: true,
                  ),
                ],
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final zone = filtered[index];
                      return _buildTimeZoneTile(
                        context,
                        zone: zone,
                        isSelected: zone == widget.selectedTimeZone,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: ProtonStyles.body2Medium(color: context.colors.textWeak),
        ),
      ),
    );
  }

  Widget _buildTimeZoneTile(
    BuildContext context, {
    required String zone,
    required bool isSelected,
  }) {
    return ListTile(
      title: Text(
        zone,
        style: ProtonStyles.body2Regular(color: context.colors.textNorm),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: context.colors.protonBlue)
          : null,
      onTap: () {
        widget.onSelect(zone);
        Navigator.pop(context);
      },
    );
  }
}
