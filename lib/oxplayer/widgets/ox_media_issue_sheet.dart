import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/models/ox_media_issue_category.dart';
import 'package:fladder/oxplayer/models/ox_media_issue_target.dart';
import 'package:fladder/oxplayer/providers/ox_media_issue_context.dart';
import 'package:fladder/oxplayer/providers/ox_media_issue_submit.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/screens/shared/outlined_text_field.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/modal_side_sheet.dart';

Future<void> showOxMediaIssueSheet({
  required BuildContext context,
  required OxMediaIssueTarget target,
}) async {
  if (AdaptiveLayout.viewSizeOf(context) != ViewSize.phone) {
    await showModalSideSheet(
      context,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(context.localized.oxplayerReportIssueTitle),
          Text(target.displayTitle, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      content: OxMediaIssueSheet(target: target),
    );
  } else {
    await showBottomSheetPill(
      context: context,
      content: (context, scrollController) => OxMediaIssueSheet(
        target: target,
        scrollController: scrollController,
      ),
    );
  }
}

class OxMediaIssueSheet extends ConsumerStatefulWidget {
  final OxMediaIssueTarget target;
  final ScrollController? scrollController;

  const OxMediaIssueSheet({
    required this.target,
    this.scrollController,
    super.key,
  });

  @override
  ConsumerState<OxMediaIssueSheet> createState() => _OxMediaIssueSheetState();
}

class _OxMediaIssueSheetState extends ConsumerState<OxMediaIssueSheet> {
  OxMediaIssueCategory? _selected;
  final _otherController = TextEditingController();
  final _otherFocus = FocusNode();

  @override
  void dispose() {
    _otherController.dispose();
    _otherFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final category = _selected;
    if (category == null) return;

    final notifier = ref.read(oxMediaIssueSubmitProvider.notifier);
    await notifier.submit(
      target: widget.target,
      category: category,
      customMessage: category.requiresCustomMessage ? _otherController.text : null,
    );

    if (!mounted) return;
    final state = ref.read(oxMediaIssueSubmitProvider);
    state.whenOrNull(
      data: (_) {
        Navigator.of(context).pop();
        FladderSnack.show(context.localized.oxplayerReportIssueSuccess, context: context);
      },
      error: (error, _) {
        FladderSnack.show(
          context.localized.oxplayerReportIssueFailed,
          context: context,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final contextAsync = ref.watch(oxMediaIssueContextProvider(widget.target));
    final submitState = ref.watch(oxMediaIssueSubmitProvider);
    final isDpad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    final isSubmitting = submitState.isLoading;

    return contextAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          context.localized.oxplayerReportIssueContextFailed,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
      data: (ctx) {
        final categories = OxMediaIssueCategory.values;
        return ListView(
          controller: widget.scrollController,
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (AdaptiveLayout.viewSizeOf(context) == ViewSize.phone) ...[
              Text(
                context.localized.oxplayerReportIssueTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(widget.target.displayTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
            ],
            Text(context.localized.oxplayerReportIssueChooseCategory),
            const SizedBox(height: 12),
            for (var i = 0; i < categories.length; i++)
              _CategoryTile(
                label: _categoryLabel(context, categories[i]),
                selected: _selected == categories[i],
                autofocus: isDpad && i == 0,
                onTap: isSubmitting
                    ? null
                    : () => setState(() => _selected = categories[i]),
              ),
            if (_selected?.requiresCustomMessage == true) ...[
              const SizedBox(height: 16),
              OutlinedTextField(
                controller: _otherController,
                focusNode: _otherFocus,
                label: context.localized.oxplayerReportIssueOtherHint,
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                autofocus: isDpad && _selected != null,
                onPressed: _selected == null || isSubmitting ? null : _submit,
                icon: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(IconsaxPlusBold.flag),
                label: Text(context.localized.oxplayerReportIssueSubmit),
              ),
            ),
          ],
        );
      },
    );
  }

  String _categoryLabel(BuildContext context, OxMediaIssueCategory category) {
    return switch (category) {
      OxMediaIssueCategory.brokenSubtitles => context.localized.oxplayerReportIssueBrokenSubtitles,
      OxMediaIssueCategory.dualAudioDubbing => context.localized.oxplayerReportIssueDualAudio,
      OxMediaIssueCategory.badVideoQuality => context.localized.oxplayerReportIssueBadVideo,
      OxMediaIssueCategory.other => context.localized.oxplayerReportIssueOther,
    };
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback? onTap;

  const _CategoryTile({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          autofocus: autofocus,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          focusColor: theme.colorScheme.primary.withValues(alpha: 0.2),
          child: Focus(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  if (selected) Icon(IconsaxPlusBold.tick_circle, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
