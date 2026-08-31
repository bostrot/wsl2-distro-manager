import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/sandbox_service.dart';
import 'package:wsl2distromanager/api/todo_store.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/beta_badge.dart';
import 'package:wsl2distromanager/components/named_button.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:wsl2distromanager/nav/router.dart';

class AiChatPanel extends StatefulWidget {
  const AiChatPanel({Key? key, this.onClose, this.sandbox}) : super(key: key);

  /// Closes the panel. Without it the only way to dismiss the panel was the
  /// FAB behind it (audit PS-34).
  final VoidCallback? onClose;

  /// When set, this panel is that sandbox's chat: same UI, same task queue,
  /// but the transcript and tools come from [SandboxChat] — scoped to one
  /// distro. Null is the normal app-wide assistant.
  final SandboxChat? sandbox;

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final AiService _ai = AiService();
  final LicenseManager _license = LicenseManager();
  final TodoStore _todos = TodoStore.instance;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _todoInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlyoutController _sessionsFlyout = FlyoutController();
  bool _isLoading = false;
  bool _tasksExpanded = false;

  /// The signal that genuinely stops the current run — tools and the
  /// in-flight request included, not just the UI (plan item 1).
  CancelSignal? _runCancel;

  /// Set by Cancel so the task runner's auto-continue stops too, instead of
  /// immediately dispatching the next round of the queue.
  bool _stopTasksRequested = false;

  /// How many times a "work on tasks" run may auto-continue itself before it
  /// stops on its own — a queue that never drains must not loop forever.
  static const int _maxAutoContinue = 6;

  SandboxChat? get _sandbox => widget.sandbox;
  List<AiMessage> get _transcript =>
      _sandbox?.history ?? _ai.conversationHistory;

