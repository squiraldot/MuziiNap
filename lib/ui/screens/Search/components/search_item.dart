import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../search_screen_controller.dart';

import '../../../navigator.dart';

class SearchItem extends StatelessWidget {
  final String queryString;
  final bool isHistoryString;
  final int index;
  const SearchItem(
      {super.key, required this.queryString, required this.isHistoryString, required this.index});

  @override
  Widget build(BuildContext context) {
    final searchScreenController = Get.find<SearchScreenController>();
    return Obx(() {
      final isSelected = searchScreenController.historyIndex.value == index;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          selected: isSelected,
          selectedTileColor: Theme.of(context).focusColor,
          selectedColor: Theme.of(context).colorScheme.onSurface,
          contentPadding: const EdgeInsets.only(left: 10, right: 20),
        onTap: () {
        Get.toNamed(ScreenNavigationSetup.searchResultScreen,
            id: ScreenNavigationSetup.id, arguments: queryString);
        searchScreenController.addToHistryQueryList(queryString);
      },
      leading: isHistoryString
          ? const Icon(Icons.history)
          : const Icon(Icons.search),
      minLeadingWidth: 20,
      dense: true,
      title: Text(queryString),
      trailing: SizedBox(
        width: 80,
        child: Row(
          children: [
            isHistoryString
                ? IconButton(
                    iconSize: 18,
                    splashRadius: 18,
                    visualDensity: const VisualDensity(horizontal: -2),
                    onPressed: () {
                      searchScreenController
                          .removeQueryFromHistory(queryString);
                    },
                    icon: Icon(
                      Icons.clear,
                      color: Theme.of(context).textTheme.titleMedium!.color,
                    ),
                  )
                : const SizedBox(
                    width: 40,
                  ),
            IconButton(
              iconSize: 20,
              splashRadius: 18,
              visualDensity: const VisualDensity(horizontal: -2),
              onPressed: () {
                searchScreenController.suggestionInput(queryString);
              },
              icon: Icon(
                Icons.north_west,
                color: Theme.of(context).textTheme.titleMedium!.color,
              ),
            ),
          ],
        ),
      ),
    ));
    });
  }
}
