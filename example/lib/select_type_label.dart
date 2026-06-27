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
    return DropdownButton<LabelPerRow>(
      value: value,
      underline: Container(height: 1, color: Colors.grey.shade400),
      items: LabelPerRow.values.map((item) {
        return DropdownMenuItem<LabelPerRow>(
          value: item,
          child: Text(item.title),
        );
      }).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
