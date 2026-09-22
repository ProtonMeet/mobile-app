import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meet/utils/mentions/mention_composer_display.dart';
import 'package:meet/utils/mentions/mention_label.dart';
import 'package:meet/utils/mentions/mention_plain_text.dart';
import 'package:meet/utils/mentions/mention_token.dart';

/// Keeps stored text (with tokens) in sync with the display text shown in the
/// composer (`@Name` form).
class MentionComposerController extends ChangeNotifier {
  MentionComposerController({
    required this.resolveParticipantName,
    required this.everyoneName,
    required this.unknownName,
    required this.localIdentity,
    String initialStored = '',
  }) : _stored = initialStored {
    displayController.text = _plainText(_stored);
    displayController.addListener(_onDisplayChanged);
  }

  final String Function(String id) resolveParticipantName;
  final String everyoneName;
  final String unknownName;
  final String localIdentity;

  String _stored;
  bool _applyingDisplayUpdate = false;

  final TextEditingController displayController = TextEditingController();

  String get storedText => _stored;

  List<MentionDisplayRange> get mentionDisplayRanges =>
      computeMentionDisplayRanges(
        stored: _stored,
        resolveParticipantName: resolveParticipantName,
        localIdentity: localIdentity,
        everyoneName: everyoneName,
        unknownName: unknownName,
      );

  void setStored(String value) {
    _stored = value;
    _refreshDisplay();
    notifyListeners();
  }

  void clear() {
    _stored = '';
    _refreshDisplay();
    notifyListeners();
  }

  void disposeController() {
    displayController.removeListener(_onDisplayChanged);
    displayController.dispose();
    super.dispose();
  }

  String _plainText(String stored) {
    return mentionPlainText(
      stored,
      participantNameMap: {
        for (final id in extractMentionIds(stored))
          id: resolveParticipantName(id),
      },
      localIdentity: localIdentity,
      everyoneName: everyoneName,
      unknownName: unknownName,
    );
  }

  String _mentionLabel(String id) {
    return getMentionLabel(
      id,
      participantName: resolveParticipantName(id),
      localIdentity: localIdentity,
      everyoneName: everyoneName,
      unknownName: unknownName,
    );
  }

  void _refreshDisplay() {
    _applyingDisplayUpdate = true;
    final selection = displayController.selection;
    displayController.text = _plainText(_stored);
    if (selection.isValid) {
      final maxOffset = displayController.text.length;
      displayController.selection = selection.copyWith(
        baseOffset: selection.baseOffset.clamp(0, maxOffset),
        extentOffset: selection.extentOffset.clamp(0, maxOffset),
      );
    }
    _applyingDisplayUpdate = false;
  }

  void _onDisplayChanged() {
    if (_applyingDisplayUpdate) {
      return;
    }
    _stored = _rebuildStoredFromDisplay(displayController.text);
    notifyListeners();
  }

  String _rebuildStoredFromDisplay(String display) {
    final mentionSegments = splitMessageIntoMentionSegments(
      _stored,
    ).whereType<MentionSegment>().toList();
    if (mentionSegments.isEmpty) {
      return display;
    }

    // Match from the end so a literal `@Name` earlier in the display is not
    // mistaken for a completed mention.
    final replacements = <int, MentionSegment>{};
    var searchEnd = display.length;
    for (var i = mentionSegments.length - 1; i >= 0; i--) {
      final segment = mentionSegments[i];
      final label = '@${_mentionLabel(segment.id)}';
      final index = display.lastIndexOf(label, searchEnd);
      if (index < 0) {
        return display;
      }
      replacements[index] = segment;
      searchEnd = index - 1;
    }

    final sortedStarts = replacements.keys.toList()..sort();
    final buffer = StringBuffer();
    var cursor = 0;
    for (final start in sortedStarts) {
      final segment = replacements[start]!;
      final label = '@${_mentionLabel(segment.id)}';
      buffer.write(display.substring(cursor, start));
      buffer.write(segment.rawToken);
      cursor = start + label.length;
    }
    buffer.write(display.substring(cursor));
    return buffer.toString();
  }

