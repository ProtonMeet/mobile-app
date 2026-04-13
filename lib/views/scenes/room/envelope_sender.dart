/// Parses the claimed LiveKit participant identity from our data-channel envelope.
///
/// Senders set `id` to `'$identity-$timestamp'` and `timestamp` to the same
/// millisecond value (see room chat publish helpers).
String? claimedParticipantIdFromEnvelope(Map<String, dynamic> json) {
  final id = json['id'];
  if (id is! String) {
    return null;
  }

  final tsMillis = switch (json['timestamp']) {
    final int v => v,
    final num v => v.toInt(),
    final String s => int.tryParse(s),
    null => null,
    _ => null,
  };
  if (tsMillis == null) {
    return null;
  }

  final suffix = '-$tsMillis';
  if (!id.endsWith(suffix) || id.length == suffix.length) {
    return null;
  }
  return id.substring(0, id.length - suffix.length);
}