  /// Incremented on every Send and on Cancel. A reply whose generation is
  /// stale was cancelled while in flight and is dropped — the panel used to
  /// have no way out of a hung request at all (audit PS-34).
  int _requestGeneration = 0;

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
    _todos.addListener(_onTodosChanged);
  }

  void _onTodosChanged() {
    if (mounted) setState(() {});
  }

  /// Sends the "work through the queue" instruction, then auto-continues while
  /// the assistant keeps completing tasks — this is the "keep going until all
  /// are done" the user asked for. It stops when the queue is empty, when a
  /// run makes no progress, or after [_maxAutoContinue] rounds.
  Future<void> _workOnTasks() async {
    if (_isLoading || !_todos.hasOpen) return;
    _stopTasksRequested = false;
    await _dispatch(
        'Work through the task list until every item is done. Use todo_list '
        'to see what is left, do each task with your tools, and call '
        'todo_set_done the moment you finish one.');
    var rounds = 0;
    while (mounted &&
        !_stopTasksRequested &&
        _todos.hasOpen &&
        rounds < _maxAutoContinue &&
        !_isLoading) {
      final before = _todos.openCount;
      rounds++;
      await _dispatch('Continue with the remaining tasks.');
      // No progress this round — stop rather than spin.
      if (_todos.openCount >= before) break;
    }
  }

  /// One button stops everything: the in-flight request, further tool
  /// executions, and the task runner's auto-continue.
  void _cancelRun() {
    _stopTasksRequested = true;
    _runCancel?.cancel();
    setState(() {
      _requestGeneration++;
      _isLoading = false;
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;
    _inputController.clear();
    await _dispatch(text);
  }

  /// The actual send: precondition checks, the request, and error handling.
  /// Factored out of [_sendMessage] so the task runner can reuse it.
  Future<void> _dispatch(String text) async {
    if (text.isEmpty || _isLoading) return;

    // Check license
    if (!_license.isPro) {
      _block('ai-chat-pro-required-text', 'license', 'upgrade-text');
      return;
    }

    // Chat runs on credentials the user brings — nothing to send without
    // a key or a Claude sign-in, whichever provider is picked.
    if (!_ai.hasAiConfigured) {
      _block(_ai.configRequiredKey, 'settings', 'opensettings-text');
      return;
    }

    _unblock();
    final generation = ++_requestGeneration;
    final cancel = _runCancel = CancelSignal();
    setState(() {
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      void onUpdate() {
        // Tool calls and interim narration land in the transcript mid-run;
        // repaint so the user watches the assistant work instead of staring
        // at a spinner.
        if (mounted && generation == _requestGeneration) {
          setState(() {});
          _scrollToBottom();
        }
      }

      if (_sandbox != null) {
        await _sandbox!.send(text, onUpdate: onUpdate, cancel: cancel);
      } else {
        await _ai.sendMessage(text, onUpdate: onUpdate, cancel: cancel);
      }
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _isLoading = false;
      });
    } on CancelledException {
      // The user pressed Cancel — the run is already unwound and reported.
      return;
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _isLoading = false;
      });

      final msg = e.toString();
      if (msg.contains('pro-required') ||
          msg.contains('byok-required') ||
          msg.contains('claude-signin-required')) {
        // The question never reached a provider, so give it back rather than
        // making the user retype it (PS-33).
        if (_inputController.text.isEmpty) _inputController.text = text;
        msg.contains('pro-required')
            ? _block('ai-chat-pro-required-text', 'license', 'upgrade-text')
            : _block(_ai.configRequiredKey, 'settings', 'opensettings-text');
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
    final history = _transcript;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: surfaceBorderColor(context),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(_sandbox == null ? FluentIcons.chat : FluentIcons.cube_shape,
                  size: 16, color: FluentTheme.of(context).accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sandbox == null
                      ? 'ai-assistant-title'.i18n()
                      : 'sandbox-chat-title'
                          .i18n([_shortSandboxName(_sandbox!.distro)]),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: FluentTheme.of(context).accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const BetaBadge(),
              const SizedBox(width: 4),
              // Switch between the app assistant and sandbox sessions —
              // their transcripts persist, so any of them can be reopened.
              _sessionsButton(context),
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
                            _sandbox == null
                                ? _ai.clearHistory()
                                : _sandbox!.clear();
                            setState(() {});
                          },
                        ),
              ),
              if (widget.onClose != null) ...[
                const SizedBox(width: 4),
                NamedIconButton(
                  key: const ValueKey('test-chat-close'),
                  label: 'close-text'.i18n(),
                  icon: FluentIcons.chrome_close,
                  iconSize: 12,
                  onPressed: widget.onClose,
                ),
              ],
            ],
          ),
        ),

        // The task queue: the user adds todos and can tell the assistant to
        // work through them; the assistant checks them off as it goes.
        _buildTasksSection(context),

        // Said before the first keystroke, not after the first Send: with no
        // key the panel used to be indistinguishable from a working one until
        // the button revealed the precondition (audit PS-34).
        if (!_ai.hasAiConfigured && _blockedReasonKey == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: InfoBar(
              key: const ValueKey('test-aichat-needs-key'),
              title: Text(_ai.configRequiredKey.i18n()),
              severity: InfoBarSeverity.info,
              action: Button(
                onPressed: () => navigateGuarded('settings'),
                child: Text('opensettings-text'.i18n()),
              ),
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
                        color: disabledTextColor(context),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          (_sandbox == null
                                  ? 'ai-assistant-hint'
                                  : 'sandbox-chat-hint-text')
                              .i18n(),
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // No Upgrade button here: the FAB that opens this panel
                      // is Pro-only, so the only people who could ever see
                      // one are already Pro (audit PS-39). If the panel needs
                      // a key instead, Send says so inline (PS-34).
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
                // "Generating… · step 12 · 34.5k tokens": a long agent run is
                // visibly moving, not hanging (plan item 3).
                Expanded(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: _ai.runStatus,
                    builder: (context, status, _) => Text(
                      status == null
                          ? 'ai-generating-text'.i18n()
                          : "${'ai-generating-text'.i18n()} · $status",
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: secondaryTextColor(context)),
                    ),
                  ),
                ),
                // Really stops the run — request, tools and auto-continue —
                // not just this panel's spinner (plan item 1).
                Button(
                  key: const ValueKey('test-chat-cancel-request'),
                  onPressed: _cancelRun,
                  child: Text('cancel-text'.i18n()),
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
                color: surfaceBorderColor(context),
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

  static String _shortSandboxName(String distro) =>
      distro.startsWith(SandboxService.prefix)
          ? distro.substring(SandboxService.prefix.length)
          : distro;

  /// Flyout listing the app assistant and every sandbox chat, so a closed
  /// conversation can be reopened — transcripts persist across close/reopen.
  Widget _sessionsButton(BuildContext context) {
    final sandboxes = SandboxService().list();
    if (sandboxes.isEmpty && _sandbox == null) {
      return const SizedBox.shrink();
    }
    // An icon-only button like its clear/close neighbours, not a
    // DropDownButton: the empty title left a stray gap between the history
    // glyph and the chevron (user-reported).
    return FlyoutTarget(
      controller: _sessionsFlyout,
      child: NamedIconButton(
        key: const ValueKey('test-chat-sessions'),
        label: 'ai-sessions-text'.i18n(),
        icon: FluentIcons.history,
        iconSize: 14,
        onPressed: () => _sessionsFlyout.showFlyout(
          builder: (context) => _sessionsMenu(),
        ),
      ),
    );
  }

  MenuFlyout _sessionsMenu() {
    final sandboxes = SandboxService().list();
    final withHistory = SandboxChat.sessions().toSet();
    return MenuFlyout(
      items: [
        MenuFlyoutItem(
          selected: _sandbox == null,
          leading: _sandbox == null
              ? const Icon(FluentIcons.check_mark, size: 12.0)
              : const SizedBox.square(dimension: 12.0),
          text: Text('ai-assistant-title'.i18n()),
          onPressed: () => GlobalVariable.sandboxChat.value = null,
        ),
        if (sandboxes.isNotEmpty) const MenuFlyoutSeparator(),
        for (final distro in sandboxes)
          MenuFlyoutItem(
            selected: _sandbox?.distro == distro,
            leading: _sandbox?.distro == distro
                ? const Icon(FluentIcons.check_mark, size: 12.0)
                : const SizedBox.square(dimension: 12.0),
            text: Text(withHistory.contains(distro)
                ? _shortSandboxName(distro)
                : "${_shortSandboxName(distro)} — "
                    "${'sandbox-session-new-text'.i18n()}"),
            onPressed: () => GlobalVariable.sandboxChat.value = distro,
          ),
      ],
    );
  }

  Widget _buildTasksSection(BuildContext context) {
    final items = _todos.items;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Icon(
            _tasksExpanded ? FluentIcons.chevron_down : FluentIcons.chevron_right,
            size: 10,
            color: secondaryTextColor(context),
          ),
          const SizedBox(width: 6),
          Text('ai-tasks-title'.i18n(),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(width: 6),
          if (items.isNotEmpty)
            Text('${_todos.openCount}/${items.length}',
                style: TextStyle(
                    fontSize: 11, color: secondaryTextColor(context))),
          const Spacer(),
          if (_todos.hasOpen)
            MergeSemantics(
              child: Tooltip(
                message: 'ai-tasks-work-text'.i18n(),
                child: IconButton(
                  key: const ValueKey('test-chat-work-tasks'),
                  icon: const Icon(FluentIcons.play, size: 12),
                  onPressed: _isLoading ? null : _workOnTasks,
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tasksExpanded = !_tasksExpanded),
          child: header,
        ),
        if (_tasksExpanded) ...[
          // Capped: a long queue scrolls inside its own box instead of
          // squeezing the conversation out of the panel.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: Column(children: [
          for (final t in items)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
              child: Row(
                children: [
                  Checkbox(
                    checked: t.done,
                    onChanged: (v) => _todos.setDone(t.id, v ?? false),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.text,
                      style: TextStyle(
                        fontSize: 12,
                        decoration:
                            t.done ? TextDecoration.lineThrough : null,
                        color: t.done ? secondaryTextColor(context) : null,
                      ),
                    ),
                  ),
                  MergeSemantics(
                    child: Tooltip(
                      message: 'delete-text'.i18n(),
                      child: IconButton(
                        icon: Icon(FluentIcons.clear,
                            size: 10, color: secondaryTextColor(context)),
                        onPressed: () => _todos.remove(t.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _todoInputController,
                    placeholder: 'ai-tasks-add-hint-text'.i18n(),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) {
                        _todos.add(v);
                        _todoInputController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                MergeSemantics(
                  child: Tooltip(
                    message: 'ai-tasks-add-hint-text'.i18n(),
                    child: IconButton(
                  icon: const Icon(FluentIcons.add, size: 12),
                  onPressed: () {
                    final v = _todoInputController.text.trim();
                    if (v.isNotEmpty) {
                      _todos.add(v);
                      _todoInputController.clear();
                    }
                  },
                ),
                  ),
                ),
              ],
            ),
          ),
              ]),
            ),
          ),
        ],
        Container(height: 1, color: surfaceBorderColor(context)),
      ],
    );
  }

  Widget _buildMessageBubble(AiMessage msg) {
    // A tool note: a compact "ran <tool>" chip, not a chat bubble, so the
    // user can see what the assistant actually did on their machine.
    if (msg.role == 'tool') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 36),
        child: Row(
          children: [
            Icon(FluentIcons.processing,
                size: 11, color: secondaryTextColor(context)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'ai-ran-tool-text'.i18n([msg.content]),
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: secondaryTextColor(context),
                ),
              ),
            ),
          ],
        ),
      );
    }
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
                    : subtleFillColor(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: msg.role == 'assistant'
                  ? MarkdownBody(
                      data: msg.content,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 12),
                        code: TextStyle(
                          fontSize: 11,
                          backgroundColor: subtleFillColor(context),
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: subtleFillColor(context),
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
                color: subtleFillColor(context),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              // A person glyph — the user avatar rendered as a plus sign
              // (audit PS-37).
              child: Icon(
                FluentIcons.contact,
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
    _todos.removeListener(_onTodosChanged);
    _sessionsFlyout.dispose();
    _inputController.dispose();
    _todoInputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
