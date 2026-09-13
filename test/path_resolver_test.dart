import 'dart:io';

import 'package:disk_space_info/src/path_resolver.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('dsi_path_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('returns an existing directory unchanged', () {
    expect(resolveQueryDirectory(temp.path), temp.resolveSymbolicLinksSync());
  });

  test('walks up to the nearest existing ancestor for a path that does not exist', () {
    final String missing = '${temp.path}${Platform.pathSeparator}a${Platform.pathSeparator}b${Platform.pathSeparator}c.zip';
    expect(resolveQueryDirectory(missing), temp.resolveSymbolicLinksSync());
  });

  test('returns the containing directory for an existing file', () {
    final File file = File('${temp.path}${Platform.pathSeparator}f.txt')..writeAsStringSync('x');
    expect(resolveQueryDirectory(file.path), temp.resolveSymbolicLinksSync());
  });

  test('resolves a relative path to an absolute one', () {
    final String? result = resolveQueryDirectory('.');
    expect(result, isNotNull);
    expect(Directory(result!).isAbsolute, isTrue);
  });

  test('throws on an empty path', () {
    expect(() => resolveQueryDirectory(''), throwsArgumentError);
  });
}
