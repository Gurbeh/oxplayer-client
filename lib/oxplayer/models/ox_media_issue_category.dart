/// Jellyseerr [IssueType] values for POST /api/v1/issue.
enum OxMediaIssueCategory {
  brokenSubtitles(3),
  dualAudioDubbing(2, defaultMessage: 'Expected dual-audio or dubbed track'),
  badVideoQuality(1),
  other(4);

  const OxMediaIssueCategory(this.issueType, {this.defaultMessage});

  final int issueType;
  final String? defaultMessage;

  bool get requiresCustomMessage => this == OxMediaIssueCategory.other;
}
