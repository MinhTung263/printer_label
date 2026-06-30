import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

/// Controlled size selector for cup stickers.
/// Parent owns the selected [value]; [onChanged] fires when the user picks a new size;
/// [onPrint] fires when the user taps the print button.
class CupStickerSizeSelector extends StatefulWidget {
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
  State<CupStickerSizeSelector> createState() => _CupStickerSizeSelectorState();
}

class _CupStickerSizeSelectorState extends State<CupStickerSizeSelector> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        /// Dropdown chọn size
        DropdownButton<CupStickerSize>(
          value: widget.value,
          items: CupStickerSize.defaults.map((size) {
            return DropdownMenuItem(
              value: size,
              child: Text('${size.key} mm'),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) widget.onChanged(v);
          },
        ),

        const SizedBox(width: 12),

        /// Nút in
        ElevatedButton.icon(
          onPressed: _isLoading
              ? null
              : () async {
                  setState(() => _isLoading = true);
                  try {
                    await widget.onPrint(widget.value);
                  } finally {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  }
                },
          icon: _isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                  ),
                )
              : const Icon(Icons.print, size: 16),
          label: Text(_isLoading ? 'Đang in...' : 'In tem'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D9488),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
