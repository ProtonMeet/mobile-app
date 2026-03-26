import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/rust/proton_meet/user_config.dart';

import '../helper.dart';

void main() {
  group('UI Constants', () {
    testUnit('defaultPadding should be 16.0', () {
      expect(defaultPadding, equals(16.0));
    });

    testUnit('maxDeskTopSheetWidth should be 600.0', () {
      expect(maxDeskTopSheetWidth, equals(600.0));
    });

    testUnit('drawerMaxWidth should be 400.0', () {
      expect(drawerMaxWidth, equals(400.0));
    });

    testUnit('maxMobileSheetWidth should be 500.0', () {
      expect(maxMobileSheetWidth, equals(500.0));
    });
  });

  group('Animation Duration Constants', () {
    testUnit('defaultAnimationDuration should be 260ms', () {
      expect(
        defaultAnimationDuration,
        equals(const Duration(milliseconds: 260)),
      );
    });

    testUnit('defaultAnimationDurationLong should be 500ms', () {
      expect(
        defaultAnimationDurationLong,
        equals(const Duration(milliseconds: 500)),
      );
    });
  });

  group('Database Version Constants', () {
    testUnit('driftDatabaseVersion should be 1', () {
      expect(driftDatabaseVersion, equals(1));
    });

    testUnit('rustDatabaseVersion should be 1', () {
      expect(rustDatabaseVersion, equals(1));
    });
  });

  group('Meet Constants', () {
    testUnit('systemMessageIdentity should be correct', () {
      expect(systemMessageIdentity, equals("ProtonMeetSystemMessageIdentity"));
    });

    testUnit('livekitRoomKey should be correct', () {
      expect(livekitRoomKey, equals("ProtonMeetStaticRoomKey2025042118"));
    });

    testUnit('hiveFilesName should be correct', () {
      expect(hiveFilesName, equals("protono_meet_shared_preference"));
    });

    testUnit('defaultRoomId should be correct', () {
      expect(defaultRoomId, equals("Proton-Meet-For-MSA"));
    });
  });

  group('User Settings Constants', () {
    testUnit('defaultCameraResolution should be p720', () {
      expect(defaultCameraResolution, equals(VideoResolution.p720));
    });

    testUnit('defaultScreenSharingResolution should be p1080', () {
      expect(defaultScreenSharingResolution, equals(VideoResolution.p1080));
    });

    testUnit('defaultCameraMaxBitrate should be kbps500', () {
      expect(defaultCameraMaxBitrate, equals(VideoMaxBitrate.kbps500));
    });

    testUnit('defaultScreenSharingMaxBitrate should be kbps1000', () {
      expect(defaultScreenSharingMaxBitrate, equals(VideoMaxBitrate.kbps1000));
    });

    testUnit('defaultCameraPosition should be front', () {
      expect(defaultCameraPosition, equals(CameraPosition.front));
    });

    testUnit('maxDisplayNameLength should be 50', () {
      expect(maxDisplayNameLength, equals(50));
      expect(maxDisplayNameLength, greaterThan(0));
    });
  });

  group('Delay Constants', () {
    testUnit('delaySubscriptionUpdate should be 5000ms', () {
      expect(
        delaySubscriptionUpdate,
        equals(const Duration(milliseconds: 5000)),
      );
    });

    testUnit('delayUnsubscribeTrack should be 2000ms', () {
      expect(delayUnsubscribeTrack, equals(const Duration(milliseconds: 2000)));
    });
  });

  group('Simulation Constants', () {
    testUnit('defaultSimulationParticipantCount should be 1', () {
      expect(defaultSimulationParticipantCount, equals(1));
      expect(defaultSimulationParticipantCount, greaterThan(0));
    });

    testUnit('defaultSimulationEnableVideo should be true', () {
      expect(defaultSimulationEnableVideo, isTrue);
    });
  });

  group('Error Dialog Settings', () {
    testUnit('showExpandableErrorDetails should be true', () {
      expect(showExpandableErrorDetails, isTrue);
    });
  });

  group('Valid Timezones', () {
    testUnit('validTimeZones should not be empty', () {
      expect(validTimeZones, isNotEmpty);
    });

    testUnit('validTimeZones should contain UTC', () {
      expect(validTimeZones, contains('UTC'));
    });

    testUnit('validTimeZones should contain common timezones', () {
      expect(validTimeZones, contains('America/New_York'));
      expect(validTimeZones, contains('Europe/London'));
      expect(validTimeZones, contains('Asia/Tokyo'));
      expect(validTimeZones, contains('Australia/Sydney'));
    });

    testUnit('validTimeZones should not contain duplicates', () {
      final uniqueTimezones = validTimeZones.toSet();
      expect(uniqueTimezones.length, equals(validTimeZones.length));
    });
  });
}
