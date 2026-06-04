import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/oxplayer/telegram/utils/tdlib_wire_json_compat.dart';

void main() {
  group('tdJsonPrepareForConvertToObject', () {
    test('coerces updateAvailableMessageEffects int64 strings (native path)', () {
      const raw =
          '{"@type":"updateAvailableMessageEffects",'
          '"reaction_effect_ids":["100","200"],'
          '"sticker_effect_ids":["300"]}';
      final out = tdJsonPrepareForConvertToObject(raw);
      expect(out, isNot(equals(raw)));
      final map = parseTdJsonObjectMap(out);
      expect(map, isNotNull);
      expect(map!['reaction_effect_ids'], [100, 200]);
      expect(map['sticker_effect_ids'], [300]);
    });

    test('passes through unrelated updates on native path', () {
      const raw = '{"@type":"updateOption","name":"x","value":{"@type":"optionValueEmpty"}}';
      expect(tdJsonPrepareForConvertToObject(raw), raw);
    });
  });

  group('tdlibJsonPeekForLog', () {
    test('returns @type for object JSON', () {
      expect(tdlibJsonPeekForLog('{"@type":"getMe"}'), 'getMe');
    });

    test('includes @extra when present', () {
      expect(
        tdlibJsonPeekForLog('{"@type":"foo","@extra":1}'),
        'foo @extra=1',
      );
    });
  });
}
