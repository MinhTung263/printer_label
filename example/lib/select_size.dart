import 'package:flutter/material.dart';
import 'package:printer_label/enums/enum.src.dart';

class CupStickerSizeSelector extends StatefulWidget {
  final Future<void> Function(CupStickerSize size) onPrint;

  const CupStickerSizeSelector({
    super.key,
    required this.onPrint,
  });

  @override
  State<CupStickerSizeSelector> createState() => _CupStickerSizeSelectorState();
}

class _CupStickerSizeSelectorState extends State<CupStickerSizeSelector> {
  CupStickerSize _selectedSize = CupStickerSize.s50x30;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        /// Dropdown chọn size
        DropdownButton<CupStickerSize>(
          value: _selectedSize,
          items: CupStickerSize.defaults.map((size) {
            return DropdownMenuItem(
              value: size,
              child: Text('${size.key} mm'),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedSize = value);
            }
          },
        ),

        const SizedBox(width: 12),

        /// Nút in
        ElevatedButton(
          onPressed: () async {
            await widget.onPrint(_selectedSize);
          },
          child: const Text('Print Cup Sticker'),
        ),
      ],
    );
  }
}
