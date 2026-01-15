enum PaperSize {
  mm58,
  mm80,
}

extension PaperSizeValue on PaperSize {
  int get value {
    switch (this) {
      case PaperSize.mm58:
        return 58;
      case PaperSize.mm80:
        return 80;
    }
  }
}
