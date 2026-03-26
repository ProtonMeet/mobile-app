enum ApiEnvType { prod, atlas, local, staging }

class ApiEnv {
  final ApiEnvType type;
  final String? custom; // Only used for the atlas type

  const ApiEnv.prod() : type = ApiEnvType.prod, custom = null;
  const ApiEnv.local() : type = ApiEnvType.local, custom = null;
  const ApiEnv.staging() : type = ApiEnvType.staging, custom = null;
  ApiEnv.atlas(this.custom) : type = ApiEnvType.atlas;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ApiEnv && other.type == type && other.custom == custom;
  }

  @override
  int get hashCode => Object.hash(type, custom);

  @override
  String toString() {
    switch (type) {
      case ApiEnvType.prod:
        return "prod";
      case ApiEnvType.staging:
        // staging is the same as prod for now
        return "prod";
      case ApiEnvType.atlas:
        return "atlas${custom != null ? ':$custom' : ''}";
      case ApiEnvType.local:
        return "local";
    }
  }

  /// Isolates local on-disk / secure storage between backends. Prefer this over [toString]
  /// for cache invalidation (staging vs prod differ, custom atlas variants differ).
  String get cacheIsolationKey {
    switch (type) {
      case ApiEnvType.prod:
        return 'prod';
      case ApiEnvType.staging:
        return 'staging';
      case ApiEnvType.local:
        return 'local';
      case ApiEnvType.atlas:
        return 'atlas:${custom ?? 'default'}';
    }
  }

  String get apiPath {
    return "$baseUrl/api";
  }

  String get wsHost {
    switch (type) {
      case ApiEnvType.prod:
        return "meet.proton.me/meet/api";
      case ApiEnvType.staging:
        return "meet-mls.protontech.ch";
      case ApiEnvType.atlas:
        return "mls.${custom != null ? '$custom.' : ''}proton.black";
      case ApiEnvType.local:
        return "localhost:8090";
    }
  }

  String get httpHost {
    switch (type) {
      case ApiEnvType.prod:
        return "meet.proton.me/meet/api";
      case ApiEnvType.staging:
        return "meet-mls.protontech.ch";
      case ApiEnvType.atlas:
        return "mls.${custom != null ? '$custom.' : ''}proton.black";
      case ApiEnvType.local:
        return "localhost:8090";
    }
  }

  String get baseUrl {
    return "https://$domain";
  }

  String get domain {
    switch (type) {
      case ApiEnvType.prod:
        return "meet.proton.me";
      case ApiEnvType.staging:
        return "meet.proton.me";
      case ApiEnvType.atlas:
        return "meet.${custom != null ? '$custom.' : ''}proton.black";
      case ApiEnvType.local:
        return "localhost";
    }
  }
}

final payments = ApiEnv.atlas("payments");
