// Runs on a real device, emulator or desktop host. Asserts invariants only —
// never absolute byte counts, which differ per machine and per run.
import 'package:disk_space_info/disk_space_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports a plausible reading for the documents directory', (WidgetTester tester) async {
    final String path = (await getApplicationDocumentsDirectory()).path;
    final DiskSpaceInfo? info = await DiskSpaceInfo.query(path);

    expect(info, isNotNull, reason: 'the app documents directory must be queryable');
    expect(info!.totalBytes, greaterThan(0));
    expect(info.freeBytes, greaterThan(0));
    expect(info.freeBytes, lessThanOrEqualTo(info.totalBytes));
    expect(info.usedBytes, lessThanOrEqualTo(info.totalBytes));
    expect(info.freeBytes + info.usedBytes, lessThanOrEqualTo(info.totalBytes));
    expect(info.usedFraction, inInclusiveRange(0.0, 1.0));
  });

  testWidgets('resolves a file that does not exist yet', (WidgetTester tester) async {
    final String path = '${(await getApplicationDocumentsDirectory()).path}/not/created/yet.zip';
    final DiskSpaceInfo? info = await DiskSpaceInfo.query(path);

    expect(info, isNotNull);
    expect(info!.freeBytes, greaterThan(0));
  });

  testWidgets('sync and async entry points agree', (WidgetTester tester) async {
    final String path = (await getApplicationDocumentsDirectory()).path;

    expect(DiskSpaceInfo.querySync(path)!.totalBytes, (await DiskSpaceInfo.query(path))!.totalBytes);
  });

  testWidgets('an empty path is a caller error', (WidgetTester tester) async {
    expect(() => DiskSpaceInfo.querySync(''), throwsArgumentError);
  });
}
