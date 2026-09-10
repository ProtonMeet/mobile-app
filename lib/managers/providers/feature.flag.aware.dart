import 'package:meet/managers/providers/unleash.data.provider.dart';

/// Providers that expose state derived from Unleash feature flags.
abstract interface class FeatureFlagAware {
  Future<void> syncFromFeatureFlags(UnleashDataProvider unleash);
}
