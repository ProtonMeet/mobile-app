import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/scenes/room/recording/recording_save_location.dart';
import 'package:meet/views/scenes/room/recording/recording_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Lists completed local recordings and opens the system share sheet.
class SavedRecordingsSheet {
  SavedRecordingsSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (ctx) => const _SavedRecordingsBody(),
    );
  }
}

/// In-room / settings row that opens [SavedRecordingsSheet].
class SavedRecordingsSettingRow extends StatelessWidget {
  const SavedRecordingsSettingRow({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => SavedRecordingsSheet.show(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.local.saved_recordings_title,
              style: ProtonStyles.body1Medium(color: context.colors.textNorm),
            ),
          ),
          Icon(Icons.chevron_right, color: context.colors.interActionWeak),
        ],
      ),
    );
  }
}

class _SavedRecordingsBody extends StatefulWidget {
  const _SavedRecordingsBody();

  @override
  State<_SavedRecordingsBody> createState() => _SavedRecordingsBodyState();
}

class _SavedRecordingsBodyState extends State<_SavedRecordingsBody> {
  final RecordingStorage _storage = RecordingStorage();
  List<RecordingSession> _recordings = const [];
  String _folderPath = '';
  bool _loading = true;
  String? _sharingSessionId;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final config = await RecordingSaveLocationConfig.load();
    final folderPath = await config.displayPath();
    final recordings = await _storage.reconcileAll();
    if (!mounted) return;
    setState(() {
      _folderPath = folderPath;
      _recordings = recordings;
      _loading = false;
    });
  }

  Future<void> _shareRecording(
    RecordingSession session, {
    BuildContext? anchorContext,
  }) async {
    if (_sharingSessionId != null) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorTitle = context.local.error;

    setState(() => _sharingSessionId = session.id);
    try {
      final file = File(session.filePath);
      if (!file.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.local.saved_recordings_missing_file),
            ),
          );
        }
        await _reload();
        return;
      }

      final subject = session.roomName?.trim().isNotEmpty == true
          ? session.roomName!
          : p.basenameWithoutExtension(session.filePath);

      // iOS share targets cannot read private Documents URLs; copy to temp first.
      final shareFile = await _copyRecordingForShare(
        source: file,
        suggestedName: subject,
      );

      if (!kIsWeb && iOS && mounted) {
        // UIActivityViewController is hidden behind modal bottom sheets on iOS.
        Navigator.of(context).pop();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              shareFile.path,
              mimeType: 'video/mp4',
              name: p.basename(shareFile.path),
            ),
          ],
          subject: subject,
          sharePositionOrigin:
              anchorContext == null || !anchorContext.mounted || iOS
              ? null
              : _shareOriginForContext(anchorContext),
        ),
      );
    } catch (e, stackTrace) {
      l.logger.e(
        '[SavedRecordings] share failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
      messenger?.showSnackBar(SnackBar(content: Text('$errorTitle: $e')));
      if (mounted) {
        LocalToast.showToastification(
          context,
          errorTitle,
          context.local.saved_recordings_share_failed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sharingSessionId = null);
      }
    }
  }

  Future<File> _copyRecordingForShare({
    required File source,
    required String suggestedName,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final base = _sanitizeShareFileName(suggestedName);
    final fileName = base.toLowerCase().endsWith('.mp4') ? base : '$base.mp4';
    final dest = File(p.join(tempDir.path, fileName));
    if (dest.existsSync()) {
      await dest.delete();
    }
    return source.copy(dest.path);
  }

  String _sanitizeShareFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'proton-meet-recording-${DateTime.now().millisecondsSinceEpoch}';
    }
    return trimmed
        .replaceAll(RegExp(r'[^\w\-. ]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Rect? _shareOriginForContext(BuildContext anchorContext) {
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  String _formatTimestamp(BuildContext context, RecordingSession session) {
    final ms = session.completedAtMs ?? session.startedAtMs;
    final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).add_jm().format(date);
  }

  String _formatFileSize(String path) {
    final file = File(path);
    if (!file.existsSync()) return '';
    return _formatBytes(file.lengthSync());
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    final index = math.min(
      (math.log(bytes) / math.log(1024)).floor(),
      units.length - 1,
    );
    final size = bytes / math.pow(1024, index);
    final decimals = index == 0 ? 0 : 1;
    return '${size.toStringAsFixed(decimals)} ${units[index]}';
  }

  @override
  Widget build(BuildContext context) {
    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: context.isLandscape,
      modalOnBackdropTap: () => Navigator.of(context).pop(),
      modalMaxHeight: context.height * 0.85,
      innerEnableHandleDragPassthrough: false,
      outerEnableHandleDragPassthrough: true,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(
              context.local.saved_recordings_title,
              style: ProtonStyles.headline(
                fontSize: 18,
                color: context.colors.textNorm,
              ),
            ),
          ),
        ),
        if (_folderPath.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '${context.local.saved_recordings_folder}\n$_folderPath',
                style: ProtonStyles.body2Regular(
                  color: context.colors.textWeak,
                ),
              ),
            ),
          ),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_recordings.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: Text(
                  context.local.saved_recordings_empty,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.body1Regular(
                    color: context.colors.textWeak,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverList.separated(
              itemCount: _recordings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final session = _recordings[index];
                final title = session.roomName?.trim().isNotEmpty == true
                    ? session.roomName!
                    : p.basename(session.filePath);
                final subtitle = [
                  _formatTimestamp(context, session),
                  _formatFileSize(session.filePath),
                ].where((part) => part.isNotEmpty).join(' · ');
                final isRecovered =
                    session.status == RecordingSessionStatus.recovered;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _sharingSessionId != null
                          ? null
                          : () => unawaited(
                              _shareRecording(session, anchorContext: context),
                            ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: ProtonStyles.body1Medium(
                                      color: context.colors.textNorm,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: ProtonStyles.body2Regular(
                                      color: context.colors.textWeak,
                                    ),
                                  ),
                                  if (isRecovered) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      context.local.saved_recordings_recovered,
                                      style: ProtonStyles.body2Regular(
                                        color: context.colors.textWeak,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: context.local.saved_recordings_share,
                              onPressed: _sharingSessionId == session.id
                                  ? null
                                  : () => unawaited(
                                      _shareRecording(
                                        session,
                                        anchorContext: context,
                                      ),
                                    ),
                              icon: _sharingSessionId == session.id
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: context.colors.protonBlue,
                                      ),
                                    )
                                  : Icon(
                                      Icons.ios_share,
                                      color: context.colors.protonBlue,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
