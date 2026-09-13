import 'package:disk_space_info/disk_space_info.dart';
import 'package:test/test.dart';

void main() {
  group('formatBytes binary', () {
    test('formats bytes below a kibibyte without a unit prefix', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
    });

    test('formats kibibytes, mebibytes and gibibytes', () {
      expect(formatBytes(1024), '1.0 KiB');
      expect(formatBytes(1536), '1.5 KiB');
      expect(formatBytes(1024 * 1024), '1.0 MiB');
      expect(formatBytes(72470000000), '67.5 GiB');
    });

    test('honours the decimals argument', () {
      expect(formatBytes(1536, decimals: 0), '2 KiB');
      expect(formatBytes(1536, decimals: 2), '1.50 KiB');
    });
  });

  group('formatBytes decimal', () {
    test('uses SI units when binary is false', () {
      expect(formatBytes(1000, binary: false), '1.0 kB');
      expect(formatBytes(1500000, binary: false), '1.5 MB');
    });
  });

  test('formats negative input by preserving the sign', () {
    expect(formatBytes(-1024), '-1.0 KiB');
  });
}
