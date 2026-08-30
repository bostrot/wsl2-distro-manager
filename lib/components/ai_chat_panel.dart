import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/beta_badge.dart';
import 'package:wsl2distromanager/components/named_button.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:wsl2distromanager/nav/router.dart';

class AiChatPanel extends StatefulWidget {
  const AiChatPanel({Key? key}) : super(key: key);

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final AiService _ai = AiService();
  final LicenseManager _license = LicenseManager();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  /// i18n key of the precondition that stopped the last Send, if any.
  ///
  /// Send used to answer a missing API key by navigating to Settings on its
  /// own, which destroyed this panel and took the typed question with it
  /// (audit PS-33). The notice is rendered in the panel instead, and the text
  /// stays in the box.
  String? _blockedReasonKey;

  /// The route the notice's button goes to, and its label.
  String? _blockedRouteName;
  String? _blockedActionKey;

  void _block(String reasonKey, String routeName, String actionKey) {
    if (!mounted) return;
    setState(() {
      _blockedReasonKey = reasonKey;
      _blockedRouteName = routeName;
      _blockedActionKey = actionKey;
    });
  }

  void _unblock() {
    if (_blockedReasonKey == null) return;
    setState(() {
      _blockedReasonKey = null;
      _blockedRouteName = null;
      _blockedActionKey = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _ai.init().then((_) => setState(() {}));
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    // Check license
    if (!_license.isPro) {
      _block('ai-chat-pro-required-text', 'license', 'upgrade-text');
      return;
    }

    // Chat runs on the user's own API key — nothing to send without one.
    if (!_ai.hasByokConfigured) {
      _block('byok-required-text', 'settings', 'opensettings-text');
      return;
    }

    _unblock();
    setState(() {
      _isLoading = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      await _ai.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      final msg = e.toString();
      if (msg.contains('pro-required') || msg.contains('byok-required')) {
        // The question never reached a provider, so give it back rather than
        // making the user retype it (PS-33).
        if (_inputController.text.isEmpty) _inputController.text = text;
        msg.contains('pro-required')
            ? _block('ai-chat-pro-required-text', 'license', 'upgrade-text')
            : _block('byok-required-text', 'settings', 'opensettings-text');
      } else {
        Notify.message('ai-error-text'.i18n(), severity: InfoBarSeverity.error);
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = _ai.conversationHistory;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(FluentIcons.chat,
                  size: 16, color: FluentTheme.of(context).accentColor),
              const SizedBox(width: 8),
              Text(
                'ai-assistant-title'.i18n(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: FluentTheme.of(context).accentColor,
                ),
              ),
              const SizedBox(width: 6),
              const BetaBadge(),
              const Spacer(),
              // No quota counter anymore — chat runs on the user's own API
              // key, so usage is between them and their provider.
              const SizedBox(width: 8),
              // One mis-click used to erase the whole conversation with no
              // undo, and the control stayed live over an empty history
              // (audit PS-35).
              NamedIconButton(
                key: const ValueKey('test-chat-clear'),
                label: 'clearchat-text'.i18n(),
                icon: FluentIcons.delete,
                iconSize: 14,
                onPressed: history.isEmpty
                    ? null
                    : () => dialog(
                          hostContext: context,
                          item: '',
                          title: 'clearchatquestion-text'.i18n(),
                          body: 'clearchatbody-text'.i18n(),
                          submitText: 'clear-text'.i18n(),
                          submitInput: false,
                          submitStyle: ButtonStyle(
                            backgroundColor: ButtonState.all(Colors.red),
                            foregroundColor: ButtonState.all(Colors.white),
                          ),
                          onSubmit: (_) {
                            _ai.clearHistory();
                            setState(() {});
                          },
                        ),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        FluentIcons.chat,
                        size: 48,
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ai-assistant-hint'.i18n(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (!_license.isPro) ...[
                        const SizedBox(height: 16),
                        Button(
                          onPressed: () => navigateGuarded('license'),
                          child: Text('upgrade-text'.i18n()),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final msg = history[index];
                    return _buildMessageBubble(msg);
                  },
                ),
        ),

        // Loading indicator
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const SizedBox(width: 16, height: 16, child: ProgressRing()),
                const SizedBox(width: 8),
                Text(
                  'ai-generating-text'.i18n(),
                  style: TextStyle(
                      fontSize: 11, color: secondaryTextColor(context)),
                ),
              ],
            ),
          ),

        // Why Send did nothing, said in the panel instead of by navigating
        // away from it (PS-33).
        if (_blockedReasonKey != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: InfoBar(
              key: const ValueKey('test-aichat-blocked'),
              title: Text(_blockedReasonKey!.i18n()),
              severity: InfoBarSeverity.warning,
              onClose: _unblock,
              action: Button(
                key: const ValueKey('test-aichat-blocked-action'),
                onPressed: () => navigateGuarded(_blockedRouteName!),
                child: Text(_blockedActionKey!.i18n()),
              ),
            ),
          ),

        // Input area
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.grey.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _inputController,
                  placeholder: 'ai-assistant-placeholder'.i18n(),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed:
                    (_inputController.text.trim().isNotEmpty && !_isLoading)
                        ? _sendMessage
                        : null,
                child: Text('ai-send-text'.i18n()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(AiMessage msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color:
                    FluentTheme.of(context).accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                FluentIcons.chat,
                size: 14,
                color: FluentTheme.of(context).accentColor,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isUser
                    ? FluentTheme.of(context)
                        .accentColor
                        .withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: msg.role == 'assistant'
                  ? MarkdownBody(
                      data: msg.content,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 12),
                        code: TextStyle(
                          fontSize: 11,
                          backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    )
                  : Text(
                      msg.content,
                      style: const TextStyle(fontSize: 12),
                    ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                FluentIcons.add,
                size: 14,
                color: secondaryTextColor(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
