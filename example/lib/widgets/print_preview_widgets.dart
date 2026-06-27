import 'dart:typed_data';

import 'package:flutter/material.dart';

// ─── Section header ───────────────────────────────────────────────────────────

class PrintSectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const PrintSectionHeader({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Raw dev print bar ────────────────────────────────────────────────────────

class RawPrintBar extends StatelessWidget {
  final Color color;
  final String title;
  final List<RawPrintButtonData> buttons;

  const RawPrintBar({
    super.key,
    required this.color,
    required this.title,
    required this.buttons,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(color: color.withValues(alpha: 0.4), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.developer_mode_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: buttons[i].onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(buttons[i].label,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class RawPrintButtonData {
  final String label;
  final VoidCallback onPressed;

  const RawPrintButtonData({required this.label, required this.onPressed});
}

RawPrintBar buildRawPrintBar({
  required Color color,
  required String title,
  required List<({String label, VoidCallback onPressed})> buttons,
}) {
  return RawPrintBar(
    color: color,
    title: title,
    buttons: buttons
        .map((b) => RawPrintButtonData(label: b.label, onPressed: b.onPressed))
        .toList(),
  );
}

// ─── Label carousel ───────────────────────────────────────────────────────────

class LabelCarousel extends StatelessWidget {
  final List<Uint8List> images;
  final Color accentColor;

  const LabelCarousel({
    super.key,
    required this.images,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < images.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            PrintImageCard(
              bytes: images[i],
              label: 'Tờ ${i + 1}/${images.length}',
              accentColor: accentColor,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Cup sticker carousel ─────────────────────────────────────────────────────

class CupStickerCarousel extends StatelessWidget {
  final List<Uint8List> images;

  const CupStickerCarousel({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < images.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            PrintImageCard(
              bytes: images[i],
              label: 'Nhãn ${i + 1}/${images.length}',
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared image card ────────────────────────────────────────────────────────

class PrintImageCard extends StatelessWidget {
  final Uint8List bytes;
  final String label;
  final Color accentColor;

  const PrintImageCard({
    super.key,
    required this.bytes,
    required this.label,
    this.accentColor = const Color(0xFF0D9488),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: accentColor,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(
            bytes,
            fit: BoxFit.fitWidth,
            filterQuality: FilterQuality.high,
          ),
        ),
      ],
    );
  }
}
