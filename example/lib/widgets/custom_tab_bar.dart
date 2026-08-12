import 'package:flutter/material.dart';

class CustomTabBar extends StatelessWidget {
  final TabController controller;
  final List<Widget> tabs;
  final bool isScrollable;
  final EdgeInsetsGeometry? margin;

  const CustomTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.isScrollable = false,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: TabBar(
          controller: controller,
          isScrollable: isScrollable,
          tabAlignment: isScrollable ? TabAlignment.start : TabAlignment.fill,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade600,
          labelPadding: EdgeInsets.symmetric(horizontal: isScrollable ? 16 : 4),
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: tabs,
        ),
      ),
    );
  }
}

class CustomTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Axis direction;
  final double? height;

  const CustomTab({
    super.key,
    required this.icon,
    required this.label,
    this.direction = Axis.horizontal,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isVertical = direction == Axis.vertical;
    return Tab(
      height: height ?? (isVertical ? 60 : 54),
      child: Flex(
        direction: direction,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isVertical ? 24 : 22),
          SizedBox(
            width: isVertical ? 0 : 8,
            height: isVertical ? 4 : 0,
          ),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: isVertical ? 2 : 1,
              style: TextStyle(
                fontSize: isVertical ? 11.5 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
