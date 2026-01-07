import 'package:flutter/material.dart';
import 'package:printer_label/enums/label_per_row_enum.dart';

class LabelPerRowSelector extends StatefulWidget {
  /// Giá trị ban đầu
  final LabelPerRow initialValue;

  /// Callback khi đổi
  final ValueChanged<LabelPerRow> onChanged;

  const LabelPerRowSelector({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<LabelPerRowSelector> createState() => _LabelPerRowSelectorState();
}

class _LabelPerRowSelectorState extends State<LabelPerRowSelector> {
  late LabelPerRow _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<LabelPerRow>(
      value: _selected,
      underline: Container(
        height: 1,
        color: Colors.grey.shade400,
      ),
      items: LabelPerRow.values.map((item) {
        return DropdownMenuItem<LabelPerRow>(
          value: item,
          child: Text(item.title),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selected = value);
        widget.onChanged(value);
      },
    );
  }
}
