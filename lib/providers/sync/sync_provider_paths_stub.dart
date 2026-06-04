/// Web / any target without `dart:io`: never call — [SyncNotifier] guards with [kIsWeb] first.
Future<List<String>> supportAndTempPathsForCleanup() async => const [];
