# disk_space_info

[![pub package](https://img.shields.io/pub/v/disk_space_info.svg)](https://pub.dev/packages/disk_space_info)
[![CI](https://github.com/Wolfteam/disk_space_info/actions/workflows/ci.yaml/badge.svg)](https://github.com/Wolfteam/disk_space_info/actions/workflows/ci.yaml)
[![pub points](https://img.shields.io/pub/points/disk_space_info)](https://pub.dev/packages/disk_space_info/score)

Free, total and used disk space for **any path**, on Android, iOS, macOS, Windows and Linux.

Pure Dart via `dart:ffi` — **no native build configuration**. There is no `android/`, `ios/`,
`macos/`, `windows/` or `linux/` directory, so adding this package brings no Gradle, Xcode,
CocoaPods, SwiftPM or CMake surface into your app, and **no permissions on any platform**.

| Platform | How | Notes |
|---|---|---|
| macOS, iOS | `statfs` | Not `statvfs` — see [Why `statfs` on Darwin](#why-statfs-on-darwin) |
| Linux, Android | `statvfs` | Includes 32-bit ABIs (`armeabi-v7a`) |
| Windows | `GetVolumePathNameW` + `GetDiskFreeSpaceExW` | Quota-aware |
| Web | — | Always reports unknown (`null`) |

## Usage

```dart
import 'package:disk_space_info/disk_space_info.dart';

final info = await DiskSpaceInfo.query('/path/to/somewhere');

if (info == null) {
  // Unknown — proceed anyway and let the write fail if it must.
} else {
  print(formatBytes(info.freeBytes));      // 75.6 GiB
  print(info.usedFraction);                // 0.918

  // Extracting an archive needs room for the archive AND its contents.
  if (info.hasRoomFor(archiveBytes, safetyFactor: 2.0)) {
    // ...
  }
}
```

`querySync` is also available — the underlying call is a single syscall taking microseconds, so
there is no I/O to await. `query` exists for `Future`-shaped call sites.

The path **need not exist**. Resolution walks up to the nearest existing ancestor directory, so you
can ask about a file you are about to create.

## No permissions required

Not on any platform. No Android manifest entries, no iOS or macOS `Info.plist` keys, no
entitlements, no runtime permission requests.

Storage permissions govern access to a *path*, not querying space, and this package is designed for
directories your app already owns (`path_provider`'s documents or cache directory). Some other
packages ask for `READ_EXTERNAL_STORAGE` to do this; it is unnecessary.

## Apple privacy manifest — action required for App Store submission

`statfs`/`statvfs` are [required-reason APIs][rr] under `NSPrivacyAccessedAPICategoryDiskSpace`.
Since 1 May 2024, App Store Connect rejects apps that use them without a declaration.

Because this package is pure Dart it compiles **into your app binary** and ships no resource bundle
of its own, so it cannot declare this on your behalf. Add the following to your app's
`ios/Runner/PrivacyInfo.xcprivacy` (and the macOS equivalent):

```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
      <string>E174.1</string>
    </array>
  </dict>
</array>
```

Reason `E174.1` is *"Declare this reason to check whether there is sufficient disk space to write
files."* — exactly what this package does.

[rr]: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api

## Semantics worth knowing

**`freeBytes` is deliberately conservative.** It may under-report, never over-report:

- Linux and Android exclude blocks reserved for root (~5% on ext4).
- Apple platforms exclude *purgeable* space — caches and offloadable iCloud files the system would
  evict under write pressure. On a device with plenty of space the true figure can be ~2x higher,
  but the two converge as the disk fills, which is when the number actually matters.
- Windows respects per-user disk quotas.

Treat it as a floor, never a guarantee: space can vanish between the query and the write.

**`freeBytes + usedBytes` may be less than `totalBytes`.** The gap is space that exists but that you
cannot write — root-reserved blocks on Linux, and sibling volumes sharing an APFS container on
macOS.

**`usedBytes` counts the whole APFS container.** macOS puts the system, data, VM and preboot volumes
in one container and `statfs` reports container-level counts, so on macOS this is the sum across all
of them rather than your volume alone — it will read higher than `df`'s per-volume `Used` column. On
single-volume filesystems (ext4, NTFS, HFS+) it matches `df`. Gate decisions on `freeBytes`, which is
container-level too and is what genuinely limits a write.

**`null` means unknown, never zero.** An unreadable path, an unsupported platform, or a failing
syscall all yield `null`. A precheck that cannot get an answer should let the operation proceed and
handle the write failure, rather than blocking on a number it does not have.

## Why `statfs` on Darwin

Both of these are easy to get wrong, and most implementations do:

1. **`struct statvfs`'s `f_bsize` on Darwin is a 1 MiB I/O hint, not a block size.** Multiplying by
   it yields a **256x overestimate** — 18 TB reported on a 72 GB volume. `struct statfs` keeps that
   hint in `f_iosize`, out of the way.
2. **Darwin's `fsblkcnt_t` is a 32-bit `unsigned int`**, so `struct statvfs` block counts silently
   **wrap above 16 TiB** with no error returned.

`statfs` avoids both: 64-bit counts, and `f_bsize` means what it says.

There is a third trap, in the **symbol name**. Darwin renames `statfs` per architecture
(`sys/cdefs.h`): `__DARWIN_ONLY_64_BIT_INO_T` is 0 on `__x86_64__`, so the 64-bit-inode entry point
is exported as **`statfs$INODE64`**, while on arm64 the macro is 1 and the symbol is plain
**`statfs`**. Looking up only `statfs` fails outright on Intel Macs — and plain `statfs` there is the
*legacy* 32-bit-inode function with a different struct, so resolving it would give wrong numbers
rather than an error. This package tries `statfs$INODE64` first and falls back to `statfs`.

A CI job compiles a C probe on every run and asserts the offsets in
`lib/src/platform_layout.dart` still match the system headers, so an OS ABI change fails the build
rather than returning a wrong number. The matrix runs Darwin on both arm64 and x86_64 — the Intel leg
is what caught the symbol-suffix bug.

## Example app

[`example/`](example) is a Flutter app that runs on **all six platforms** and shows a reading for the
documents directory, the temporary directory, and a file that does not exist yet:

```bash
cd example
flutter run              # or: -d macos / -d windows / -d linux / -d chrome
```

On web every card reads `unknown` — deliberately, since there is no filesystem to measure.

Its integration tests double as the package's on-device verification:

```bash
cd example
flutter test integration_test -d macos     # or -d windows, an emulator, a simulator
```

In CI these run **on demand**, not on every push — an Android emulator takes ~16 minutes, so gating
every commit on it is not worth the wait. Trigger them from the Actions tab or with:

```bash
gh workflow run integration.yaml                                # all platforms
gh workflow run integration.yaml -f android=false               # all but Android
gh workflow run integration.yaml -f desktop=false -f ios=false  # Android only
```

Every push still runs the unit tests, which exercise the real syscalls on Linux (x64 and arm64),
macOS (arm64 and x86_64) and Windows.

## Releasing

Publishing is automated: pushing a `v`-prefixed tag triggers
[`publish.yml`](.github/workflows/publish.yml), which authenticates to pub.dev over OIDC — there is
no token to store.

1. Bump `version:` in `pubspec.yaml`
2. Add the matching section to `CHANGELOG.md`
3. Commit, then tag — **the tag must match the pubspec version** or pub.dev rejects it:

```bash
git tag v0.1.1
git push origin v0.1.1
```

## License

MIT
