import 'package:disk_space_info/src/syscall_web.dart';
import 'package:test/test.dart';

void main() {
  test('the web stub reports unknown', () {
    expect(queryNative('/anything'), isNull);
  });
}
