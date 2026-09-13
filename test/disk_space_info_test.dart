import 'package:disk_space_info/disk_space_info.dart';
import 'package:test/test.dart';

void main() {
  const DiskSpaceInfo info = DiskSpaceInfo(totalBytes: 1000, freeBytes: 250, usedBytes: 700);

  group('usedFraction', () {
    test('is used over total', () {
      expect(info.usedFraction, closeTo(0.7, 1e-9));
    });

    test('is 0.0 rather than NaN when total is zero', () {
      const DiskSpaceInfo empty = DiskSpaceInfo(totalBytes: 0, freeBytes: 0, usedBytes: 0);
      expect(empty.usedFraction, 0.0);
    });
  });

  group('hasRoomFor', () {
    test('accepts a request that fits', () {
      expect(info.hasRoomFor(250), isTrue);
      expect(info.hasRoomFor(0), isTrue);
    });

    test('rejects a request larger than free space', () {
      expect(info.hasRoomFor(251), isFalse);
    });

    test('applies the safety factor', () {
      expect(info.hasRoomFor(125, safetyFactor: 2.0), isTrue);
      expect(info.hasRoomFor(126, safetyFactor: 2.0), isFalse);
    });

    test('rounds the requirement up, never in the callers favour', () {
      // 200 * 1.3 == 260.0000000000000004 -> 261 after rounding up.
      expect(info.hasRoomFor(200, safetyFactor: 1.3), isFalse);
      // 100 * 2.5 == 250 exactly, which fits.
      expect(info.hasRoomFor(100, safetyFactor: 2.5), isTrue);
    });

    test('throws on caller errors', () {
      expect(() => info.hasRoomFor(-1), throwsArgumentError);
      expect(() => info.hasRoomFor(1, safetyFactor: 0), throwsArgumentError);
      expect(() => info.hasRoomFor(1, safetyFactor: -1), throwsArgumentError);
      expect(() => info.hasRoomFor(1, safetyFactor: double.nan), throwsArgumentError);
      expect(() => info.hasRoomFor(1, safetyFactor: double.infinity), throwsArgumentError);
    });
  });

  test('value equality', () {
    expect(info, const DiskSpaceInfo(totalBytes: 1000, freeBytes: 250, usedBytes: 700));
    expect(info.hashCode, const DiskSpaceInfo(totalBytes: 1000, freeBytes: 250, usedBytes: 700).hashCode);
    expect(info, isNot(const DiskSpaceInfo(totalBytes: 1000, freeBytes: 251, usedBytes: 700)));
  });

  test('toString names every field', () {
    expect(info.toString(), 'DiskSpaceInfo(total: 1000, free: 250, used: 700)');
  });
}
