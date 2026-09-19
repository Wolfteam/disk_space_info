// Turns `pana --json` output into a GitHub Actions step summary, so the score
// is visible on the run page instead of buried in a job log.
//
//   dart pub global run pana --no-warning --json . > pana.json
//   dart run tool/pana_summary.dart pana.json 20 >> "$GITHUB_STEP_SUMMARY"
//
// The second argument is the maximum number of points that may be missing
// before this exits non-zero, mirroring pana's own --exit-code-threshold.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: pana_summary.dart <pana.json> [threshold]');
    exit(64);
  }

  final int threshold = args.length > 1 ? int.parse(args[1]) : 0;

  final Map<String, Object?> report;
  try {
    report = jsonDecode(File(args.first).readAsStringSync()) as Map<String, Object?>;
  } on Object catch (e) {
    stderr.writeln('pana_summary: could not read ${args.first}: $e');
    exit(1);
  }

  final Map<String, Object?> scores = (report['scores'] as Map<String, Object?>?) ?? <String, Object?>{};
  final int granted = (scores['grantedPoints'] as int?) ?? 0;
  final int max = (scores['maxPoints'] as int?) ?? 0;
  final int missing = max - granted;

  final StringBuffer out = StringBuffer()
    ..writeln('## pana score: $granted / $max')
    ..writeln()
    ..writeln('| | Section | Points |')
    ..writeln('|---|---|---|');

  final List<Object?> sections = ((report['report'] as Map<String, Object?>?)?['sections'] as List<Object?>?) ?? <Object?>[];

  for (final Object? raw in sections) {
    final Map<String, Object?> section = raw! as Map<String, Object?>;
    final int sectionGranted = (section['grantedPoints'] as int?) ?? 0;
    final int sectionMax = (section['maxPoints'] as int?) ?? 0;
    final String icon = sectionGranted == sectionMax ? '✅' : '⚠️';
    out.writeln('| $icon | ${section['title']} | $sectionGranted/$sectionMax |');
  }

  final List<Object?> tags = (report['tags'] as List<Object?>?) ?? <Object?>[];
  final List<String> platforms = <String>[
    for (final Object? tag in tags)
      if (tag is String && tag.startsWith('platform:')) tag.substring('platform:'.length),
  ];
  if (platforms.isNotEmpty) {
    out
      ..writeln()
      ..writeln('**Platforms:** ${platforms.join(', ')}');
  }
  if (tags.contains('is:wasm-ready')) {
    out.writeln('**WASM ready:** yes');
  }

  stdout.write(out);

  if (missing > threshold) {
    stderr.writeln('pana_summary: missing $missing points, which exceeds the threshold of $threshold.');
    exit(1);
  }
}
