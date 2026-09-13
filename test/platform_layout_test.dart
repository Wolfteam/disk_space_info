import 'package:disk_space_info/src/platform_layout.dart';
import 'package:test/test.dart';

void main() {
  group('darwin statfs layout', () {
    test('matches the verified offsets for struct statfs', () {
      // Verified on macOS 26.5 arm64: sizeof(struct statfs) == 2168,
      // uint32 f_bsize@0, int32 f_iosize@4, uint64 f_blocks@8, f_bfree@16, f_bavail@24.
      expect(darwinStatfsLayout.symbol, 'statfs');
      expect(darwinStatfsLayout.unitOffset, 0);
      expect(darwinStatfsLayout.unitIs64, isFalse);
      expect(darwinStatfsLayout.blocksOffset, 8);
      expect(darwinStatfsLayout.freeOffset, 16);
      expect(darwinStatfsLayout.availOffset, 24);
      expect(darwinStatfsLayout.countsAre64, isTrue);
      expect(darwinStatfsLayout.bufferBytes, greaterThanOrEqualTo(2168));
    });

    test('prefers the INODE64 symbol, which is what x86_64 exports', () {
      // sys/cdefs.h: __DARWIN_ONLY_64_BIT_INO_T is 0 on __x86_64__, so
      // __DARWIN_SUF_64_BIT_INO_T expands to "$INODE64"; on arm64 it is 1 and
      // the suffix is empty. Plain `statfs` on x86_64 is the LEGACY
      // 32-bit-inode function with a different struct, so order matters —
      // getting it wrong yields wrong numbers, not an error.
      expect(darwinStatfsLayout.effectiveLookupSymbols, <String>[r'statfs$INODE64', 'statfs']);
    });
  });

  group('effectiveLookupSymbols', () {
    test('falls back to the plain symbol when no aliases are registered', () {
      expect(posixStatvfsLp64Layout.effectiveLookupSymbols, <String>['statvfs']);
      expect(posixStatvfsIlp32Layout.effectiveLookupSymbols, <String>['statvfs']);
    });
  });

  group('posix statvfs LP64 layout', () {
    test('matches the verified offsets for glibc, musl and bionic', () {
      // sizeof(struct statvfs) == 112; all fields 8 bytes,
      // f_bsize@0, f_frsize@8, f_blocks@16, f_bfree@24, f_bavail@32.
      expect(posixStatvfsLp64Layout.symbol, 'statvfs');
      expect(posixStatvfsLp64Layout.unitOffset, 8);
      expect(posixStatvfsLp64Layout.unitIs64, isTrue);
      expect(posixStatvfsLp64Layout.blocksOffset, 16);
      expect(posixStatvfsLp64Layout.freeOffset, 24);
      expect(posixStatvfsLp64Layout.availOffset, 32);
      expect(posixStatvfsLp64Layout.countsAre64, isTrue);
      expect(posixStatvfsLp64Layout.bufferBytes, greaterThanOrEqualTo(112));
    });
  });

  group('posix statvfs ILP32 layout', () {
    test('matches the verified offsets for 32-bit bionic', () {
      // sizeof(struct statvfs) == 44; 4-byte fields at 0/4/8/12/16.
      expect(posixStatvfsIlp32Layout.symbol, 'statvfs');
      expect(posixStatvfsIlp32Layout.unitOffset, 4);
      expect(posixStatvfsIlp32Layout.unitIs64, isFalse);
      expect(posixStatvfsIlp32Layout.blocksOffset, 8);
      expect(posixStatvfsIlp32Layout.freeOffset, 12);
      expect(posixStatvfsIlp32Layout.availOffset, 16);
      expect(posixStatvfsIlp32Layout.countsAre64, isFalse);
      expect(posixStatvfsIlp32Layout.bufferBytes, greaterThanOrEqualTo(44));
    });
  });

  group('layoutFor', () {
    test('selects statfs on 64-bit darwin', () {
      expect(layoutFor(isDarwin: true, pointerSize: 8), same(darwinStatfsLayout));
    });

    test('returns null on 32-bit darwin, which we do not ship', () {
      expect(layoutFor(isDarwin: true, pointerSize: 4), isNull);
    });

    test('selects the LP64 statvfs layout on 64-bit posix', () {
      expect(layoutFor(isDarwin: false, pointerSize: 8), same(posixStatvfsLp64Layout));
    });

    test('selects the ILP32 statvfs layout on 32-bit posix', () {
      expect(layoutFor(isDarwin: false, pointerSize: 4), same(posixStatvfsIlp32Layout));
    });

    test('returns null for an unknown pointer size', () {
      expect(layoutFor(isDarwin: false, pointerSize: 2), isNull);
    });
  });
}
