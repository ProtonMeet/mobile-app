import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/env.dart';

import '../helper.dart';

void main() {
  testUnit('Equality of ApiEnv.prod instances', () {
    const env1 = ApiEnv.prod();
    const env2 = ApiEnv.prod();
    expect(env1, equals(env2));
    expect(env1.hashCode, equals(env2.hashCode));
  });

  testUnit('Equality of ApiEnv.atlas with the same custom value', () {
    final env1 = ApiEnv.atlas("testEnv");
    final env2 = ApiEnv.atlas("testEnv");
    expect(env1, equals(env2));
    expect(env1.hashCode, equals(env2.hashCode));
  });

  testUnit('Inequality of ApiEnv.atlas with different custom values', () {
    final env1 = ApiEnv.atlas("testEnv1");
    final env2 = ApiEnv.atlas("testEnv2");
    expect(env1, isNot(equals(env2)));
    expect(env1.hashCode, isNot(equals(env2.hashCode)));
  });

  testUnit('Inequality between ApiEnv.prod and ApiEnv.atlas', () {
    const prodEnv = ApiEnv.prod();
    final atlasEnv = ApiEnv.atlas("testEnv");
    expect(prodEnv, isNot(equals(atlasEnv)));
    expect(prodEnv.hashCode, isNot(equals(atlasEnv.hashCode)));
  });

  testUnit('toString representation for ApiEnv.prod', () {
    const env = ApiEnv.prod();
    expect(env.toString(), equals("prod"));
  });

  testUnit('toString representation for ApiEnv.atlas with custom value', () {
    final env = ApiEnv.atlas("testEnv");
    expect(env.toString(), equals("atlas:testEnv"));
  });

  testUnit('toString representation for ApiEnv.atlas without custom value', () {
    final env = ApiEnv.atlas(null);
    expect(env.toString(), equals("atlas"));
  });

  testUnit('toString representation for ApiEnv.staging', () {
    const env = ApiEnv.staging();
    expect(env.toString(), equals("prod"));
  });

  testUnit('toString representation for ApiEnv.local', () {
    const env = ApiEnv.local();
    expect(env.toString(), equals("local"));
  });

  testUnit('apiPath for ApiEnv.prod', () {
    const env = ApiEnv.prod();
    expect(env.apiPath, equals("https://meet.proton.me/api"));
  });

  testUnit('apiPath for ApiEnv.atlas with custom value', () {
    final env = ApiEnv.atlas("testEnv");
    expect(env.apiPath, equals("https://meet.testEnv.proton.black/api"));
  });

  testUnit('apiPath for ApiEnv.atlas without custom value', () {
    final env = ApiEnv.atlas(null);
    expect(env.apiPath, equals("https://meet.proton.black/api"));
  });

  testUnit('Predefined payments ApiEnv instance', () {
    final expectedEnv = ApiEnv.atlas("payments");
    expect(payments, equals(expectedEnv));
    expect(payments.hashCode, equals(expectedEnv.hashCode));
    expect(payments.toString(), equals("atlas:payments"));
    expect(payments.apiPath, equals("https://meet.payments.proton.black/api"));
  });

  group('ApiEnv getters', () {
    testUnit('wsHost for ApiEnv.prod', () {
      const env = ApiEnv.prod();
      expect(env.wsHost, equals("meet.proton.me/meet/api"));
    });

    testUnit('wsHost for ApiEnv.staging', () {
      const env = ApiEnv.staging();
      expect(env.wsHost, equals("meet-mls.protontech.ch"));
    });

    testUnit('wsHost for ApiEnv.atlas with custom value', () {
      final env = ApiEnv.atlas("testEnv");
      expect(env.wsHost, equals("mls.testEnv.proton.black"));
    });

    testUnit('wsHost for ApiEnv.atlas without custom value', () {
      final env = ApiEnv.atlas(null);
      expect(env.wsHost, equals("mls.proton.black"));
    });

    testUnit('wsHost for ApiEnv.local', () {
      const env = ApiEnv.local();
      expect(env.wsHost, equals("localhost:8090"));
    });

    testUnit('httpHost for ApiEnv.prod', () {
      const env = ApiEnv.prod();
      expect(env.httpHost, equals("meet.proton.me/meet/api"));
    });

    testUnit('httpHost for ApiEnv.staging', () {
      const env = ApiEnv.staging();
      expect(env.httpHost, equals("meet-mls.protontech.ch"));
    });

    testUnit('httpHost for ApiEnv.atlas with custom value', () {
      final env = ApiEnv.atlas("testEnv");
      expect(env.httpHost, equals("mls.testEnv.proton.black"));
    });

    testUnit('httpHost for ApiEnv.local', () {
      const env = ApiEnv.local();
      expect(env.httpHost, equals("localhost:8090"));
    });

    testUnit('domain for ApiEnv.prod', () {
      const env = ApiEnv.prod();
      expect(env.domain, equals("meet.proton.me"));
    });

    testUnit('domain for ApiEnv.staging', () {
      const env = ApiEnv.staging();
      expect(env.domain, equals("meet.proton.me"));
    });

    testUnit('domain for ApiEnv.atlas with custom value', () {
      final env = ApiEnv.atlas("testEnv");
      expect(env.domain, equals("meet.testEnv.proton.black"));
    });

    testUnit('domain for ApiEnv.atlas without custom value', () {
      final env = ApiEnv.atlas(null);
      expect(env.domain, equals("meet.proton.black"));
    });

    testUnit('domain for ApiEnv.local', () {
      const env = ApiEnv.local();
      expect(env.domain, equals("localhost"));
    });

    testUnit('baseUrl for ApiEnv.prod', () {
      const env = ApiEnv.prod();
      expect(env.baseUrl, equals("https://meet.proton.me"));
    });

    testUnit('baseUrl for ApiEnv.staging', () {
      const env = ApiEnv.staging();
      expect(env.baseUrl, equals("https://meet.proton.me"));
    });

    testUnit('baseUrl for ApiEnv.atlas with custom value', () {
      final env = ApiEnv.atlas("testEnv");
      expect(env.baseUrl, equals("https://meet.testEnv.proton.black"));
    });

    testUnit('baseUrl for ApiEnv.local', () {
      const env = ApiEnv.local();
      expect(env.baseUrl, equals("https://localhost"));
    });
  });
}
