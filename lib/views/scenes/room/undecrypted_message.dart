class UnDecryptedMessage {
  final String message;
  final int keyIndex;
  final String identity;
  final String name;
  bool hasProcessed = false;
  UnDecryptedMessage({
    required this.message,
    required this.keyIndex,
    required this.identity,
    required this.name,
  });
}
