import 'package:flutter_test/flutter_test.dart';

import 'package:healthyfast/providers/fasting_provider.dart';

void main() {
  group('FastingProtocol', () {
    test('presets contain expected protocols', () {
      expect(FastingProtocol.presets.length, 5);
      expect(FastingProtocol.presets.first.label, '16:8');
      expect(FastingProtocol.presets.first.hours, 16);
    });

    test('custom label formats days and hours', () {
      expect(FastingProtocol.custom(60).label, '2d 12h');
      expect(FastingProtocol.custom(48).label, '2d');
      expect(FastingProtocol.custom(20).label, '20h');
    });
  });

  group('FastingProvider.editStartTime', () {
    test('ignores edit when not fasting', () async {
      final fp = FastingProvider();
      await fp.editStartTime(DateTime.now().subtract(const Duration(hours: 2)));
      expect(fp.startTime, isNull);
      expect(fp.isFasting, isFalse);
    });
  });
}
