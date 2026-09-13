import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'disk_space_info_base.dart';
import 'path_resolver.dart';
import 'platform_layout.dart';
import 'record_decoder.dart';

typedef _PathStatNative = Int32 Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _PathStatDart = int Function(Pointer<Utf8>, Pointer<Uint8>);

typedef _GetVolumePathNameNative = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _GetVolumePathNameDart = int Function(Pointer<Utf16>, Pointer<Utf16>, int);

typedef _GetDiskFreeSpaceExNative = Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetDiskFreeSpaceExDart = int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

/// `MAX_PATH` plus room for the terminating null.
const int _maxPathChars = 261;

/// Opens libc for the running platform.
///
/// Android must name the library explicitly: the VM resolves
/// `DynamicLibrary.process()` through `RTLD_DEFAULT`, which fails to expose
/// libc symbols on Android (dart-lang/sdk#53249).
DynamicLibrary _openLibc() => Platform.isAndroid ? DynamicLibrary.open('libc.so') : DynamicLibrary.process();

/// Queries the filesystem holding [path].
///
/// [path] is resolved to an absolute, existing directory first (see
/// [resolveQueryDirectory]), so it need not exist yet.
///
/// This is the native half of the conditional import in
/// `disk_space_info_base.dart`; `syscall_web.dart` is the other half. Path
/// resolution lives here rather than in the caller because it needs `dart:io`,
/// which is unavailable on web.
///
/// Returns `null` for every failure: an unresolvable path, an unsupported
/// platform or architecture, a missing symbol, a failing syscall, or an
/// implausible result.
DiskSpaceInfo? queryNative(String path) {
  final String? resolvedDirectory = resolveQueryDirectory(path);
  if (resolvedDirectory == null) {
    return null;
  }

  if (Platform.isWindows) {
    return queryWindows(resolvedDirectory);
  }
  return _queryPosix(resolvedDirectory);
}

/// Resolves the first of [FsLayout.effectiveLookupSymbols] that libc exports.
///
/// Darwin exports the 64-bit-inode `statfs` under different names per
/// architecture — `statfs$INODE64` on x86_64, plain `statfs` on arm64 — so the
/// candidates are tried in order rather than assuming one name. Getting this
/// wrong is not a graceful failure: plain `statfs` on x86_64 is the legacy
/// 32-bit-inode function, whose struct layout differs from the one decoded
/// here.
_PathStatDart? _lookupStat(FsLayout layout) {
  final DynamicLibrary libc;
  try {
    libc = _openLibc();
  } on Object {
    return null;
  }

  for (final String symbol in layout.effectiveLookupSymbols) {
    try {
      return libc.lookupFunction<_PathStatNative, _PathStatDart>(symbol);
    } on Object {
      // Not exported on this architecture; try the next candidate.
      continue;
    }
  }
  return null;
}

DiskSpaceInfo? _queryPosix(String resolvedDirectory) {
  final FsLayout? layout = layoutFor(isDarwin: Platform.isMacOS || Platform.isIOS, pointerSize: sizeOf<IntPtr>());
  if (layout == null) {
    return null;
  }

  final _PathStatDart? statCall = _lookupStat(layout);
  if (statCall == null) {
    return null;
  }

  final Pointer<Uint8> buffer = calloc<Uint8>(layout.bufferBytes);
  final Pointer<Utf8> path = resolvedDirectory.toNativeUtf8(allocator: calloc);
  try {
    if (statCall(path, buffer) != 0) {
      return null;
    }

    final ByteData data = buffer.asTypedList(layout.bufferBytes).buffer.asByteData();
    return decodeFsRecord(data, layout);
  } on Object {
    return null;
  } finally {
    calloc.free(buffer);
    calloc.free(path);
  }
}

/// Queries the filesystem holding [resolvedDirectory] on Windows.
///
/// Two calls rather than one: `GetVolumePathNameW` maps an arbitrary path to
/// the volume that actually hosts it, which is what makes junction points and
/// mounted folders report the correct volume. Passing the path straight to
/// `GetDiskFreeSpaceExW` would report whichever volume the path string appears
/// to name.
///
/// Free space comes from `lpFreeBytesAvailableToCaller`, which respects
/// per-user disk quotas, rather than `lpTotalNumberOfFreeBytes`.
DiskSpaceInfo? queryWindows(String resolvedDirectory) {
  final DynamicLibrary kernel32;
  try {
    kernel32 = DynamicLibrary.open('kernel32.dll');
  } on Object {
    return null;
  }

  final _GetVolumePathNameDart getVolumePathName;
  final _GetDiskFreeSpaceExDart getDiskFreeSpaceEx;
  try {
    getVolumePathName = kernel32.lookupFunction<_GetVolumePathNameNative, _GetVolumePathNameDart>(
      'GetVolumePathNameW',
    );
    getDiskFreeSpaceEx = kernel32.lookupFunction<_GetDiskFreeSpaceExNative, _GetDiskFreeSpaceExDart>(
      'GetDiskFreeSpaceExW',
    );
  } on Object {
    return null;
  }

  final Pointer<Utf16> path = resolvedDirectory.toNativeUtf16(allocator: calloc);
  final Pointer<Utf16> volume = calloc<Uint16>(_maxPathChars).cast<Utf16>();
  final Pointer<Uint64> freeToCaller = calloc<Uint64>();
  final Pointer<Uint64> totalBytes = calloc<Uint64>();
  final Pointer<Uint64> totalFree = calloc<Uint64>();

  try {
    if (getVolumePathName(path, volume, _maxPathChars) == 0) {
      return null;
    }
    if (getDiskFreeSpaceEx(volume, freeToCaller, totalBytes, totalFree) == 0) {
      return null;
    }

    return buildFromWindowsValues(
      freeToCaller: freeToCaller.value,
      totalBytes: totalBytes.value,
      totalFree: totalFree.value,
    );
  } on Object {
    return null;
  } finally {
    calloc.free(path);
    calloc.free(volume);
    calloc.free(freeToCaller);
    calloc.free(totalBytes);
    calloc.free(totalFree);
  }
}
