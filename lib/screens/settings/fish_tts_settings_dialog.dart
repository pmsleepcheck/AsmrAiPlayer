import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/supertonic_tts_service.dart';
import 'package:aaplay/core/audio/translation/tts_synthesizer.dart';
import 'package:aaplay/core/theme/app_spacing.dart';

/// 设置 → AI 翻译：TTS 引擎切换 / Supertonic 本地服务 / Fish Key+音色预设+模型 /
/// 延迟 / 翻译轨音量。
///
/// 分区按引擎显示：[TtsSource.supertonic] → 地址/音色/语言 + 服务检测与启动；
/// [TtsSource.fish] → API Key / 音色预设 / 模型。延迟与音量两区始终可见。
class FishTtsSettingsDialog extends StatefulWidget {
  final FishTtsConfigStore config;
  final SupertonicTtsService supertonic;

  const FishTtsSettingsDialog({
    super.key,
    required this.config,
    required this.supertonic,
  });

  @override
  State<FishTtsSettingsDialog> createState() => _FishTtsSettingsDialogState();
}

class _FishTtsSettingsDialogState extends State<FishTtsSettingsDialog> {
  late final TextEditingController _keyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _voiceController;
  late final TextEditingController _langController;
  late String _model;
  late double _volume;
  late int _delayMs;
  late TtsSource _source;
  String? _loadedKey;
  bool _keyDirty = false;
  bool _saving = false;

  /// 本地服务状态：null=未检测。
  bool? _serviceUp;
  bool _serviceBusy = false;