  int _displayOffsetToStoredOffset(String display, int displayOffset) {
    var storedIndex = 0;
    var displayIndex = 0;

    while (displayIndex < displayOffset && storedIndex < _stored.length) {
      final tokenMatch = mentionTokenRegex.matchAsPrefix(_stored, storedIndex);
      if (tokenMatch != null) {
        final id = tokenMatch.group(1)!;
        final label = '@${_mentionLabel(id)}';
        if (displayIndex + label.length <= displayOffset) {
          displayIndex += label.length;
          storedIndex = tokenMatch.end;
          continue;
        }
        break;
      }

      displayIndex++;
      storedIndex++;
    }

    return storedIndex;
  }

  /// Applies atomic mention edits and keeps [_stored] in sync.
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_applyingDisplayUpdate) {
      return newValue;
    }

    final oldText = oldValue.text;
    final newText = newValue.text;
    if (oldText == newText) {
      return newValue;
    }

    final ranges = mentionDisplayRanges;
    if (ranges.isEmpty) {
      _stored = _rebuildStoredFromDisplay(newText);
      notifyListeners();
      return newValue;
    }

    var changeStart = 0;
    while (changeStart < oldText.length &&
        changeStart < newText.length &&
        oldText[changeStart] == newText[changeStart]) {
      changeStart++;
    }

    var oldEnd = oldText.length;
    var newEnd = newText.length;
    while (oldEnd > changeStart &&
        newEnd > changeStart &&
        oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }

    final affectedRanges = ranges
        .where((range) => range.intersects(changeStart, oldEnd))
        .toList();

    if (affectedRanges.isEmpty) {
      _stored = _rebuildStoredFromDisplay(newText);
      notifyListeners();
      return newValue;
    }

    var deleteStart = changeStart;
    var deleteEnd = oldEnd;
    for (final range in affectedRanges) {
      deleteStart = math.min(deleteStart, range.start);
      deleteEnd = math.max(deleteEnd, range.end);
    }

    final inserted = newText.substring(changeStart, newEnd);
    final nextDisplay = oldText.replaceRange(deleteStart, deleteEnd, inserted);
    _applyDisplayText(nextDisplay, deleteStart + inserted.length);
    notifyListeners();
    return displayController.value;
  }

  void _applyDisplayText(String text, int caret, {bool rebuildStored = true}) {
    _applyingDisplayUpdate = true;
    final clampedCaret = caret.clamp(0, text.length);
    displayController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: clampedCaret),
    );
    if (rebuildStored) {
      _stored = _rebuildStoredFromDisplay(text);
    }
    _applyingDisplayUpdate = false;
  }

  /// Inserts a picked mention, replacing `@query` with a token and trailing space.
  bool insertMention({
    required String id,
    required String label,
    required int atIndex,
    required int queryLength,
  }) {
    final token = getMentionToken(id);
    final projected = StringBuffer()
      ..write(
        _stored.substring(
          0,
          _displayOffsetToStoredOffset(displayController.text, atIndex),
        ),
      )
      ..write(token)
      ..write(' ')
      ..write(
        _stored.substring(
          _displayOffsetToStoredOffset(
            displayController.text,
            atIndex + 1 + queryLength,
          ),
        ),
      );

    final nextStored = projected.toString();
    if (nextStored.trim().length > chatMessageMaxLength) {
      return false;
    }

    _stored = nextStored;

    final display = displayController.text;
    final before = display.substring(0, atIndex);
    final after = display.substring(atIndex + 1 + queryLength);
    final mentionDisplay = '@$label ';
    final nextDisplay = '$before$mentionDisplay$after';

    _applyingDisplayUpdate = true;
    displayController.value = TextEditingValue(
      text: nextDisplay,
      selection: TextSelection.collapsed(
        offset: before.length + mentionDisplay.length,
      ),
    );
    _applyingDisplayUpdate = false;
    notifyListeners();
    return true;
  }
}

/// Deletes whole `@mention` units instead of single characters.
class MentionComposerTextInputFormatter extends TextInputFormatter {
  MentionComposerTextInputFormatter(this.controller);

  final MentionComposerController controller;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return controller.formatEditUpdate(oldValue, newValue);
  }
}
