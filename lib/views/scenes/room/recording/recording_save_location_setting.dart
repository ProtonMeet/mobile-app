import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/scenes/room/recording/recording_save_location.dart';
import 'package:meet/views/scenes/room/side_panel_widget.dart';

String recordingSaveLocationLabelForKind(
  BuildContext context,
  RecordingSaveLocationKind kind,
) {
  switch (kind) {
    case RecordingSaveLocationKind.appDocuments:
      return context.local.recording_save_location_app_documents;
    case RecordingSaveLocationKind.downloads:
      return context.local.recording_save_location_downloads;
    case RecordingSaveLocationKind.movies:
      return context.local.recording_save_location_movies;
    case RecordingSaveLocationKind.custom:
      return context.local.recording_save_location_custom;
  }
}

/// Opens the save-location picker and persists the selection.
class RecordingSaveLocationPicker {
  RecordingSaveLocationPicker._();

  static Future<void> show(BuildContext context) async {
    final current = await RecordingSaveLocationConfig.load();
    final options = RecordingSaveLocationConfig.availableKinds();
    if (options.length <= 1) return;

    if (!context.mounted) return;

    final selected = await showModalBottomSheet<RecordingSaveLocationKind>(
      context: context,
      backgroundColor: context.colors.backgroundNorm,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RoomSidePanelLayout.borderRadiusMedium),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.local.recording_save_location,
                  style: ProtonStyles.headline(
                    fontSize: 18,
                    color: context.colors.textNorm,
                  ),
                ),
                const SizedBox(height: 8),
                ...options.map((kind) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _LocationChoice(
                      title: recordingSaveLocationLabelForKind(context, kind),
                      selected: current.kind == kind,
                      onTap: () => Navigator.of(sheetContext).pop(kind),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || selected == null) return;

    if (selected == RecordingSaveLocationKind.custom) {
      final path = await RecordingSaveLocationConfig.pickCustomDirectory();
      if (path == null || path.isEmpty) return;
      if (!context.mounted) return;
      await _applyCustomPath(context, path);
      return;
    }

    final next = RecordingSaveLocationConfig(kind: selected);
    await next.save();
    if (context.mounted) {
      LocalToast.showToast(
        context,
        context.local.recording_save_location_updated,
      );
    }
  }

  static Future<void> _applyCustomPath(
    BuildContext context,
    String path,
  ) async {
    final next = RecordingSaveLocationConfig(
      kind: RecordingSaveLocationKind.custom,
      customPath: path,
    );
    try {
      await next.resolveVideoDirectory();
      await next.save();
      if (context.mounted) {
        LocalToast.showToast(
          context,
          context.local.recording_save_location_updated,
        );
      }
    } catch (e) {
      if (context.mounted) {
        LocalToast.showToastification(
          context,
          context.local.error,
          context.local.recording_save_location_unavailable,
        );
      }
    }
  }
}

/// App settings card: choose where local recordings are saved.
class RecordingSaveLocationAppSettingsCard extends StatefulWidget {
  const RecordingSaveLocationAppSettingsCard({super.key});

  @override
  State<RecordingSaveLocationAppSettingsCard> createState() =>
      _RecordingSaveLocationAppSettingsCardState();
}

class _RecordingSaveLocationAppSettingsCardState
    extends State<RecordingSaveLocationAppSettingsCard> {
  RecordingSaveLocationConfig? _config;
  String _pathSummary = '';

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final config = await RecordingSaveLocationConfig.load();
    final path = await config.displayPath();
    if (!mounted) return;
    setState(() {
      _config = config;
      _pathSummary = path;
    });
  }

  Future<void> _openPicker() async {
    await RecordingSaveLocationPicker.show(context);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(24));
    final config = _config;
    final kindLabel = config == null
        ? ''
        : recordingSaveLocationLabelForKind(context, config.kind);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openPicker,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.local.recording_save_location,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textWeak,
                        ),
                      ),
                      if (kindLabel.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          kindLabel,
                          style: ProtonStyles.body1Medium(
                            color: context.colors.textNorm,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (_pathSummary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _pathSummary,
                          style: ProtonStyles.body2Regular(
                            color: context.colors.textWeak,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: context.colors.textWeak,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// In-room setting row: choose where local recordings are saved.
class RecordingSaveLocationSettingRow extends StatefulWidget {
  const RecordingSaveLocationSettingRow({super.key});

  @override
  State<RecordingSaveLocationSettingRow> createState() =>
      _RecordingSaveLocationSettingRowState();
}

class _RecordingSaveLocationSettingRowState
    extends State<RecordingSaveLocationSettingRow> {
  RecordingSaveLocationConfig? _config;
  String _pathSummary = '';

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final config = await RecordingSaveLocationConfig.load();
    final path = await config.displayPath();
    if (!mounted) return;
    setState(() {
      _config = config;
      _pathSummary = path;
    });
  }

  Future<void> _openPicker() async {
    await RecordingSaveLocationPicker.show(context);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final title = config == null
        ? context.local.recording_save_location
        : recordingSaveLocationLabelForKind(context, config.kind);

    return InkWell(
      onTap: _openPicker,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.local.recording_save_location,
                  style: ProtonStyles.body1Medium(
                    color: context.colors.textNorm,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: ProtonStyles.body2Regular(
                    color: context.colors.textWeak,
                  ),
                ),
                if (_pathSummary.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _pathSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ProtonStyles.body2Regular(
                      color: context.colors.textWeak,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: context.colors.interActionWeak),
        ],
      ),
    );
  }
}

class _LocationChoice extends StatelessWidget {
  const _LocationChoice({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: ProtonStyles.body1Medium(color: context.colors.textNorm),
            ),
          ),
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected
                ? context.colors.protonBlue
                : context.colors.interActionWeak,
            size: 22,
          ),
        ],
      ),
    );
  }
}
