import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'common_dialog_widget.dart';

class KeyboardShortcutsMenu extends StatelessWidget {
  const KeyboardShortcutsMenu({super.key});

  Widget _buildShortcutRow(
      BuildContext context, String action, String keyLabel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(action,
                  style: Theme.of(context).textTheme.titleSmall)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Theme.of(context).primaryColorLight.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  offset: const Offset(0, 2),
                  blurRadius: 2,
                ),
              ],
            ),
            child: Text(
              keyLabel,
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, Map<String, String> shortcuts) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...shortcuts.entries
              .map((e) => _buildShortcutRow(context, e.key, e.value))
              ,
          const Divider(height: 30),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection(context, "Player Controls", {
          "Play / Pause": "Space",
          "Focus Player Controls (for arrows)": "C",
          "Seek Backward / Forward": "Arrow Left / Right",
          "Volume Down / Up": "Arrow Down / Up",
          "Next Track": "N",
          "Previous Track": "B",
          "Toggle Full Player": "F",
          "Toggle Lyrics": "L",
          "Toggle Queue": "P",
        }),
        _buildSection(context, "Navigation", {
          "Focus Home Screen": "Tab",
          "Focus Search Bar": "S",
          "Focus Side Panel": "M",
          "Unfocus / Close Player / Go Back": "Esc",
          "Show Shortcuts Menu": "?",
        }),
      ],
    );
  }
}

void showKeyboardShortcutsDialog(BuildContext context) {
  if (Get.isDialogOpen ?? false) {
    Get.back();
    return;
  }
  Get.dialog(
    CommonDialog(
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.keyboard),
                SizedBox(width: 10),
                Text("Keyboard Shortcuts",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            const Flexible(
              child: SingleChildScrollView(
                child: SizedBox(width: 450, child: KeyboardShortcutsMenu()),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: Get.back,
                child: const Text("Close",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
