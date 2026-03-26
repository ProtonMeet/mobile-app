import 'package:livekit_client/livekit_client.dart';
import 'package:meet/rust/proton_meet/user_config.dart';

extension VideoMaxBitrateExtension on VideoMaxBitrate {
  VideoEncoding get videoEncoding {
    switch (this) {
      case VideoMaxBitrate.kbps2000:
        return const VideoEncoding(maxBitrate: 2000 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1900:
        return const VideoEncoding(maxBitrate: 1900 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1800:
        return const VideoEncoding(maxBitrate: 1800 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1700:
        return const VideoEncoding(maxBitrate: 1700 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1600:
        return const VideoEncoding(maxBitrate: 1600 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1500:
        return const VideoEncoding(maxBitrate: 1500 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1400:
        return const VideoEncoding(maxBitrate: 1400 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1300:
        return const VideoEncoding(maxBitrate: 1300 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1200:
        return const VideoEncoding(maxBitrate: 1200 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1100:
        return const VideoEncoding(maxBitrate: 1100 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps1000:
        return const VideoEncoding(maxBitrate: 1000 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps900:
        return const VideoEncoding(maxBitrate: 900 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps800:
        return const VideoEncoding(maxBitrate: 800 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps700:
        return const VideoEncoding(maxBitrate: 700 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps600:
        return const VideoEncoding(maxBitrate: 600 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps500:
        return const VideoEncoding(maxBitrate: 500 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps400:
        return const VideoEncoding(maxBitrate: 400 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps300:
        return const VideoEncoding(maxBitrate: 300 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps200:
        return const VideoEncoding(maxBitrate: 200 * 1024, maxFramerate: 15);
      case VideoMaxBitrate.kbps100:
        return const VideoEncoding(maxBitrate: 100 * 1024, maxFramerate: 15);
    }
  }
}

extension VideoResolutionExtension on VideoResolution {
  VideoDimensions get videoDimensions {
    switch (this) {
      case VideoResolution.p360:
        return VideoDimensionsPresets.h360_169;
      case VideoResolution.p720:
        return VideoDimensionsPresets.h720_169;
      case VideoResolution.p1080:
        return VideoDimensionsPresets.h1080_169;
      case VideoResolution.p4K:
        return VideoDimensionsPresets.h2160_169;
    }
  }
}
