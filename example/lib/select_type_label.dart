import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

/// Controlled dropdown for selecting how many labels to print per row.
/// The parent owns the selected value via [value] and [onChanged].
class LabelPerRowSelector extends StatelessWidget {
  /// Currently selected value (controlled by parent).
  final LabelPerRow value;

  /// Callback khi đổi giá trị.
  final ValueChanged<LabelPerRow> onChanged;

  const LabelPerRowSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final List<DropdownMenuItem<LabelPerRow?>> items = [];

    // Nhóm 1: 1 Tem / Hàng
    items.add(const DropdownMenuItem<LabelPerRow?>(
      value: null,
      enabled: false,
      child: Text(
        '── 1 TEM / HÀNG ──',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF4F46E5),
          fontSize: 11,
        ),
      ),
    ));
    items.addAll(LabelPerRow.values
        .where((item) => !item.name.startsWith('double') && !item.name.startsWith('triple'))
        .map((item) => DropdownMenuItem<LabelPerRow?>(
              value: item,
              child: Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Text(item.title),
              ),
            )));

    // Nhóm 2: 2 Tem / Hàng
    items.add(const DropdownMenuItem<LabelPerRow?>(
      value: null,
      enabled: false,
      child: Text(
        '── 2 TEM / HÀNG ──',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF4F46E5),
          fontSize: 11,
        ),
      ),
    ));
    items.addAll(LabelPerRow.values
        .where((item) => item.name.startsWith('double'))
        .map((item) => DropdownMenuItem<LabelPerRow?>(
              value: item,
              child: Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Text(item.title),
              ),
            )));

    // Nhóm 3: 3 Tem / Hàng
    items.add(const DropdownMenuItem<LabelPerRow?>(
      value: null,
      enabled: false,
      child: Text(
        '── 3 TEM / HÀNG ──',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF4F46E5),
          fontSize: 11,
        ),
      ),
    ));
    items.addAll(LabelPerRow.values
        .where((item) => item.name.startsWith('triple'))
        .map((item) => DropdownMenuItem<LabelPerRow?>(
              value: item,
              child: Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Text(item.title),
              ),
            )));

    return DropdownButtonHideUnderline(
      child: DropdownButton<LabelPerRow?>(
        value: value,
        isExpanded: true,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
        items: items,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
