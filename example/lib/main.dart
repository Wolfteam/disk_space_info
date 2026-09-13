// A bare-bones example: query a few directories and print exactly what the
// library returns.
//
// Runs on Android, iOS, macOS, Windows, Linux and web. On web every reading is
// "unknown", which is the point — the package degrades rather than failing.
import 'dart:io' show Directory;

import 'package:disk_space_info/disk_space_info.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const ExampleApp());
}

/// A labelled path and the reading taken for it.
class Reading {
  /// What the path is, e.g. `Documents`.
  final String label;

  /// The path that was queried.
  final String path;

  /// The reading, or `null` when the platform could not answer.
  final DiskSpaceInfo? info;

  /// Creates a reading.
  const Reading({required this.label, required this.path, required this.info});
}

/// The example application.
class ExampleApp extends StatelessWidget {
  /// Creates the example application.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'disk_space_info',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

/// Shows a reading for each interesting directory on the device.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Reading> _readings = <Reading>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    final List<Reading> readings = <Reading>[];

    for (final (String label, Future<String?> pathFuture) in _candidatePaths()) {
      final String? path = await pathFuture;
      if (path == null) {
        continue;
      }
      readings.add(Reading(label: label, path: path, info: await DiskSpaceInfo.query(path)));
    }

    if (mounted) {
      setState(() {
        _readings = readings;
        _loading = false;
      });
    }
  }

  List<(String, Future<String?>)> _candidatePaths() {
    if (kIsWeb) {
      // There is no filesystem on web; the package reports unknown for any path.
      return <(String, Future<String?>)>[('Any path', Future<String?>.value('/'))];
    }

    return <(String, Future<String?>)>[
      ('Documents', getApplicationDocumentsDirectory().then((Directory d) => d.path)),
      ('Temporary', getTemporaryDirectory().then((Directory d) => d.path)),
      ('Not yet created', Future<String?>.value('${Directory.systemTemp.path}/does/not/exist/yet.zip')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('disk_space_info'),
        actions: <Widget>[IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _readings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (BuildContext context, int index) => _ReadingCard(reading: _readings[index]),
            ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.reading});

  final Reading reading;

  @override
  Widget build(BuildContext context) {
    final DiskSpaceInfo? info = reading.info;
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(reading.label, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(reading.path, style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const Divider(height: 24),
            if (info == null)
              Text('unknown', style: text.bodyLarge)
            else ...<Widget>[
              _Row(label: 'total', value: formatBytes(info.totalBytes)),
              _Row(label: 'free', value: formatBytes(info.freeBytes)),
              _Row(label: 'used', value: '${formatBytes(info.usedBytes)} (${_percent(info.usedFraction)})'),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: info.usedFraction),
              const SizedBox(height: 12),
              Text(
                info.hasRoomFor(150 * 1024 * 1024, safetyFactor: 2.0)
                    ? 'Room for a 150 MiB download (2x safety factor)'
                    : 'Not enough room for a 150 MiB download (2x safety factor)',
                style: text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _percent(double fraction) => '${(fraction * 100).toStringAsFixed(1)}%';
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[Text(label), Text(value)],
      ),
    );
  }
}
