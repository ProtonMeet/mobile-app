import 'dart:convert';
import 'dart:typed_data';

extension StringExtension on String {
  bool isPalindrome() {
    final String cleanedString = replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final String reversedString = cleanedString.split('').reversed.join();
    return cleanedString == reversedString;
  }

  Uint8List base64decode() {
    return base64Decode(this);
  }

  /// Sanitizes a string by:
  /// 1. Trimming leading and trailing whitespace
  /// 2. Removing control characters and zero-width characters
  /// 3. Escaping special HTML characters to prevent XSS when rendering in HTML
  /// 4. Limiting length if [maxLength] is provided
  ///
  /// Parameters:
  /// - [maxLength]: Optional maximum length of the sanitized string
  ///
  /// Returns:
  /// The sanitized string, or null if the result is empty
  String? sanitize({int? maxLength}) {
    final trimmed = trim();
    if (trimmed.isEmpty) return null;

    // Remove control characters and zero-width characters
    var cleaned = trimmed.replaceAll(
      RegExp(r'[\u0000-\u001F\u007F-\u009F\u200B-\u200D\uFEFF]'),
      '',
    );

    // Escape HTML special characters to prevent XSS when rendering in web/HTML contexts
    cleaned = const HtmlEscape().convert(cleaned);

    // Limit length to specified maximum if provided
    if (maxLength != null) {
      cleaned = cleaned.length > maxLength
          ? cleaned.substring(0, maxLength)
          : cleaned;
    }

    if (cleaned.isEmpty) return null;

    return cleaned;
  }

  String get meetingLinkHint => "$this/join/id-XXXX#pwd-YYYY";
}
