import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'basic_container.dart';

class HomeShimmer extends StatelessWidget {
  const HomeShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[500]!,
      highlightColor: Colors.grey[300]!,
      enabled: true,
      direction: ShimmerDirection.ltr,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _quickPicksShimmer(),
            const SizedBox(height: 10),
            _contentWidget(),
            _contentWidget(),
          ],
        ),
    );
  }

  Widget _quickPicksShimmer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BasicShimmerContainer(Size(150, 28)),
        const SizedBox(height: 10),
        SizedBox(
          height: 256,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: 12,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: 300,
              crossAxisSpacing: 0,
              mainAxisSpacing: 0,
            ),
            itemBuilder: (_, __) {
              return const Padding(
                padding: EdgeInsets.all(10),
                child: Row(
                  children: [
                    BasicShimmerContainer(Size(44, 44)),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BasicShimmerContainer(Size(150, 14)),
                          SizedBox(height: 5),
                          BasicShimmerContainer(Size(90, 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _contentWidget() {
    return SizedBox(
      height: 285,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BasicShimmerContainer(Size(150, 28)),
          const SizedBox.shrink(),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 5,
              itemBuilder: (_, __) {
                return const SizedBox(
                  width: 160,
                  child: Padding(
                    padding: EdgeInsets.only(top: 10, bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BasicShimmerContainer(Size(160, 160)),
                        SizedBox(height: 8),
                        BasicShimmerContainer(Size(130, 14)),
                        SizedBox(height: 5),
                        BasicShimmerContainer(Size(90, 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          ],
        ),
      ),
    );
  }
}
