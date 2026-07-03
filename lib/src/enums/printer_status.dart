/// Represents the physical or operational status of a printer.
enum PrinterStatus {
  normal('normal'),
  headOpened('headOpened'),
  paperJam('paperJam'),
  outOfPaper('outOfPaper'),
  outOfRibbon('outOfRibbon'),
  pause('pause'),
  printing('printing'),
  offline('offline'),
  unknown('unknown');

  const PrinterStatus(this.value);
  final String value;

  static PrinterStatus fromValue(String? value) {
    if (value == null) return PrinterStatus.unknown;
    return PrinterStatus.values.firstWhere(
      (e) => e.value.toLowerCase() == value.toLowerCase(),
      orElse: () => PrinterStatus.unknown,
    );
  }
}
