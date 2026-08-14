import 'package:fladder/oxplayer/oxplayer_home_detail_prefetch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home slider PlaybackInfo warmup caps at five', () {
    expect(OxplayerHomeDetailPrefetch.sliderTake, 5);
  });
}
