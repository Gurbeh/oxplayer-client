import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/oxplayer/models/ox_media_issue_category.dart';
import 'package:fladder/oxplayer/models/ox_media_issue_target.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/providers/ox_media_issue_context.dart';
import 'package:fladder/oxplayer/services/ox_seerr_issue_client.dart';
import 'package:fladder/providers/user_provider.dart';

part 'ox_media_issue_submit.g.dart';

@riverpod
class OxMediaIssueSubmit extends _$OxMediaIssueSubmit {
  @override
  FutureOr<void> build() {}

  Future<void> submit({
    required OxMediaIssueTarget target,
    required OxMediaIssueCategory category,
    String? customMessage,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final context = await ref.read(oxMediaIssueContextProvider(target).future);

      final prefix = target.episodePrefix();
      final body = switch (category) {
        OxMediaIssueCategory.other => customMessage?.trim() ?? '',
        _ => category.defaultMessage ?? '',
      };
      if (body.isEmpty && category.requiresCustomMessage) {
        throw StateError('Please describe the issue');
      }
      final message = '$prefix$body'.trim();

      final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
      if (token.isEmpty) {
        throw StateError('Not signed in');
      }

      final apiBase = OxplayerEnv.apiBaseUrl?.trim() ?? '';
      if (apiBase.isEmpty) {
        throw StateError('API not configured');
      }

      await oxPostSeerrIssue(
        apiBaseUrl: apiBase,
        accessToken: token,
        issueType: category.issueType,
        message: message,
        mediaId: context.seerrMediaId,
      );
    });
  }
}
