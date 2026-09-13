// Compiles and runs tool/layout_probe.c, then asserts that the offsets in
// lib/src/platform_layout.dart match the real system headers.
//
// This is the guard that would have caught the Darwin trap during development:
// `struct statvfs`'s f_bsize is a 1 MiB I/O hint, and using it yields a 256x
// overestimate. Wired into CI, an OS ABI change fails the build instead of
// silently returning a wrong number.
//
// POSIX only; skipped on Windows, where the implementation decodes no struct.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:disk_space_info/src/platform_layout.dart';

void main() {
  // Returning an int from main() does NOT set the process exit code in Dart —
  // it is silently ignored, which would make this check report failures and
  // still go green in CI. The exit code must be set explicitly.
  exit(_run());
}

int _run() {
  if (Platform.isWindows) {
    stdout.writeln('check_layout: skipped on Windows (no struct decoding).');
    return 0;
  }

  final Directory temp = Directory.systemTemp.createTempSync('dsi_probe_');
  final String binary = '${temp.path}${Platform.pathSeparator}layout_probe';

  try {
    final ProcessResult compile = Process.runSync('cc', <String>['-o', binary, 'tool/layout_probe.c']);
    if (compile.exitCode != 0) {
      stderr.writeln('check_layout: failed to compile the probe:\n${compile.stderr}');
      return 1;
    }

    final ProcessResult run = Process.runSync(binary, <String>[]);
    if (run.exitCode != 0) {
      stderr.writeln('check_layout: probe failed:\n${run.stderr}');
      return 1;
    }

    final Map<String, Object?> actual = jsonDecode(run.stdout as String) as Map<String, Object?>;

    final FsLayout? expected = layoutFor(
      isDarwin: Platform.isMacOS || Platform.isIOS,
      pointerSize: sizeOf<IntPtr>(),
    );
    if (expected == null) {
      stderr.writeln('check_layout: no layout registered for this platform.');
      return 1;
    }

    final List<String> problems = <String>[];

    void compare(String label, Object? actualValue, Object? expectedValue) {
      if (actualValue != expectedValue) {
        problems.add('  $label: header says $actualValue, layout says $expectedValue');
      }
    }

    compare('symbol', actual['struct'], expected.symbol);
    compare('unitOffset', actual['unitOffset'], expected.unitOffset);
    compare('unitSize', actual['unitSize'], expected.unitIs64 ? 8 : 4);
    compare('blocksOffset', actual['blocksOffset'], expected.blocksOffset);
    compare('freeOffset', actual['freeOffset'], expected.freeOffset);
    compare('availOffset', actual['availOffset'], expected.availOffset);
    compare('countSize', actual['countSize'], expected.countsAre64 ? 8 : 4);

    final int structSize = actual['structSize']! as int;
    if (expected.bufferBytes < structSize) {
      problems.add('  bufferBytes: $structSize needed, layout allocates ${expected.bufferBytes}');
    }

    if (problems.isNotEmpty) {
      stderr.writeln('check_layout: platform_layout.dart disagrees with the system headers:');
      stderr.writeln(problems.join('\n'));
      return 1;
    }

    stdout.writeln('check_layout: ${actual['struct']} layout matches the system headers.');
    return 0;
  } finally {
    temp.deleteSync(recursive: true);
  }
}
