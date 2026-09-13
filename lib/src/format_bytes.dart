const List<String> _binaryUnits = <String>['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
const List<String> _decimalUnits = <String>['B', 'kB', 'MB', 'GB', 'TB', 'PB'];

/// Formats [bytes] for display, e.g. `1.5 GiB` (binary) or `1.6 GB` (decimal).
///
/// Binary units (KiB/MiB/GiB) are the default and match what Linux and macOS
/// report; pass `binary: false` for SI units.
///
/// [decimals] controls the fraction digits used for every unit above bytes;
/// whole bytes are always printed without a fraction.
String formatBytes(int bytes, {int decimals = 1, bool binary = true}) {
  final String sign = bytes < 0 ? '-' : '';
  final int magnitude = bytes.abs();
  final int base = binary ? 1024 : 1000;
  final List<String> units = binary ? _binaryUnits : _decimalUnits;

  if (magnitude < base) {
    return '$sign$magnitude ${units.first}';
  }

  double value = magnitude.toDouble();
  int unitIndex = 0;
  while (value >= base && unitIndex < units.length - 1) {
    value /= base;
    unitIndex++;
  }

  return '$sign${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}
