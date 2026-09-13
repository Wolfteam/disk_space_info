import 'dart:io';

import 'package:disk_space_info/disk_space_info.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('dsi_query_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('reports a plausible reading for a real directory', () {
    final DiskSpaceInfo? info = DiskSpaceInfo.querySync(temp.path);

    expect(info, isNotNull, reason: 'a real temp directory must be queryable');
    expect(info!.totalBytes, greaterThan(0));
    expect(info.freeBytes, greaterThan(0));
    expect(info.freeBytes, lessThanOrEqualTo(info.totalBytes));
    expect(info.usedBytes, lessThanOrEqualTo(info.totalBytes));
    expect(info.freeBytes + info.usedBytes, lessThanOrEqualTo(info.totalBytes));
    expect(info.usedFraction, inInclusiveRange(0.0, 1.0));
  });

  test('resolves a path that does not exist yet', () {
    final String missing = '${temp.path}${Platform.pathSeparator}not${Platform.pathSeparator}here.zip';
    final DiskSpaceInfo? info = DiskSpaceInfo.querySync(missing);

    expect(info, isNotNull);
    expect(info!.freeBytes, greaterThan(0));
  });

  test('agrees with itself across the sync and async entry points', () async {
    final DiskSpaceInfo? sync = DiskSpaceInfo.querySync(temp.path);
    final DiskSpaceInfo? async = await DiskSpaceInfo.query(temp.path);

    expect(sync, isNotNull);
    expect(async, isNotNull);
    expect(async!.totalBytes, sync!.totalBytes);
  });

  test('throws on an empty path', () {
    expect(() => DiskSpaceInfo.querySync(''), throwsArgumentError);
    expect(() => DiskSpaceInfo.query(''), throwsArgumentError);
  });

  test('reports unknown for a path that cannot be resolved', () {
    final String bogus = Platform.isWindows
        ? r'\\?\Volume{00000000-0000-0000-0000-000000000000}\nope'
        : '/proc/nonexistent-device-xyz/deeper';
    expect(() => DiskSpaceInfo.querySync(bogus), returnsNormally);
  });
}
