import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/sandbox_service.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

/// A modal chat scoped to one sandbox distro. The model is handed only the
/// `sandbox_*` tools, so it can act inside the sandbox and nowhere else.
void showSandboxChat(String distro) {
  final context = GlobalVariable.infobox.currentContext;
  if (context == null) return;
  showDialog(
    context: context,
    builder: (context) => SandboxChatDialog(distro: distro),
  );
}

class SandboxChatDialog extends StatefulWidget {
  const SandboxChatDialog({super.key, required this.distro, this.chat});

  final String distro;

  /// Injectable for tests.
  final SandboxChat? chat;

  @override
  State<SandboxChatDialog> createState() => _SandboxChatDialogState();
}

class _SandboxChatDialogState extends State<SandboxChatDialog> {
  late final SandboxChat _chat = widget.chat ?? SandboxChat(widget.distro);
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!_chat.canSend) {
      Notify.message('byok-required-text'.i18n(),
          severity: InfoBarSeverity.warning);
      return;
    }
    _input.clear();
    setState(() => _busy = true);
    _scrollDown();
    try {
      await _chat.send(text, onUpdate: () {
        if (mounted) setState(() {});
        _scrollDown();
      });
    } catch (_) {
      if (mounted) {
        Notify.message('ai-error-text'.i18n(), severity: InfoBarSeverity.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _chat.history;
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
      title: Row(
        children: [
          Icon(FluentIcons.processing,
              size: 16, color: FluentTheme.of(context).accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text('sandbox-chat-title'.i18n([widget.distro]),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: InfoBar(
                title: Text('sandbox-chat-scope-text'.i18n()),
                severity: InfoBarSeverity.info,
                isLong: true,
              ),
            ),
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Text('sandbox-chat-hint-text'.i18n(),
                          style:
                              TextStyle(color: secondaryTextColor(context))),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: history.length,
                      itemBuilder: (context, i) => _bubble(history[i]),
                    ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const SizedBox.square(dimension: 14, child: ProgressRing()),
                  const SizedBox(width: 8),
                  Text('ai-generating-text'.i18n(),
                      style: TextStyle(
                          fontSize: 11, color: secondaryTextColor(context))),
                ]),
              ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextBox(
                controller: _input,
                placeholder: 'ai-assistant-placeholder'.i18n(),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  (_input.text.trim().isNotEmpty && !_busy) ? _send : null,
              child: Text('ai-send-text'.i18n()),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('close-text'.i18n()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bubble(AiMessage msg) {
    if (msg.role == 'tool') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 8),
        child: Text('ai-ran-tool-text'.i18n([msg.content]),
            style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: secondaryTextColor(context))),
      );
    }
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isUser
                ? FluentTheme.of(context).accentColor.withValues(alpha: 0.15)
                : subtleFillColor(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: isUser
              ? Text(msg.content, style: const TextStyle(fontSize: 12))
              : MarkdownBody(
                  data: msg.content,
                  styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 12))),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
