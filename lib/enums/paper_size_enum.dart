enum TicketSize {
  mm58,
  mm80,
}

extension PaperSizeValue on TicketSize {
  int get value {
    switch (this) {
      case TicketSize.mm58:
        return 384; // khổ in 58mm
      case TicketSize.mm80:
        return 576; // khổ in 80mm
    }
  }
}
