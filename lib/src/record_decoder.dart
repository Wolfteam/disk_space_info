import 'dart:typed_data';

import 'disk_space_info_base.dart';
import 'platform_layout.dart';

/// Multiplies [a] by [b], returning `null` on overflow or negative input.
///
/// The operating system reports unsigned 64-bit quantities while Dart's `int`
/// is signed 64-bit, so a mis-decoded buffer can produce values that are
/// nonsensical rather than merely large. `null` is the right answer for a
/// reading that cannot be true.
int? _checkedProduct(int a, int b) {
  if (a < 0 || b < 0) {
    return null;
  }
  if (a == 0 || b == 0) {
    return 0;
  }

  final int product = a * b;
  if (product < 0 || product ~/ a != b) {
    return null;
  }
  return product;
}

int _readField(ByteData data, int offset, bool is64) =>
    is64 ? data.getInt64(offset, Endian.host) : data.getUint32(offset, Endian.host);

/// Decodes a `statfs`/`statvfs` result buffer into a [DiskSpaceInfo].
///
/// Returns `null` when the buffer cannot describe a real filesystem: a zero
/// block size, counts that read as negative, free blocks exceeding total
/// blocks, or a product that overflows.
///
/// `freeBytes` comes from `f_bavail` (available to an unprivileged process),
/// never `f_bfree`. `usedBytes` is `(f_blocks - f_bfree) * unit`, which is what
/// `df`, Finder and File Explorer report.
DiskSpaceInfo? decodeFsRecord(ByteData data, FsLayout layout) {
  final int unit = _readField(data, layout.unitOffset, layout.unitIs64);
  if (unit <= 0) {
    return null;
  }

  final int blocks = _readField(data, layout.blocksOffset, layout.countsAre64);
  final int freeBlocks = _readField(data, layout.freeOffset, layout.countsAre64);
  final int availBlocks = _readField(data, layout.availOffset, layout.countsAre64);

  if (blocks < 0 || freeBlocks < 0 || availBlocks < 0) {
    return null;
  }
  if (freeBlocks > blocks || availBlocks > blocks) {
    return null;
  }

  final int? total = _checkedProduct(blocks, unit);
  final int? free = _checkedProduct(availBlocks, unit);
  final int? used = _checkedProduct(blocks - freeBlocks, unit);

  if (total == null || free == null || used == null) {
    return null;
  }

  return DiskSpaceInfo(totalBytes: total, freeBytes: free, usedBytes: used);
}

/// Builds a [DiskSpaceInfo] from the three `GetDiskFreeSpaceExW` outputs.
///
/// [freeToCaller] is `lpFreeBytesAvailableToCaller`, which respects per-user
/// disk quotas and is therefore what this process may actually write.
/// [totalFree] is `lpTotalNumberOfFreeBytes`, used only to derive
/// [DiskSpaceInfo.usedBytes] so the figure matches File Explorer.
///
/// Returns `null` when any value reads as negative — the Win32 values are
/// unsigned 64-bit and Dart's `int` is signed — or when free space exceeds the
/// volume total.
DiskSpaceInfo? buildFromWindowsValues({required int freeToCaller, required int totalBytes, required int totalFree}) {
  if (freeToCaller < 0 || totalBytes < 0 || totalFree < 0) {
    return null;
  }
  if (freeToCaller > totalBytes || totalFree > totalBytes) {
    return null;
  }

  return DiskSpaceInfo(totalBytes: totalBytes, freeBytes: freeToCaller, usedBytes: totalBytes - totalFree);
}
