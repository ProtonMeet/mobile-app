import 'package:meet/helper/logger.dart' as l;
import 'package:meet/models/live_captions/live_caption_text_stream.dart';
import 'package:meet/models/live_captions/live_captions_models.dart';
import 'package:meet/rust/proton_meet/core.dart';

/// Decrypts a base64-encoded MLS transcription payload via Meet Core.
///
/// Uses [decodeTranscriptionPayload] (binary base64) — not the chat
/// `decryptMessage` wrapper in `room.dart`, which treats ciphertext as UTF-8
/// code units.
Future<DecryptedCaptionMessage?> decryptTranscriptionPayload({
  required AppCore appCore,
  required String base64Payload,
}) async {
  if (base64Payload.isEmpty) {
    return null;
  }
  try {
    final bytes = decodeTranscriptionPayload(base64Payload);
    final record = await appCore.decryptMessage(data: bytes);
    return DecryptedCaptionMessage.fromRecord(record);
  } catch (e, stackTrace) {
    l.logger.w(
      '[LiveCaptions] decryptTranscriptionPayload failed: $e',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}
