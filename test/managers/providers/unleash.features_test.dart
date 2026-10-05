import 'package:flutter_test/flutter_test.dart';
import 'package:meet/managers/providers/unleash.features.dart';
import 'package:unleash_proxy_client_flutter/variant.dart';

void main() {
  group('FeatureClientDefault', () {
    test('off preset maps to disabled toggle config', () {
      final config = FeatureClientDefault.off.toToggleConfig();

      expect(config.enabled, isFalse);
      expect(config.impressionData, isFalse);
      expect(config.variant, equals(Variant(enabled: false, name: 'disabled')));
    });

    test('on preset maps to enabled toggle config', () {
      final config = FeatureClientDefault.on.toToggleConfig();

      expect(config.enabled, isTrue);
      expect(config.variant.enabled, isTrue);
      expect(config.variant.name, 'enabled');
    });

    test('supports custom variant fields', () {
      const custom = FeatureClientDefault(
        enabled: true,
        impressionData: true,
        variantName: 'beta',
        variantEnabled: true,
      );
      final config = custom.toToggleConfig();

      expect(config.enabled, isTrue);
      expect(config.impressionData, isTrue);
      expect(config.variant.name, 'beta');
      expect(config.variant.enabled, isTrue);
    });
  });

  group('kClientDisabledToggle', () {
    test('matches FeatureClientDefault.off', () {
      expect(
        kClientDisabledToggle,
        equals(FeatureClientDefault.off.toToggleConfig()),
      );
    });
  });

  group('UnleashFeature', () {
    test('maps every feature to a unique unleash toggle name', () {
      final names = UnleashFeature.values
          .map((feature) => feature.toggleName)
          .toList();

      expect(names, hasLength(UnleashFeature.values.length));
      expect(names.toSet(), hasLength(UnleashFeature.values.length));
      expect(
        UnleashFeature.meetMeetingRecordingNative.toggleName,
        'MeetingRecordingNative',
      );
      expect(UnleashFeature.isNeedForceUpgrade.toggleName, 'NeedForceUpgrade');
    });

    test('returns client defaults only for opted-in features', () {
      const clientDefaultOff = {
        UnleashFeature.meetVp9,
        UnleashFeature.meetH264,
        UnleashFeature.isNeedForceUpgrade,
        UnleashFeature.meetShowProtonCalendar,
        UnleashFeature.meetAdminLowerHand,
        UnleashFeature.meetMobileInAppUpdate,
        UnleashFeature.meetUseCachedServerTime,
        UnleashFeature.meetUseMessageQueues,
        UnleashFeature.meetSettingsPreview,
      };

      for (final feature in UnleashFeature.values) {
        if (clientDefaultOff.contains(feature)) {
          expect(feature.clientDefault, FeatureClientDefault.off);
          expect(feature.defaultValue, equals(kClientDisabledToggle));
        } else {
          expect(feature.clientDefault, isNull);
          expect(feature.defaultValue, isNull);
        }
      }
    });

    test('denoise backends declare meetAudioDenoise as parent', () {
      const children = [
        UnleashFeature.meetAudioDenoiseRnnoise,
        UnleashFeature.meetAudioDenoiseDeepfilter,
        UnleashFeature.meetAudioDenoiseDtlnRs,
      ];

      for (final child in children) {
        expect(child.parent, UnleashFeature.meetAudioDenoise);
      }
      expect(UnleashFeature.meetAudioDenoise.parent, isNull);
    });

    test('kUnleashLocalOverrides is empty by default', () {
      expect(kUnleashLocalOverrides, isEmpty);
    });
  });
}
