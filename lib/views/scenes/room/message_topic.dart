import 'package:collection/collection.dart';

/// Will be deprecated in favor of [PublishableDataType]-based routing.
@Deprecated('Use PublishableDataType for type-based message routing instead')
enum MessageTopic { e2eeMessage, recordingStatus }

enum RecordingStatus { started, stopped }

/// Matches PublishableDataTypes from web
enum PublishableDataType {
  recordingStatus('recordingStatus'),
  message('message'),
  emojiReaction('emojiReaction'),
  raiseHand('raiseHand'),
  chatMessageReaction('chatMessageReaction');

  const PublishableDataType(this.value);
  final String value;

  static PublishableDataType? fromString(String? v) => v != null
      ? PublishableDataType.values.firstWhereOrNull((e) => e.value == v)
      : null;
}
