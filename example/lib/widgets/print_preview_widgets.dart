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
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(buttons[i].label,
                        style: const TextStyle(fontSize: 11)),
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
  final VoidCallback? onPressed;

  const RawPrintButtonData({required this.label, this.onPressed});
}

RawPrintBar buildRawPrintBar({
  required Color color,
  required String title,
  required List<({String label, VoidCallback? onPressed})> buttons,
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

OverlayEntry? _activeNotificationEntry;

void showTopNotification(BuildContext context, String message, {bool isError = true, Color? customBgColor}) {
  // Gỡ bỏ thông báo cũ nếu đang hiển thị
  if (_activeNotificationEntry != null) {
    try {
      _activeNotificationEntry!.remove();
    } catch (_) {}
    _activeNotificationEntry = null;
  }

  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  
  entry = OverlayEntry(
    builder: (context) {
      return _TopNotificationWidget(
        message: message,
        isError: isError,
        customBgColor: customBgColor,
        onDismiss: () {
          if (_activeNotificationEntry == entry) {
            _activeNotificationEntry = null;
          }
          try {
            entry.remove();
          } catch (_) {}
        },
      );
    },
  );
  
  _activeNotificationEntry = entry;
  overlay.insert(entry);
}

class _TopNotificationWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final Color? customBgColor;
  final VoidCallback onDismiss;
  
  const _TopNotificationWidget({
    required this.message,
    required this.isError,
    this.customBgColor,
    required this.onDismiss,
  });
  
  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _yAnimation;
  late Animation<double> _opacityAnimation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    
    _yAnimation = Tween<double>(begin: -60, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    
    _controller.forward();
    
    // Auto dismiss after 2 seconds
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bgColor = widget.customBgColor ?? (widget.isError ? const Color(0xFFF43F5E) : const Color(0xFF0D9488));
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: topPadding + 16 + _yAnimation.value,
          left: 16,
          right: 16,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                widget.isError ? Icons.error_outline : Icons.info_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
