import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/rust/errors.dart';
import 'package:test/test.dart';

import '../../helper.dart';

void main() {
  testUnit('protonForceUpgradeResponseCodes includes documented API codes', () {
    expect(protonForceUpgradeResponseCodes, contains(5003));
    expect(protonForceUpgradeResponseCodes, contains(5005));
    expect(protonForceUpgradeResponseCodes.length, 2);
  });

  group('indicatesForceUpgrade', () {
    testUnit('is true for force-upgrade API codes regardless of message', () {
      for (final code in protonForceUpgradeResponseCodes) {
        expect(
          ResponseError(
            code: code,
            error: '',
            details: '',
          ).indicatesForceUpgrade,
          isTrue,
          reason: 'code $code with empty strings',
        );
      }
      expect(
        const ResponseError(
          code: 5003,
          error: 'x',
          details: 'y',
        ).indicatesForceUpgrade,
        isTrue,
      );
      expect(
        const ResponseError(
          code: 5005,
          error: '',
          details: '',
        ).indicatesForceUpgrade,
        isTrue,
      );
    });

    testUnit('is false for other codes with empty error and details', () {
      expect(
        const ResponseError(
          code: 0,
          error: '',
          details: '',
        ).indicatesForceUpgrade,
        isFalse,
      );
      expect(
        const ResponseError(
          code: 403,
          error: '',
          details: '',
        ).indicatesForceUpgrade,
        isFalse,
      );
      expect(
        const ResponseError(
          code: 5000,
          error: '',
          details: '',
        ).indicatesForceUpgrade,
        isFalse,
      );
    });

    testUnit('is false for non-upgrade code with arbitrary error text', () {
      expect(
        const ResponseError(
          code: 400,
          error: 'Human verification required',
          details: '{}',
        ).indicatesForceUpgrade,
        isFalse,
      );
    });
  });

  group('detailString', () {
    testUnit('includes code, error, and details on separate lines', () {
      const r = ResponseError(code: 42, error: 'oops', details: 'more');
      expect(
        r.detailString,
        'ResponseError:\n  Code: 42\n  Error: oops\n  Details: more',
      );
    });
  });
}