  List<FishVoicePreset> _presets = [];
  String _activeId = '';

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
    _baseUrlController =
        TextEditingController(text: widget.config.supertonicBaseUrl);
    _voiceController =
        TextEditingController(text: widget.config.supertonicVoice);
    _langController = TextEditingController(text: widget.config.supertonicLang);
    _model = widget.config.model;
    _volume = widget.config.secondaryVolume;
    _delayMs = widget.config.delayMs;
    _source = widget.config.ttsSource;
    _presets = List.from(widget.config.voicePresets);
    _activeId = widget.config.activeVoiceId;
    _loadKey();
  }

  Future<void> _loadKey() async {
    final k = await widget.config.loadApiKey();
    if (!mounted) return;
    setState(() {
      _loadedKey = k;
      if (!_keyDirty) {
        // 显示掩码占位，不回填明文。
        _keyController.text = '';
      }
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _voiceController.dispose();
    _langController.dispose();
    super.dispose();
  }

  bool get _keyHasExisting =>
      (_loadedKey ?? '').isNotEmpty || _keyController.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final typed = _keyController.text.trim();
      if (typed.isNotEmpty) {
        await widget.config.writeApiKey(typed);
      } else if (_keyController.text.isEmpty && _keyDirty) {
        // 用户清空输入且主动改过 → 视为删除。
        // 未 dirty 时保持原 Key。
      }
      // 预设列表：整表写回（管理对话框内本地编辑）。
      for (final p in _presets) {
        await widget.config.upsertPreset(p);
      }
      // 删除已不在列表中的旧项。
      final keepIds = _presets.map((e) => e.id).toSet();
      for (final old in List.of(widget.config.voicePresets)) {
        if (!keepIds.contains(old.id)) {
          await widget.config.removePreset(old.id);
        }
      }
      if (_activeId.isNotEmpty) {
        await widget.config.setActiveVoiceId(_activeId);
      }
      await widget.config.setModel(_model);
      await widget.config.setSecondaryVolume(_volume);
      await widget.config.setDelayMs(_delayMs);
      // 引擎与 Supertonic 参数：切引擎要立即生效（router 每次请求读配置）。
      await widget.config.setTtsSource(_source);
      if (_source == TtsSource.supertonic) {
        await widget.config.setSupertonicBaseUrl(_baseUrlController.text);
        await widget.config.setSupertonicVoice(_voiceController.text);
        await widget.config.setSupertonicLang(_langController.text);
      }
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editPreset({FishVoicePreset? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final refCtrl = TextEditingController(text: existing?.referenceId ?? '');
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            existing == null ? Strings.voicePresetAdd : Strings.voicePresetEdit,
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: Strings.voicePresetName,
                    hintText: Strings.voicePresetNameHint,
                    errorText: error,
                  ),
                ),
                const SizedBox(height: AppSpacing.space12),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: Strings.voicePresetReference,
                    hintText: Strings.fishReferenceIdHint,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(Strings.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setLocal(() => error = Strings.voicePresetNameRequired);
                  return;
                }
                final dup = _presets.any(
                  (p) =>
                      p.name.trim() == name &&
                      (existing == null || p.id != existing.id),
                );
                if (dup) {
                  setLocal(() => error = Strings.voicePresetNameDuplicate);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text(Strings.save),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    final preset = existing == null
        ? FishVoicePreset(
            id: FishTtsConfigStore.newPresetId(),
            name: nameCtrl.text.trim(),
            referenceId: refCtrl.text.trim(),
          )
        : existing.copyWith(
            name: nameCtrl.text.trim(),
            referenceId: refCtrl.text.trim(),
          );
    setState(() {
      final i = _presets.indexWhere((p) => p.id == preset.id);
      if (i >= 0) {
        _presets[i] = preset;
      } else {
        _presets.add(preset);
      }
      if (_activeId.isEmpty) _activeId = preset.id;
    });
  }

  /// 健康检测：`GET /v1/health`，结果只驱动状态文案，不抛错。
  Future<void> _checkService() async {
    setState(() => _serviceBusy = true);
    final up = await widget.supertonic.isHealthy();
    if (!mounted) return;
    setState(() {
      _serviceUp = up;
      _serviceBusy = false;
    });
  }

  /// 尝试拉起本地服务（仅桌面端），把结果映射成用户可执行的文案。
  Future<void> _startService() async {
    setState(() => _serviceBusy = true);
    final status = await widget.supertonic.startServer();
    if (!mounted) return;
    setState(() {
      _serviceBusy = false;
      if (status == SupertonicLaunchStatus.alreadyRunning ||
          status == SupertonicLaunchStatus.started) {
        _serviceUp = true;
      } else if (status == SupertonicLaunchStatus.notFound ||
          status == SupertonicLaunchStatus.unsupported ||
          status == SupertonicLaunchStatus.failed) {
        _serviceUp = false;
      }
    });
    final msg = switch (status) {
      SupertonicLaunchStatus.alreadyRunning =>
        Strings.supertonicLaunchAlreadyRunning,
      SupertonicLaunchStatus.started => Strings.supertonicLaunchStarted,
      SupertonicLaunchStatus.starting => Strings.supertonicLaunchStarting,
      SupertonicLaunchStatus.unsupported =>
        Strings.supertonicLaunchUnsupported,
      SupertonicLaunchStatus.notFound => Strings.supertonicLaunchNotFound,
      SupertonicLaunchStatus.failed => Strings.supertonicLaunchFailed,
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deletePreset(FishVoicePreset p) async {
    final name = p.name;
    final msg = Strings.voicePresetDeleteConfirm.replaceFirst('%s', name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(Strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(Strings.voicePresetDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _presets.removeWhere((e) => e.id == p.id);
      if (_activeId == p.id) _activeId = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text(Strings.aiTranslationSection),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Strings.aiTranslationSectionDesc,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.space16),
              Text(Strings.ttsSourceLabel,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.space4),
              DropdownButtonFormField<TtsSource>(
                value: _source,
                items: const [
                  DropdownMenuItem(
                      value: TtsSource.supertonic,
                      child: Text(Strings.ttsSourceSupertonic)),
                  DropdownMenuItem(
                      value: TtsSource.fish,
                      child: Text(Strings.ttsSourceFish)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _source = v);
                },
                decoration: const InputDecoration(
                    helperText: Strings.ttsSourceDesc),
              ),
              const SizedBox(height: AppSpacing.space16),
              if (_source == TtsSource.fish) ...[
              Text(Strings.fishApiKey,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.space4),
              TextField(
                controller: _keyController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: (_loadedKey ?? '').isNotEmpty
                      ? Strings.fishApiKeySet
                      : Strings.fishApiKeyHint,
                  helperText: Strings.fishApiKeyHint,
                  errorText: _keyDirty && _keyController.text.isEmpty &&
                          (_loadedKey ?? '').isEmpty
                      ? null
                      : null,
                ),
                onChanged: (_) => setState(() => _keyDirty = true),
              ),
              const SizedBox(height: AppSpacing.space16),
              Row(
                children: [
                  Text(Strings.voicePresetSection,
                      style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editPreset(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(Strings.voicePresetAdd),
                  ),
                ],
              ),
              Text(
                Strings.voicePresetSectionDesc,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.space4),
              if (_presets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space8),
                  child: Text(
                    Strings.voicePresetEmpty,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              else
                for (final p in _presets)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Radio<String>(
                      value: p.id,
                      groupValue: _activeId,
                      onChanged: (v) {
                        if (v != null) setState(() => _activeId = v);
                      },
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      p.referenceId.isEmpty
                          ? Strings.voicePresetDefault
                          : p.referenceId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: Strings.voicePresetEdit,
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _editPreset(existing: p),
                        ),
                        IconButton(
                          tooltip: Strings.voicePresetDelete,
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _deletePreset(p),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: AppSpacing.space16),
              Text(Strings.fishModel,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.space4),
              DropdownButtonFormField<String>(
                value: _model,
                items: [
                  for (final m in FishTtsConfigStore.modelOptions)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _model = v);
                },
              ),
              ] else ...[
                TextField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: Strings.supertonicBaseUrlLabel,
                    hintText: Strings.supertonicBaseUrlHint,
                    helperText: Strings.supertonicBaseUrlHint,
                  ),
                ),
                const SizedBox(height: AppSpacing.space12),
                TextField(
                  controller: _voiceController,
                  decoration: const InputDecoration(
                    labelText: Strings.supertonicVoiceLabel,
                    hintText: Strings.supertonicVoiceHint,
                    helperText: Strings.supertonicVoiceHint,
                  ),
                ),
                const SizedBox(height: AppSpacing.space12),
                TextField(
                  controller: _langController,
                  decoration: const InputDecoration(
                    labelText: Strings.supertonicLangLabel,
                    hintText: Strings.supertonicLangHint,
                    helperText: Strings.supertonicLangHint,
                  ),
                ),
                const SizedBox(height: AppSpacing.space12),
                Row(
                  children: [
                    Text(Strings.supertonicServiceLabel,
                        style: Theme.of(context).textTheme.labelLarge),
                    const Spacer(),
                    Text(
                      _serviceUp == null
                          ? Strings.supertonicStatusUnknown
                          : _serviceUp!
                              ? Strings.supertonicStatusRunning
                              : Strings.supertonicStatusStopped,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: _serviceUp == true
                                ? cs.primary
                                : _serviceUp == false
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space4),
                Row(
                  children: [
                    TextButton(
                      onPressed:
                          _serviceBusy ? null : _checkService,
                      child: Text(_serviceBusy
                          ? Strings.supertonicChecking
                          : Strings.supertonicCheck),
                    ),
                    TextButton(
                      onPressed:
                          _serviceBusy ? null : _startService,
                      child: Text(_serviceBusy
                          ? Strings.supertonicStarting
                          : Strings.supertonicStart),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.space16),
              Text(Strings.translationDelayLabel,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.space4),
              DropdownButtonFormField<int>(
                value: FishTtsConfigStore.delayOptionsMs.contains(_delayMs)
                    ? _delayMs
                    : FishTtsConfigStore.defaultDelayMs,
                items: [
                  for (final d in FishTtsConfigStore.delayOptionsMs)
                    DropdownMenuItem(
                      value: d,
                      child: Text(Strings.translationDelayOption(d)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _delayMs = v);
                },
                decoration: const InputDecoration(
                  helperText: Strings.translationDelayHint,
                ),
              ),
              const SizedBox(height: AppSpacing.space16),
              Text(
                '${Strings.translationSecondaryVolumeLabel} · '
                '${Strings.percentLabel((_volume * 100).round())}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Slider(
                value: _volume,
                min: 0,
                max: 1,
                divisions: 20,
                label: Strings.percentLabel((_volume * 100).round()),
                onChanged: (v) => setState(() => _volume = v),
              ),
              if (_source == TtsSource.fish && !_keyHasExisting && _keyDirty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space8),
                  child: Text(
                    Strings.translationRequiresApiKey,
                    style: TextStyle(color: cs.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text(Strings.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text(Strings.save),
        ),
      ],
    );
  }
}
