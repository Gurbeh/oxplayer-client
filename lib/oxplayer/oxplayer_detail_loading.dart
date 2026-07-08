import 'package:flutter/material.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/widgets/ox_media_play_button_skeleton.dart';
import 'package:fladder/oxplayer/widgets/ox_skeleton_box.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// Detail page body shown while full item payload is still loading.
class OxDetailLoadingContent extends StatelessWidget {
  final ItemBaseModel item;
  final EdgeInsets padding;

  const OxDetailLoadingContent({
    required this.item,
    required this.padding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    final titleWidth = isPhone ? double.infinity : 360.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: isPhone ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                if (item.name.isNotEmpty) ...[
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: isPhone ? TextAlign.center : TextAlign.start,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  OxSkeletonBox(
                    width: titleWidth,
                    height: 32,
                    borderRadius: FladderTheme.defaultShape.borderRadius,
                  ),
                  const SizedBox(height: 16),
                ],
                const OxMediaPlayButtonSkeleton(),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: isPhone ? WrapAlignment.center : WrapAlignment.start,
                  children: List.generate(
                    3,
                    (_) => const OxSkeletonBox(
                      width: 40,
                      height: 40,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OxSkeletonBox(
                  width: titleWidth,
                  height: 14,
                  borderRadius: FladderTheme.defaultShape.borderRadius,
                ),
                const SizedBox(height: 8),
                OxSkeletonBox(
                  width: titleWidth,
                  height: 14,
                  borderRadius: FladderTheme.defaultShape.borderRadius,
                ),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: isPhone ? 1 : 0.7,
                  alignment: isPhone ? Alignment.center : Alignment.centerLeft,
                  child: const OxSkeletonBox(
                    height: 14,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
