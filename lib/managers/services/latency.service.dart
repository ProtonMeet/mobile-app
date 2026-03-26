import 'dart:async';
import 'package:http/http.dart' as http;

class LatencyService {
  /// Measures the latency of a URL by making a HEAD request
  /// Returns the latency in milliseconds, or -1 if the request fails
  static Future<int> measureLatency(String url) async {
    try {
      final stopwatch = Stopwatch()..start();

      final response = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return stopwatch.elapsedMilliseconds;
      }
      return -1;
    } catch (e) {
      return -1;
    }
  }

  /// Measures the latency multiple times and returns the average
  /// [url] - The URL to test
  /// [attempts] - Number of attempts to measure (default: 3)
  /// Returns the average latency in milliseconds, or -1 if all attempts fail
  static Future<int> measureAverageLatency(
    String url, {
    int attempts = 3,
  }) async {
    final List<int> latencies = [];

    for (int i = 0; i < attempts; i++) {
      final latency = await measureLatency(url);
      if (latency > 0) {
        latencies.add(latency);
      }
      // Small delay between attempts
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (latencies.isEmpty) {
      return -1;
    }

    return (latencies.reduce((a, b) => a + b) / latencies.length).round();
  }

  /// Calculates the appropriate debounce time based on network latency
  /// [latency] - The measured network latency in milliseconds
  /// Returns the recommended debounce time in milliseconds
  static int calculateDebounceTime(int latency) {
    // Base debounce time (minimum)
    const int baseDebounce = 300;

    // For high latency (>1000ms), use a more aggressive debounce
    if (latency > 1000) {
      // Cap the maximum debounce at 2000ms
      return (latency * 1.2).round().clamp(baseDebounce, 2000);
    }

    // For moderate latency (300-1000ms), use a moderate debounce
    if (latency > 300) {
      return (latency * 1.5).round().clamp(baseDebounce, 1000);
    }

    // For low latency (<300ms), use the base debounce
    return baseDebounce;
  }

  /// Gets the recommended debounce time for a given URL
  /// [url] - The URL to test
  /// Returns the recommended debounce time in milliseconds
  static Future<int> getRecommendedDebounceTime(String url) async {
    final latency = await measureAverageLatency(url);
    if (latency < 0) {
      // If we can't measure latency, return a safe default
      return 1000;
    }
    return calculateDebounceTime(latency);
  }
}
