import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../screens/Home/home_screen_controller.dart';

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();

    return Obx(
      () => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavItem(
              label: 'Home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              selected: homeScreenController.tabIndex.value == 0,
              onTap: () => homeScreenController.onBottonBarTabSelected(0),
            ),
            _NavItem(
              label: 'Search',
              icon: Icons.search,
              selected: homeScreenController.tabIndex.value == 1,
              onTap: () => homeScreenController.onBottonBarTabSelected(1),
            ),
            _NavItem(
              label: 'Library',
              icon: Icons.library_music_outlined,
              selectedIcon: Icons.library_music,
              selected: homeScreenController.tabIndex.value == 2,
              onTap: () => homeScreenController.onBottonBarTabSelected(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? (selectedIcon ?? icon) : icon,
                size: 28,
                color: foreground,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
