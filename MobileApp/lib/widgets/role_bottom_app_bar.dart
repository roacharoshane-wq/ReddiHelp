import 'package:flutter/material.dart';

class RoleBottomBarItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;

  const RoleBottomBarItem({
    required this.icon,
    this.selectedIcon,
    required this.tooltip,
  });
}

class RoleBottomAppBar extends StatelessWidget {
  final List<RoleBottomBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Color barColor;
  final Color selectedCircleColor;
  final Color selectedIconColor;
  final Color unselectedIconColor;

  const RoleBottomAppBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
    this.barColor = const Color(0xFF1F73DA),
    this.selectedCircleColor = Colors.white,
    this.selectedIconColor = const Color(0xFF1F73DA),
    this.unselectedIconColor = const Color(0xFFE8F1FF),
  }) : assert(items.length >= 2);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPadding > 0 ? 8 : 12),
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: barColor.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final selected = index == currentIndex;
            final icon =
                selected ? (item.selectedIcon ?? item.icon) : item.icon;

            return Expanded(
              child: Center(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: item.tooltip,
                  child: Tooltip(
                    message: item.tooltip,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onSelected(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? selectedCircleColor
                                : Colors.transparent,
                          ),
                          child: Icon(
                            icon,
                            color: selected
                                ? selectedIconColor
                                : unselectedIconColor,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
