import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'disk_space_info_base.dart';
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

/// Queries the filesystem holding [resolvedDirectory], which must already be an
/// absolute, existing directory.
///
/// Returns `null` for every failure: unsupported platform or architecture,
/// missing symbol, failing syscall, or an implausible result.
DiskSpaceInfo? queryNative(String resolvedDirectory) {
  if (Platform.isWindows) {
    return queryWindows(resolvedDirectory);
  }
  return _queryPosix(resolvedDirectory);
}

DiskSpaceInfo? _queryPosix(String resolvedDirectory) {
  final FsLayout? layout = layoutFor(isDarwin: Platform.isMacOS || Platform.isIOS, pointerSize: sizeOf<IntPtr>());
  if (layout == null) {
    return null;
  }

  final _PathStatDart statCall;
  try {
    statCall = _openLibc().lookupFunction<_PathStatNative, _PathStatDart>(layout.symbol);
  } on Object {
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
