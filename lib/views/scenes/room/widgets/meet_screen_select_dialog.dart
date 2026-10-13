// Based on LiveKit client-sdk-flutter ScreenSelectDialog (Apache 2.0).
//
// In-app previews for screens and windows before publish (macOS, Windows,
// Linux X11). Must not be shown on Linux Wayland: libwebrtc's
// RTCDesktopMediaListImpl segfaults when enumerating sources there, so the
// xdg-desktop-portal dialog is the picker instead.

import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// Result of the desktop screen-share source selection.
class ScreenSharePickerResult {
  const ScreenSharePickerResult.systemPortal()
    : useSystemPortal = true,
      sourceId = null;

  const ScreenSharePickerResult.source(String id)
    : useSystemPortal = false,
      sourceId = id;

  /// Linux Wayland path: xdg-desktop-portal via getDisplayMedia (no sourceId).
  final bool useSystemPortal;

  /// Window or monitor id from [rtc.desktopCapturer].
  final String? sourceId;
}

class MeetScreenSelectThumbnail extends StatefulWidget {
  const MeetScreenSelectThumbnail({
    required this.source,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final rtc.DesktopCapturerSource source;
  final bool selected;
  final void Function(rtc.DesktopCapturerSource) onTap;

  @override
  State<MeetScreenSelectThumbnail> createState() =>
      _MeetScreenSelectThumbnailState();
}

class _MeetScreenSelectThumbnailState extends State<MeetScreenSelectThumbnail> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Uint8List? _thumbnail;
  String _name = '';

  @override
  void initState() {
    super.initState();
    _name = widget.source.name;
    _thumbnail = widget.source.thumbnail?.isNotEmpty == true
        ? widget.source.thumbnail
        : null;
    _subscriptions.add(
      widget.source.onThumbnailChanged.stream.listen((thumbnail) {
        setState(() => _thumbnail = thumbnail);
      }),
    );
    _subscriptions.add(
      widget.source.onNameChanged.stream.listen((name) {
        setState(() => _name = name);
      }),
    );
  }

  @override
  void deactivate() {
    for (final element in _subscriptions) {
      unawaited(element.cancel());
    }
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: widget.selected
                ? BoxDecoration(
                    border: Border.all(width: 2, color: Colors.blueAccent),
                  )
                : null,
            child: InkWell(
              onTap: () => widget.onTap(widget.source),
              child: _thumbnail != null
                  ? Image.memory(
                      _thumbnail!,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                    )
                  : Center(
                      child: Icon(
                        widget.source.type == rtc.SourceType.Window
                            ? Icons.web_asset_outlined
                            : Icons.monitor_outlined,
                        size: 48,
                        color: Colors.black38,
                      ),
                    ),
            ),
          ),
        ),
        Text(
          _name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.black87,
            fontWeight: widget.selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

/// Desktop screen/window picker with previews before publishing a
/// screen-share track.
class MeetScreenSelectDialog extends StatefulWidget {
  const MeetScreenSelectDialog({
    super.key,
    this.titleText = 'Choose what to share',
    this.screenTabText = 'Entire Screen',
    this.windowTabText = 'Window',
    this.cancelText = 'Cancel',
    this.shareText = 'Share',
  });

  final String titleText;
  final String screenTabText;
  final String windowTabText;
  final String cancelText;
  final String shareText;

  static Future<ScreenSharePickerResult?> show(
    BuildContext context, {
    String titleText = 'Choose what to share',
    String screenTabText = 'Entire Screen',
    String windowTabText = 'Window',
    String cancelText = 'Cancel',
    String shareText = 'Share',
  }) {
    return showDialog<ScreenSharePickerResult>(
      context: context,
      builder: (context) => MeetScreenSelectDialog(
        titleText: titleText,
        screenTabText: screenTabText,
        windowTabText: windowTabText,
        cancelText: cancelText,
        shareText: shareText,
      ),
    );
  }

  @override
  State<MeetScreenSelectDialog> createState() => _MeetScreenSelectDialogState();
}

class _MeetScreenSelectDialogState extends State<MeetScreenSelectDialog> {
  static final rtc.ThumbnailSize _previewSize = rtc.ThumbnailSize(480, 360);

  final Map<String, rtc.DesktopCapturerSource> _sources = {};
  final List<StreamSubscription<rtc.DesktopCapturerSource>> _subscriptions = [];
  rtc.SourceType _sourceType = rtc.SourceType.Screen;
  rtc.DesktopCapturerSource? _selectedSource;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(
        rtc.desktopCapturer.onAdded.stream.listen((source) {
          _sources[source.id] = source;
          _refresh();
        }),
      )
      ..add(
        rtc.desktopCapturer.onRemoved.stream.listen((source) {
          _sources.remove(source.id);
          if (_selectedSource?.id == source.id) {
            _selectedSource = null;
          }
          _refresh();
        }),
      )
      ..add(
        rtc.desktopCapturer.onThumbnailChanged.stream.listen((_) => _refresh()),
      );
    unawaited(
      _loadSources(const [rtc.SourceType.Screen, rtc.SourceType.Window]),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final element in _subscriptions) {
      unawaited(element.cancel());
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSources(List<rtc.SourceType> types) async {
    try {
      for (final type in types) {
        final sources = await rtc.desktopCapturer.getSources(
          types: [type],
          thumbnailSize: _previewSize,
        );
        if (!mounted) return;
        _sources.removeWhere((_, source) => source.type == type);
        for (final element in sources) {
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              'MeetScreenSelect: name=${element.name}, id=${element.id}, type=${element.type}',
            );
          }
          _sources[element.id] = element;
        }
      }
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(rtc.desktopCapturer.updateSources(types: [_sourceType]));
      });
      _refresh();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MeetScreenSelect getSources failed: $e');
      }
    }
  }

  void _onTabSelected(int index) {
    setState(() {
      _sourceType = index == 0 ? rtc.SourceType.Screen : rtc.SourceType.Window;
      _selectedSource = null;
    });
    unawaited(_loadSources([_sourceType]));
  }

  void _share() {
    final source = _selectedSource;
    if (source == null) return;
    Navigator.pop(context, ScreenSharePickerResult.source(source.id));
  }

  void _cancel() {
    Navigator.pop<ScreenSharePickerResult>(context, null);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: 640,
          height: 560,
          color: Colors.white,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        widget.titleText,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: InkWell(
                        onTap: _cancel,
                        child: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 24,
                          child: TabBar(
                            onTap: _onTabSelected,
                            tabs: [
                              Tab(
                                child: Text(
                                  widget.screenTabText,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ),
                              Tab(
                                child: Text(
                                  widget.windowTabText,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _sourceGrid(rtc.SourceType.Screen),
                              _sourceGrid(rtc.SourceType.Window),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: OverflowBar(
                  children: [
                    TextButton(
                      onPressed: _cancel,
                      child: Text(
                        widget.cancelText,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                    FilledButton(
                      onPressed: _selectedSource != null ? _share : null,
                      child: Text(widget.shareText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceGrid(rtc.SourceType type) {
    final entries = _sources.values
        .where((source) => source.type == type)
        .toList();
    if (entries.isEmpty) {
      final message = type == rtc.SourceType.Window
          ? 'No windows found.\nOpen an app window and switch to this tab, or check capture permissions.'
          : 'No screens found.\nCheck display and capture permissions.';
      return Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
      );
    }
    return GridView.count(
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      crossAxisCount: type == rtc.SourceType.Screen ? 2 : 3,
      children: entries
          .map(
            (source) => MeetScreenSelectThumbnail(
              key: ValueKey(source.id),
              source: source,
              selected: _selectedSource?.id == source.id,
              onTap: (source) => setState(() => _selectedSource = source),
            ),
          )
          .toList(),
    );
  }
}
