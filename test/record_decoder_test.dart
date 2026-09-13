import 'dart:typed_data';

import 'package:disk_space_info/disk_space_info.dart';
import 'package:disk_space_info/src/platform_layout.dart';
import 'package:disk_space_info/src/record_decoder.dart';
import 'package:test/test.dart';

/// Builds a synthetic buffer for [layout] with the given field values.
ByteData _buffer(FsLayout layout, {required int unit, required int blocks, required int free, required int avail}) {
  final ByteData data = ByteData(layout.bufferBytes);

  void writeUnit(int offset, int value) {
    if (layout.unitIs64) {
      data.setUint64(offset, value, Endian.host);
    } else {
      data.setUint32(offset, value, Endian.host);
    }
  }

  void writeCount(int offset, int value) {
    if (layout.countsAre64) {
      data.setUint64(offset, value, Endian.host);
    } else {
      data.setUint32(offset, value, Endian.host);
    }
  }

  writeUnit(layout.unitOffset, unit);
  writeCount(layout.blocksOffset, blocks);
  writeCount(layout.freeOffset, free);
  writeCount(layout.availOffset, avail);
  return data;
}

void main() {
  group('decodeFsRecord', () {
    for (final (String name, FsLayout layout) in <(String, FsLayout)>[
      ('darwin statfs', darwinStatfsLayout),
      ('posix statvfs LP64', posixStatvfsLp64Layout),
      ('posix statvfs ILP32', posixStatvfsIlp32Layout),
    ]) {
      test('decodes a $name buffer', () {
        // 1000 blocks of 4096: 400 available to us, 450 free including the
        // root reserve, so 550 blocks are genuinely used.
        final ByteData data = _buffer(layout, unit: 4096, blocks: 1000, free: 450, avail: 400);
        final DiskSpaceInfo? info = decodeFsRecord(data, layout);

        expect(info, isNotNull);
        expect(info!.totalBytes, 1000 * 4096);
        expect(info.freeBytes, 400 * 4096, reason: 'free must use f_bavail, not f_bfree');
        expect(info.usedBytes, 550 * 4096, reason: 'used must be blocks - bfree, matching df');
      });

      test('$name: free plus used may be below total', () {
        final ByteData data = _buffer(layout, unit: 4096, blocks: 1000, free: 450, avail: 400);
        final DiskSpaceInfo info = decodeFsRecord(data, layout)!;
        expect(info.freeBytes + info.usedBytes, lessThan(info.totalBytes));
      });

      test('$name: returns null when the unit is zero', () {
        final ByteData data = _buffer(layout, unit: 0, blocks: 1000, free: 450, avail: 400);
        expect(decodeFsRecord(data, layout), isNull);
      });

      test('$name: returns null when free blocks exceed total blocks', () {
        final ByteData data = _buffer(layout, unit: 4096, blocks: 10, free: 999, avail: 999);
        expect(decodeFsRecord(data, layout), isNull);
      });
    }

    test('returns null when the product overflows a signed 64-bit int', () {
      final ByteData data = _buffer(posixStatvfsLp64Layout, unit: 1 << 32, blocks: 1 << 32, free: 0, avail: 0);
      expect(decodeFsRecord(data, posixStatvfsLp64Layout), isNull);
    });

    test('returns null when a 64-bit count reads as negative', () {
      final ByteData data = ByteData(posixStatvfsLp64Layout.bufferBytes);
      data.setUint64(posixStatvfsLp64Layout.unitOffset, 4096, Endian.host);
      data.setUint64(posixStatvfsLp64Layout.blocksOffset, 0xFFFFFFFFFFFFFFFF, Endian.host);
      expect(decodeFsRecord(data, posixStatvfsLp64Layout), isNull);
    });
  });

  group('buildFromWindowsValues', () {
    test('uses the quota-aware free value', () {
      final DiskSpaceInfo? info = buildFromWindowsValues(freeToCaller: 250, totalBytes: 1000, totalFree: 300);

      expect(info, isNotNull);
      expect(info!.freeBytes, 250, reason: 'must use lpFreeBytesAvailableToCaller');
      expect(info.totalBytes, 1000);
      expect(info.usedBytes, 700, reason: 'used is total minus lpTotalNumberOfFreeBytes');
    });

    test('returns null when a value reads as negative', () {
      expect(buildFromWindowsValues(freeToCaller: -1, totalBytes: 1000, totalFree: 300), isNull);
    });

    test('returns null when free exceeds total', () {
      expect(buildFromWindowsValues(freeToCaller: 5, totalBytes: 10, totalFree: 99), isNull);
    });
  });
}
