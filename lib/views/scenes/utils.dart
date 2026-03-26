import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

FutureOr<void> Function()? onWindowShouldClose;

String generateRandomName({int length = 8}) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random.secure();
  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}

Future<T> retry<T>({
  required Future<T> Function() action,
  int maxRetries = 3,
  Duration delay = const Duration(seconds: 1),
}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await action();
    } catch (e) {
      if (attempt == maxRetries) {
        // Last attempt → rethrow
        rethrow;
      }
      // Optional: wait before retrying
      await Future.delayed(delay);
    }
  }
  throw Exception('Unexpected retry error'); // Should never reach here
}

/// Helper function to execute an action with timeout and retry
/// This combines timeout protection with automatic retry logic
Future<T> retryWithTimeout<T>({
  required Future<T> Function() action,
  Duration timeout = const Duration(seconds: 15),
  int maxRetries = 2,
  Duration retryDelay = const Duration(seconds: 2),
  String? operationName,
}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await action().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
            '${operationName ?? "Operation"} timed out after ${timeout.inSeconds}s (attempt $attempt/$maxRetries)',
            timeout,
          );
        },
      );
    } catch (e) {
      if (attempt == maxRetries) {
        // Log error on final attempt
        debugPrint(
          '[retryWithTimeout] ${operationName ?? "Operation"} failed after $maxRetries attempts: $e',
        );
        rethrow;
      }
      // Log warning and retry
      debugPrint(
        '[retryWithTimeout] ${operationName ?? "Operation"} attempt $attempt failed, retrying in ${retryDelay.inSeconds}s: $e',
      );
      await Future.delayed(retryDelay);
    }
  }
  throw Exception('Unexpected retry error');
}

/// Extracts initials from a name string.
///
/// Examples:
/// - "John Doe" → "JD"
/// - "Marina Norbert" → "MN"
/// - "Marina" → "MA"
/// - "tyler" → "TY"
/// - "A" → "A"
/// - "李雷" → "李雷" (handles Unicode characters)
/// - null or empty → returns [defaultValue]
///
/// Parameters:
/// - [name]: The name string to extract initials from (can be null)
/// - [defaultValue]: The default value to return if name is null or empty (default: 'AP')
///
/// Returns:
/// - A string containing 1-2 uppercase initials, or the defaultValue if name is empty/null
String getInitials(String? name, {String defaultValue = 'AP'}) {
  if (name == null || name.trim().isEmpty) return defaultValue;
  final trimmedName = name.trim();

  try {
    // If it contains spaces, take the first letter of the first two words
    final parts = trimmedName.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return parts
          .take(2)
          .map((word) => word.characters.first.toUpperCase())
          .join();
    }
    // If it's a single word, take the first 1–2 characters (handles Unicode)
    return trimmedName.characters.take(2).toString().toUpperCase();
  } catch (e) {
    // Fallback for edge cases
    if (trimmedName.isNotEmpty) {
      return trimmedName.characters.first.toUpperCase();
    }
    return defaultValue;
  }
}
