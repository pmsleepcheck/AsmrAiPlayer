import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/network/proxy_config.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

/// 编辑应用内 HTTP 代理地址（`主机:端口`）。
///
/// 保存前经 [ProxyConfig.normalize] 校验/规范化；非法输入停留在弹窗内
/// 显示错误文案，不落盘。
class ProxyAddressDialog extends StatefulWidget {
  final AppSettingsService settings;

  const ProxyAddressDialog({super.key, required this.settings});

  @override
  State<ProxyAddressDialog> createState() => _ProxyAddressDialogState();
}

class _ProxyAddressDialogState extends State<ProxyAddressDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.proxyUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final normalized = ProxyConfig.normalize(_controller.text);
    if (normalized == null) {
      setState(() => _error = Strings.proxyAddressInvalid);
      return;
    }
    widget.settings.setProxyUrl(normalized);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(Strings.proxyAddress),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: Strings.proxyAddressHint,
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(Strings.cancel),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text(Strings.save),
        ),
      ],
    );
  }
}
