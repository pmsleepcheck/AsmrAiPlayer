import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FishVoicePreset 解析', () {
    test('fromJson 忽略未知字段（role 预留不破坏、不序列化）', () {
      final p = FishVoicePreset.fromJson(const {
        'id': 'a',
        'name': '少女音',
        'referenceId': 'ref-1',
        'role': 'heroine',
        'unknown': 1,
      });
      expect(p.id, 'a');
      expect(p.name, '少女音');
      expect(p.referenceId, 'ref-1');
      expect(p.toJson().containsKey('role'), isFalse);
      expect(p.toJson()['unknown'], isNull);
    });

    test('fromJson 缺字段回落空串', () {
      final p = FishVoicePreset.fromJson(const {});
      expect(p.id, '');
      expect(p.name, '');
      expect(p.referenceId, '');
    });
  });

  group('FishTtsConfigStore 音色预设', () {
    test('默认空列表 + 无活动 id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      expect(store.voicePresets, isEmpty);
      expect(store.activeVoiceId, '');
      expect(store.activeVoice, isNull);
      expect(store.referenceId, '');
    });

    test('旧 fish_reference_id 单值一次性迁移进预设并设为活动', () async {
      SharedPreferences.setMockInitialValues({
        'fish_reference_id': 'legacy-voice',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      expect(store.voicePresets, hasLength(1));
      expect(store.voicePresets.first.id, 'legacy');
      expect(store.voicePresets.first.referenceId, 'legacy-voice');
      expect(store.activeVoiceId, 'legacy');
      expect(store.referenceId, 'legacy-voice');
      expect(
        FishTtsConfigStore(prefs: prefs).voicePresets,
        hasLength(1),
      );
    });

    test('upsert / setActive / remove 后 referenceId 跟随活动预设', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);

      await store.upsertPreset(const FishVoicePreset(
        id: 'p1',
        name: 'A',
        referenceId: 'ref-a',
      ));
      await store.upsertPreset(const FishVoicePreset(
        id: 'p2',
        name: 'B',
        referenceId: 'ref-b',
      ));
      expect(store.voicePresets, hasLength(2));

      await store.setActiveVoiceId('p2');
      expect(store.referenceId, 'ref-b');
      expect(store.activeVoice?.name, 'B');

      // cacheKey 已含 referenceId → 切换天然隔离（service 层单测覆盖）。
      await store.setActiveVoiceId('p1');
      expect(store.referenceId, 'ref-a');

      await store.removePreset('p1');
      expect(store.voicePresets, hasLength(1));
      // 删活动项 → 活动 id 清空，回落 legacy/空
      expect(store.activeVoiceId, '');
      expect(store.referenceId, '');
    });

    test('upsert 同 id 覆盖（改名/改 ref）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      await store.upsertPreset(const FishVoicePreset(
        id: 'x',
        name: '旧名',
        referenceId: 'r1',
      ));
      await store.upsertPreset(const FishVoicePreset(
        id: 'x',
        name: '新名',
        referenceId: 'r2',
      ));
      expect(store.voicePresets, hasLength(1));
      expect(store.voicePresets.first.name, '新名');
      expect(store.voicePresets.first.referenceId, 'r2');
    });

    test('setActiveVoiceId(null) 清除活动并 notifyListeners', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      var n = 0;
      store.addListener(() => n++);
      await store.upsertPreset(const FishVoicePreset(
        id: 'z',
        name: 'Z',
        referenceId: 'rz',
      ));
      await store.setActiveVoiceId('z');
      expect(n, 2);
      await store.setActiveVoiceId(null);
      expect(store.activeVoiceId, '');
      expect(n, 3);
      expect(store.referenceId, '');
    });

    test('损坏的 JSON → 空列表不抛', () async {
      SharedPreferences.setMockInitialValues({
        'fish_voice_presets': '{not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      expect(store.voicePresets, isEmpty);
    });

    test('newPresetId 非空', () {
      final a = FishTtsConfigStore.newPresetId();
      expect(a, isNotEmpty);
      expect(a, isNot(''));
    });
  });
}
