import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

/// Controlled size selector for cup stickers.
/// Parent owns the selected [value]; [onChanged] fires when the user picks a new size;
/// [onPrint] fires when the user taps the print button.
class CupStickerSizeSelector extends StatelessWidget {
  final CupStickerSize value;
  final ValueChanged<CupStickerSize> onChanged;
  final Future<void> Function(CupStickerSize size) onPrint;

  const CupStickerSizeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        /// Dropdown chọn size
        DropdownButton<CupStickerSize>(
          value: value,
          items: CupStickerSize.defaults.map((size) {
            return DropdownMenuItem(
              value: size,
              child: Text('${size.key} mm'),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),

        const SizedBox(width: 12),

        /// Nút in
        ElevatedButton(
          onPressed: () async => onPrint(value),
          child: const Text('Print Cup Sticker'),
        ),
      ],
    );
  }
}
