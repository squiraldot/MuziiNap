import '../screens/Search/search_result_screen_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import './content_list_widget_item.dart';

class ContentListWidget extends StatelessWidget {
  const ContentListWidget({
    super.key,
    this.content,
    this.isHomeContent = true,
    this.scrollController,
  });

  final dynamic content;
  final bool isHomeContent;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final isAlbumContent = content.runtimeType.toString() == "AlbumContent";

    return SizedBox(
      height: 285,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  content.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.25,
                      ),
                ),
              ),
              if (!isHomeContent)
                TextButton(
                  onPressed: () {
                    final controller =
                        Get.find<SearchResultScreenController>();
                    controller.viewAllCallback(content.title);
                  },
                  child: Text(
                    "viewAll".tr,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
            ],
          ),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: isAlbumContent
                  ? content.albumList.length
                  : content.playlistList.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (_, index) => SizedBox(
                width: 160,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: ContentListItem(
                    content: isAlbumContent
                        ? content.albumList[index]
                        : content.playlistList[index],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
