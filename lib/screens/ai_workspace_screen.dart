import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/api/ai_workspace/service.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/beta_badge.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/nav/router.dart';

class AiWorkspacePage extends StatefulWidget {
  const AiWorkspacePage({super.key});

  @override
  State<AiWorkspacePage> createState() => _AiWorkspacePageState();
}

class _AiWorkspacePageState extends State<AiWorkspacePage> {
  late final AiWorkspaceService _service;
  // Gates only the distro check, not the page — cards render immediately.
  bool _preparingDistro = true;
  String? _error;
  final Set<AiWorkspaceTool> _busyTools = {};
  // Each tool clears independently as its own check resolves.
  final Set<AiWorkspaceTool> _checkingTools = {...AiWorkspaceTool.values};
  // Re-attaches this page to an install that a previous instance started.
  Timer? _installWatch;

  bool get _isPro {
    try {
      return GlobalVariable.testProEnabled || LicenseManager().isPro;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Shared instance from main.dart — startup already began these checks.
    _service = context.read<AiWorkspaceService>();
    if (_isPro) {
      // Spinner only where nothing is known yet; cached state renders at
      // once and is refreshed below without blocking the UI.
      _checkingTools
        ..clear()
        ..addAll(AiWorkspaceTool.values.where(
            (tool) => _service.getState(tool)?.hasKnownStatus != true));
      _initService();
    } else {
      // Skip touching WSL entirely for non-Pro users — nothing to probe.
      _preparingDistro = false;
      _checkingTools.clear();
    }
  }

  @override
  void dispose() {
    _installWatch?.cancel();
    super.dispose();
  }

  /// An install started before this page was rebuilt is still running in the
  /// service. Poll until it finishes so the card stops showing progress and
  /// picks up the real status.
  void _watchOngoingInstalls() {
    final ongoing = AiWorkspaceTool.values.where(_service.isInstalling).toSet();
    if (ongoing.isEmpty) return;
    _installWatch?.cancel();
    _installWatch = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final finished = ongoing.where((t) => !_service.isInstalling(t)).toSet();
      if (finished.isEmpty) return;
      timer.cancel();
      for (final tool in finished) {
        await _service.refreshStatus(tool);
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _initService() async {
    if (_service.toolStates.isEmpty) {
      _service.seedToolStates();
    }
    _watchOngoingInstalls();

    try {
      await _service.ensureDistro();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _preparingDistro = false;
          _checkingTools.clear();
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _preparingDistro = false);
    }

    // Refresh anything not yet verified this session, cached or not.
    // Results land in place without flashing a spinner.
    for (final tool in AiWorkspaceTool.values) {
      if (_service.getState(tool)?.checked == true) continue;
      unawaited(_service.refreshStatus(tool).then((_) {
        if (mounted) {
          setState(() => _checkingTools.remove(tool));
        }
      }));
    }
  }

  Future<void> _retryInit() async {
    // Clear `checked` so the retry actually re-probes everything.
    for (final tool in AiWorkspaceTool.values) {
      _service.getState(tool)?.checked = false;
    }
    setState(() {
      _error = null;
      _preparingDistro = true;
      _checkingTools
        ..clear()
        ..addAll(AiWorkspaceTool.values);
    });
    await _initService();
  }

  Future<void> _handleInstall(AiWorkspaceTool tool) async {
    if (!context.mounted) return;
    setState(() {
      // Drop the previous failure so a retry does not render under a stale
      // error message.
      final state = _service.getState(tool);
      if (state?.status == ToolStatus.error) {
        state?.errorMessage = null;
        state?.status = ToolStatus.notInstalled;
      }
      _busyTools.add(tool);
    });
    try {
      await _service.install(tool);
    } finally {
      if (context.mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
  }

  Future<void> _handleStart(AiWorkspaceTool tool) async {
    if (!context.mounted) return;
    setState(() => _busyTools.add(tool));
    try {
      await _service.start(tool);
    } finally {
      if (context.mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
  }

  Future<void> _handleStop(AiWorkspaceTool tool) async {
    if (!context.mounted) return;
    setState(() => _busyTools.add(tool));
    try {
      await _service.stop(tool);
    } finally {
      if (context.mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
  }

  Future<void> _handleOpenDashboard(AiWorkspaceTool tool) async {
    if (!context.mounted) return;
    setState(() => _busyTools.add(tool));
    try {
      final url = await _service.getDashboardUrl(tool);
      if (url == null) {
        Notify.message('ai-workspace-dashboard-failed-text'.i18n());
        return;
      }
      // No canLaunchUrl gate: on Windows it reports false for perfectly
      // launchable http URLs, which is what made a healthy dashboard look
      // unreachable. Every other launch site in this app calls launchUrl
      // directly for the same reason.
      final uri = Uri.parse(url);
      try {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          Notify.message('ai-workspace-dashboard-failed-text'.i18n());
        }
      } catch (_) {
        Notify.message('ai-workspace-dashboard-failed-text'.i18n());
      }
    } finally {
      if (context.mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
  }

  Future<void> _handleUninstall(AiWorkspaceTool tool) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: Text('ai-workspace-uninstall-title'.i18n()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_toolName(tool)),
            const SizedBox(height: 8),
            Text('ai-workspace-uninstall-confirm'.i18n()),
          ],
        ),
        actions: [
          FilledButton(
            key: const ValueKey('test-ai-uninstall-confirm'),
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(true),
            child: Text('ai-workspace-uninstall-btn'.i18n()),
          ),
          Button(
            key: const ValueKey('test-ai-uninstall-cancel'),
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(false),
            child: Text('cancel-text'.i18n()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!context.mounted) return;
    setState(() => _busyTools.add(tool));
    try {
      final success = await _service.uninstall(tool);
      if (mounted) {
        setState(() {}); // Rebuild UI after uninstall completes
        if (success) {
          Notify.message('${_toolName(tool)} ${'ai-workspace-uninstall-success'.i18n()}');
        } else {
          final state = _service.getState(tool);
          Notify.message(state?.errorMessage ?? 'ai-workspace-uninstall-failed'.i18n());
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
  }

  Widget _buildPaywall(BuildContext context) {
    final accent = FluentTheme.of(context).accentColor;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.25),
                    accent.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(FluentIcons.robot, size: 36, color: accent),
            ),
            const SizedBox(height: 20),
            Text(
              'ai-workspace-title'.i18n(),
              style: FluentTheme.of(context).typography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'ai-workspace-pro-required-text'.i18n(),
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryTextColor(context)),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('test-ai-workspace-upgrade'),
              onPressed: () => router.pushNamed('license'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.crown, size: 14),
                  const SizedBox(width: 8),
                  Text('upgrade-pro-text'.i18n()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _toolName(AiWorkspaceTool tool) {
    switch (tool) {
      case AiWorkspaceTool.hermesAgent: return 'Hermes Agent';
      case AiWorkspaceTool.openClaw: return 'OpenClaw';
      case AiWorkspaceTool.openWebUi: return 'Open WebUI';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPro) {
      return _buildPaywall(context);
    }

    // Only a missing distro blocks the whole page; everything else renders.
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FluentIcons.error, size: 48),
            const SizedBox(height: 16),
            Text('Error loading AI Workspace: $_error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _retryInit,
              child: Text('retry-text'.i18n()),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ai-workspace-title'.i18n(),
                style: FluentTheme.of(context).typography.titleLarge,
              ),
              const SizedBox(width: 10),
              const BetaBadge(key: ValueKey('test-ai-workspace-beta-badge')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ai-workspace-subtitle'.i18n(),
            style: FluentTheme.of(context).typography.bodyStrong,
          ),
          const SizedBox(height: 12),
          const BetaBanner(),
          const SizedBox(height: 16),
          if (_preparingDistro) ...[
            _buildInlineStatus('ai-workspace-checking-env-text'.i18n()),
            const SizedBox(height: 16),
          ],
          ...AiWorkspaceTool.values.map((tool) => _buildToolCard(tool)),
        ],
      ),
    );
  }

  /// Spinner plus a grey label saying what is being waited on.
  Widget _buildInlineStatus(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 12,
          child: ProgressRing(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: secondaryTextColor(context)),
        ),
      ],
    );
  }

  Widget _buildToolCard(AiWorkspaceTool tool) {
    final state = _service.getState(tool);
    final name = const {
      AiWorkspaceTool.hermesAgent: 'Hermes Agent',
      AiWorkspaceTool.openClaw: 'OpenClaw',
      AiWorkspaceTool.openWebUi: 'Open WebUI',
    }[tool]!;

    final isChecking = _checkingTools.contains(tool);
    final statusColor = _statusToColor(state?.status);
    // The service, not this page, owns install progress: the page is rebuilt
    // from scratch when the user navigates away and back, but the install
    // keeps running.
    final isBusy = _busyTools.contains(tool) || _service.isInstalling(tool);
    // `error` means the last attempt failed, not that the tool is present —
    // a retry has to stay reachable.
    final canInstall = state?.status == ToolStatus.notInstalled ||
        state?.status == ToolStatus.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(name, style: FluentTheme.of(context).typography.subtitle),
                const Spacer(),
                isChecking
                    ? _buildInlineStatus(
                        'ai-workspace-checking-status-text'.i18n())
                    : _statusBadge(state?.status),
              ],
            ),
            if (state?.installPath != null) ...[
              const SizedBox(height: 4),
              Text(
                'Installed: ${state!.installPath}',
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
            ],
            if (state?.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                'Error: ${state!.errorMessage}',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _buildAction(
                  // A failed install leaves the tool in `error`, which is not
                  // "installed" — labelling it that way and greying the
                  // button out strands the user with no way to try again.
                  label: canInstall
                      ? (state?.status == ToolStatus.error
                          ? 'retry-text'.i18n()
                          : 'install-text'.i18n())
                      : 'installed-text'.i18n(),
                  enabled: canInstall && !isBusy && !isChecking,
                  busy: isBusy && canInstall,
                  onPressed: () => _handleInstall(tool),
                ),
                const SizedBox(width: 8),
                _buildAction(
                  label: 'start-text'.i18n(),
                  enabled: state?.status == ToolStatus.stopped &&
                      !isBusy &&
                      !isChecking,
                  busy: isBusy && state?.status == ToolStatus.stopped,
                  onPressed: () => _handleStart(tool),
                ),
                const SizedBox(width: 8),
                _buildAction(
                  label: 'stop-text'.i18n(),
                  enabled: state?.status == ToolStatus.running &&
                      !isBusy &&
                      !isChecking,
                  busy: isBusy && state?.status == ToolStatus.running,
                  onPressed: () => _handleStop(tool),
                ),
                if (state?.status == ToolStatus.running) ...[
                  const SizedBox(width: 8),
                  Button(
                    key: ValueKey('test-ai-open-dashboard-${tool.name}'),
                    onPressed: !isBusy ? () => _handleOpenDashboard(tool) : null,
                    child: isBusy
                        ? SizedBox.square(
                            dimension: 16, child: ProgressRing())
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FluentIcons.open_in_new_window,
                                  size: 12),
                              const SizedBox(width: 6),
                              Text('ai-workspace-open-dashboard-text'.i18n()),
                            ],
                          ),
                  ),
                ],
                const Spacer(),
                Button(
                  key: ValueKey('test-ai-uninstall-${tool.name}'),
                  onPressed: (state?.status != ToolStatus.notInstalled &&
                          !isBusy &&
                          !isChecking)
                      ? () => _handleUninstall(tool)
                      : null,
                  child: isBusy && state?.status != ToolStatus.notInstalled
                      ? SizedBox.square(
                          dimension: 16,
                          child: ProgressRing(),
                        )
                      : Text('uninstall-text'.i18n()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction({
    required String label,
    required bool enabled,
    required bool busy,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      child: busy
          ? SizedBox.square(dimension: 16, child: ProgressRing())
          : Text(label),
    );
  }

  Widget _statusBadge(ToolStatus? status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusToColor(status).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          fontSize: 12,
          color: _statusToColor(status),
        ),
      ),
    );
  }

  Color _statusToColor(ToolStatus? status) {
    if (status == ToolStatus.running) return Colors.green;
    if (status == ToolStatus.stopped) return Colors.orange;
    if (status == ToolStatus.error) return Colors.red;
    return Colors.grey;
  }

  String _statusLabel(ToolStatus? status) {
    if (status == ToolStatus.running) return 'running-text'.i18n();
    if (status == ToolStatus.stopped) return 'stopped-text'.i18n();
    if (status == ToolStatus.error) return 'error-text'.i18n();
    return 'notinstalled-text'.i18n();
  }
}
