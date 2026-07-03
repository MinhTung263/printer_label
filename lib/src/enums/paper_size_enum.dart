enum TicketSize {
  /// khổ in 58mm
  mm58,

  /// khổ in 80mm
  mm80,
}

extension PaperSizeValue on TicketSize {
  int get value {
    switch (this) {
      case TicketSize.mm58:
        return 384;
      case TicketSize.mm80:
        return 576;
    }
  }
}
