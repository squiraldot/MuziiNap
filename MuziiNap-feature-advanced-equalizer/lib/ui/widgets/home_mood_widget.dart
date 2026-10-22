import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/home_mood.dart';
import '../screens/Home/mood_browse_screen.dart';

class HomeMoodWidget extends StatelessWidget {
  const HomeMoodWidget({
    super.key,
    required this.moods,
    this.scrollController,
  });

  final List<HomeMood> moods;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    if (moods.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mood & Moments',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 72,
          child: ListView.separated(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: moods.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) {
              final mood = moods[index];
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Get.to(() => MoodBrowseScreen(mood: mood)),
                child: SizedBox(
                  width: 128,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: mood.thumbnailUrl == null
                            ? Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.auto_awesome,
                                  size: 30,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              )
                            : Image.network(
                                mood.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                ),
                              ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.75),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            mood.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
