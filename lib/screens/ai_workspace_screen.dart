import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/api/wsl_errors.dart';
import 'package:wsl2distromanager/components/error_view.dart';
import 'package:localization/localization.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/api/ai_workspace/service.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/wsl.dart' show formatElapsed;
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/busy_button.dart';
import 'package:wsl2distromanager/components/named_button.dart';
import 'package:wsl2distromanager/components/beta_badge.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/nav/router.dart';

/// The five things a card can be asked to do, for per-action busy state
/// (audit PS-15).
enum _CardAction { install, start, stop, dashboard, uninstall }

/// How often a tool still reporting [ToolStatus.starting] is re-probed.
/// Open WebUI's migrations take ~2 minutes, so this runs a good few times;
/// each tick is one cheap `docker inspect`.
const Duration _kStartingPoll = Duration(seconds: 10);

/// How often the card repaints while an install is streaming. The service
/// keeps only the newest line, so this is a repaint rate, not a sampling
/// rate — nothing is lost by missing a line, and one second is fast enough
/// to read as live without rebuilding the page on every `npm` write.
const Duration _kInstallProgressPoll = Duration(seconds: 1);

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

  /// Which action is in flight per tool. One shared busy flag used to put
  /// the spinner on every enabled button on the card at once — Start spun
  /// Uninstall, opening the dashboard spun Stop and Uninstall (audit PS-15).
  /// The other controls still disable while something runs; only the pressed
  /// one spins.
  final Map<AiWorkspaceTool, _CardAction> _busyAction = {};
  // Each tool clears independently as its own check resolves.
  final Set<AiWorkspaceTool> _checkingTools = {...AiWorkspaceTool.values};
  // Re-attaches this page to an install that a previous instance started.
  Timer? _installWatch;
  // Tools this page has seen mid-install. A tool that drops out of the
  // service's installing set while it is in here has just finished, and is
  // the one that needs its real status read back.
  final Set<AiWorkspaceTool> _watchedInstalls = {};
  Timer? _startingWatch;

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
    _startingWatch?.cancel();
    super.dispose();
  }

  /// A tool in [ToolStatus.starting] settles on its own once its container
  /// finishes migrating — the health gate only has to be asked again. Nothing
  /// else on this page re-probes a tool that has already been checked, so
  /// without this poll the card sits on "Starting up..." with Start, Stop and
  /// the dashboard all disabled until the user happens to click something.
  /// Observed against a real Open WebUI container: `docker inspect` reported
  /// `healthy` while the card still read "Startet...".
  void _syncStartingWatch() {
    if (_startingTools().isEmpty) {
      _startingWatch?.cancel();
      _startingWatch = null;
      return;
    }
    // Already polling — a second timer would just double the probe rate.
    if (_startingWatch != null) return;
    _startingWatch = Timer.periodic(_kStartingPoll, (timer) async {
      final pending = _startingTools();
      if (!mounted || pending.isEmpty) {
        timer.cancel();
        _startingWatch = null;
        return;
      }
      await Future.wait(pending.map(_service.refreshStatus));
      if (mounted) setState(() {});
    });
  }

  List<AiWorkspaceTool> _startingTools() => AiWorkspaceTool.values
      .where((tool) => _service.getState(tool)?.status == ToolStatus.starting)
      .toList();

  /// Ticks while any install is running. An install started by the button on
  /// this page and one inherited from a previous instance of it are the same
  /// case — the service owns both — so the page only has to watch: each tick
  /// repaints the streamed progress line under the card, and a tool that has
  /// left [AiWorkspaceService.isInstalling] gets its real status read back.
  void _syncInstallWatch() {
    _watchedInstalls
        .addAll(AiWorkspaceTool.values.where(_service.isInstalling));
    if (_watchedInstalls.isEmpty) {
      _installWatch?.cancel();
      _installWatch = null;
      return;
    }
    // Already ticking — a second timer would just double the repaint rate.
    if (_installWatch != null) return;
    _installWatch = Timer.periodic(_kInstallProgressPoll, (timer) async {
      if (!mounted) {
        timer.cancel();
        _installWatch = null;
        return;
      }
      final finished =
          _watchedInstalls.where((t) => !_service.isInstalling(t)).toList();
      _watchedInstalls.removeAll(finished);
      if (_watchedInstalls.isEmpty) {
        timer.cancel();
        _installWatch = null;
      }
      // Every tick, not only the last one: the progress line changes while
      // the installer is still running, which is the whole point of showing
      // it. Nothing here touches WSL, so a repaint is all it costs.
      setState(() {});
      for (final tool in finished) {
        await _service.refreshStatus(tool);
      }
      if (mounted && finished.isNotEmpty) {
        setState(_syncStartingWatch);
      }
    });
  }

  Future<void> _initService() async {
    if (_service.toolStates.isEmpty) {
      _service.seedToolStates();
    }
    _syncInstallWatch();

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
          setState(() {
            _checkingTools.remove(tool);
            // A tool seeded or probed as `starting` has to keep being asked.
            _syncStartingWatch();
          });
        }
      }));
    }

    // Re-entering the page finds every tool already `checked`, so the loop
    // above probes nothing — but one of them may still be mid-migration from a
    // start issued before the user navigated away.
    _syncStartingWatch();
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
      // error message. install() does this too — doing it here as well is
      // what makes the card update on the same frame as the button press.
      _service.clearError(tool);
      _busyTools.add(tool);
      _busyAction[tool] = _CardAction.install;
    });
    // install() marks the tool as installing before its first await, so by
    // the time this returns the future the service already knows about it and
    // the progress ticker can start on the same frame as the button press.
    final install = _service.install(tool);
    if (mounted) setState(_syncInstallWatch);
    try {
      await install;
    } finally {
      if (context.mounted) {
        setState(() {
          _busyTools.remove(tool);
          _busyAction.remove(tool);
        });
      }
    }
  }

  Future<void> _handleStart(AiWorkspaceTool tool) async {
    if (!context.mounted) return;
    setState(() {
      _service.clearError(tool);
      _busyTools.add(tool);
      _busyAction[tool] = _CardAction.start;
    });
    try {
      await _service.start(tool);
    } finally {
      if (context.mounted) {
        setState(() {
          _busyTools.remove(tool);
          // start() leaves a health-gated tool on `starting`; poll it out.
          _syncStartingWatch();
        });
      }
    }
  }

  /// A failed install or start holds the card until the user acknowledges it.
  /// Dismissing releases it and asks WSL what the truth actually is.
  Future<void> _handleDismissError(AiWorkspaceTool tool) async {
    if (!context.mounted) return;
    setState(() {
      _service.clearError(tool);
      _checkingTools.add(tool);
    });
    await _service.refreshStatus(tool);
    if (mounted) {
      setState(() {
        _checkingTools.remove(tool);
        _syncStartingWatch();
      });
    }
  }

  Future<void> _handleStop(AiWorkspaceTool tool) async {
    if (!context.mounted) return;
    setState(() {
      _busyTools.add(tool);
      _busyAction[tool] = _CardAction.stop;
    });
    try {
      await _service.stop(tool);
    } finally {
      if (context.mounted) {
        setState(() {
          _busyTools.remove(tool);
          _busyAction.remove(tool);
        });
      }
    }
  }

  Future<void> _handleOpenDashboard(AiWorkspaceTool tool) async {
    if (!context.mounted) return;
    setState(() {
      _busyTools.add(tool);
      _busyAction[tool] = _CardAction.dashboard;
    });
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
        setState(() {
          _busyTools.remove(tool);
          _busyAction.remove(tool);
        });
      }
    }
  }

  Future<void> _handleUninstall(AiWorkspaceTool tool) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // The tool's name used to float on a bare line above a sentence that
      // called it "this tool" (PS-28), and the button that removes it was the
      // accent-blue primary every harmless dialog uses, while every other
      // destructive confirmation in the app submits in red (PS-27).
      builder: (dialogContext) => ContentDialog(
        title: Text('ai-workspace-uninstall-title'.i18n([_toolName(tool)])),
        content: Text('ai-workspace-uninstall-confirm'.i18n([_toolName(tool)])),
        actions: [
          FilledButton(
            key: const ValueKey('test-ai-uninstall-confirm'),
            style: ButtonStyle(
              backgroundColor: ButtonState.all(Colors.red),
              foregroundColor: ButtonState.all(Colors.white),
            ),
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(true),
            child: Text('ai-workspace-uninstall-btn'.i18n()),
          ),
          Button(
            key: const ValueKey('test-ai-uninstall-cancel'),
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(false),
            child: Text('cancel-text'.i18n()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!context.mounted) return;
    setState(() {
      _busyTools.add(tool);
      _busyAction[tool] = _CardAction.uninstall;
    });
    try {
      final success = await _service.uninstall(tool);
      if (mounted) {
        setState(() {}); // Rebuild UI after uninstall completes
        if (success) {
          // One key with a placeholder — word order was baked into Dart
          // concatenation, so no locale could move the subject (audit PS-29).
          Notify.message('ai-workspace-uninstall-success'.i18n([_toolName(tool)]),
              severity: InfoBarSeverity.success);
        } else {
          final state = _service.getState(tool);
          Notify.message(state?.errorMessage ?? 'ai-workspace-uninstall-failed'.i18n());
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyTools.remove(tool);
          _busyAction.remove(tool);
        });
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
            // Was 'Error loading AI Workspace: <Exception.toString()>' —
            // hardcoded English wrapped around a class name (audit PS-31).
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520.0),
              child: ErrorBody(
                failure: WslFailure.from(_error),
                leading: 'ai-workspace-load-failed-text'.i18n(),
              ),
            ),
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
  ///
  /// [fill] takes the full width and ellipsises the label instead of sizing
  /// to it — installer output is arbitrarily long and would otherwise
  /// overflow the card. The default stays min-sized for the header, where
  /// this sits next to a [Spacer].
  Widget _buildInlineStatus(String label, {bool fill = false}) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: secondaryTextColor(context)),
    );
    return Row(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 12,
          child: ProgressRing(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        if (fill) Expanded(child: text) else text,
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
    // The service, not this page, owns install progress: the page is rebuilt
    // from scratch when the user navigates away and back, but the install
    // keeps running.
    final isInstalling = _service.isInstalling(tool);
    // For the whole of a six-minute install the pill read "Not Installed" and
    // the dot stayed grey, directly above a live spinner (audit PS-19): the
    // one element whose job is to say what state the tool is in said the
    // wrong thing for the entire operation.
    final statusColors =
        _statusColors(state?.status, installing: isInstalling);
    final isBusy = _busyTools.contains(tool) || isInstalling;
    // `error` means the last attempt failed, not that the tool is present —
    // a retry has to stay reachable.
    final canInstall = state?.status == ToolStatus.notInstalled ||
        state?.status == ToolStatus.error;
    // The service keeps the last streamed line after the install ends. A
    // failure is the case that needs it — the error text is whatever the
    // killed shell managed to write, which for a timeout is nothing at all.
    final lastOutput = state?.status == ToolStatus.error
        ? _service.installProgress(tool)
        : null;

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
                    color: statusColors.dot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(name, style: FluentTheme.of(context).typography.subtitle),
                const Spacer(),
                isChecking
                    ? _buildInlineStatus(
                        'ai-workspace-checking-status-text'.i18n())
                    : isInstalling
                        ? _badge(
                            'installing-text'.i18n(),
                            statusColors,
                            key: ValueKey('test-ai-installing-badge-'
                                '${tool.name}'),
                          )
                        : _statusBadge(state?.status),
              ],
            ),
            if (state?.installPath != null) ...[
              const SizedBox(height: 4),
              // Keyed, and the internal `cmd://<binary>` existence-check
              // sentinel stays internal — "Installed: cmd://openclaw" leaked
              // an implementation detail as a path (audit PS-26).
              Text(
                'ai-workspace-installed-at-text'.i18n([
                  state!.installPath!.startsWith('cmd://')
                      ? state.installPath!.substring('cmd://'.length)
                      : state.installPath!
                ]),
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
            ],
            if (state?.errorMessage != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      WslFailure.from(state!.errorMessage).shortReason,
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                  // Without this a sticky failure has no way out: the status
                  // probe deliberately leaves it alone until the user acts.
                  NamedIconButton(
                    key: ValueKey('test-ai-dismiss-error-${tool.name}'),
                    label: 'close-text'.i18n(),
                    icon: FluentIcons.cancel,
                    iconSize: 10,
                    onPressed: () => _handleDismissError(tool),
                  ),
                ],
              ),
            ],
            // Streamed installer output. A Hermes install runs for minutes at
            // a time, and without this the card is a bare spinner: a stall
            // and steady progress look exactly alike.
            if (_service.isInstalling(tool)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey('test-ai-install-progress-${tool.name}'),
                      child: _buildInlineStatus(
                        _service.installProgress(tool) ??
                            'ai-workspace-install-progress-text'.i18n(),
                        fill: true,
                      ),
                    ),
                  ),
                  // The clock is the point: the streamed line above it sat
                  // unchanged for two minutes of a six-minute install, and a
                  // still line next to a moving one is a stall, while a still
                  // line on its own is unreadable (audit PS-18).
                  const SizedBox(width: 8),
                  Text(
                    formatElapsed(_service.installElapsed(tool) ?? Duration.zero),
                    key: ValueKey('test-ai-install-elapsed-${tool.name}'),
                    style: TextStyle(
                        fontSize: 12, color: secondaryTextColor(context)),
                  ),
                  const SizedBox(width: 8),
                  NamedIconButton(
                    key: ValueKey('test-ai-install-cancel-${tool.name}'),
                    label: 'stopinstall-text'.i18n(),
                    icon: FluentIcons.stop,
                    iconSize: 12,
                    onPressed: _service.canCancelInstall(tool)
                        ? () => _service.cancelInstall(tool)
                        : null,
                  ),
                ],
              ),
            ] else if (lastOutput != null) ...[
              const SizedBox(height: 4),
              Text(
                'ai-workspace-install-last-output-text'.i18n([lastOutput]),
                key: ValueKey('test-ai-install-last-output-${tool.name}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12, color: secondaryTextColor(context)),
              ),
            ],
            const SizedBox(height: 12),
            // One primary action per state, and only the actions that state
            // can ever run. The old row kept Install, Start and Stop all
            // visible with every non-applicable one disabled, so an installed
            // tool wore a permanently dead "Installed" button repeating the
            // badge beside it (audit PS-22), a running tool's only filled
            // button was Stop (PS-23), and each disabled `FilledButton`
            // painted white on grey at 1.71:1 (PS-21) — plain `Button`s keep
            // their disabled foreground legible.
            Row(
              children: [
                if (canInstall)
                  _buildAction(
                    key: ValueKey('test-ai-install-${tool.name}'),
                    // A failed install leaves the tool in `error`, which is
                    // not "installed" — a retry has to stay reachable.
                    label: state?.status == ToolStatus.error
                        ? 'retry-text'.i18n()
                        : 'install-text'.i18n(),
                    enabled: !isBusy && !isChecking,
                    busy: _busyAction[tool] == _CardAction.install,
                    onPressed: () => _handleInstall(tool),
                  ),
                if (state?.status == ToolStatus.stopped)
                  _buildAction(
                    key: ValueKey('test-ai-start-${tool.name}'),
                    label: 'start-text'.i18n(),
                    enabled: !isBusy && !isChecking,
                    busy: _busyAction[tool] == _CardAction.start,
                    onPressed: () => _handleStart(tool),
                  ),
                if (state?.status == ToolStatus.running ||
                    state?.status == ToolStatus.starting) ...[
                  // The thing to do with a running AI tool is to open it —
                  // Open Dashboard is the primary, not Stop (PS-23). Shown
                  // but disabled while starting: hiding it entirely reads as
                  // "this tool has no dashboard" rather than "not yet".
                  _maybeTooltip(
                    state?.status == ToolStatus.starting
                        ? 'ai-workspace-startingup-hint-text'.i18n()
                        : null,
                    BusyButton(
                      key: ValueKey('test-ai-open-dashboard-${tool.name}'),
                      filled: true,
                      label: 'ai-workspace-open-dashboard-text'.i18n(),
                      busy: _busyAction[tool] == _CardAction.dashboard,
                      minWidth: 72.0,
                      onPressed:
                          (!isBusy && state?.status == ToolStatus.running)
                              ? () => _handleOpenDashboard(tool)
                              : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Live while starting too: a tool stuck mid-migration used
                  // to leave Uninstall as the only enabled way out (PS-16).
                  BusyButton(
                    key: ValueKey('test-ai-stop-${tool.name}'),
                    label: 'stop-text'.i18n(),
                    busy: _busyAction[tool] == _CardAction.stop,
                    minWidth: 72.0,
                    onPressed: (!isBusy &&
                            (state?.status == ToolStatus.running ||
                                state?.status == ToolStatus.starting))
                        ? () => _handleStop(tool)
                        : null,
                  ),
                ],
                const Spacer(),
                BusyButton(
                  key: ValueKey('test-ai-uninstall-${tool.name}'),
                  label: 'uninstall-text'.i18n(),
                  busy: _busyAction[tool] == _CardAction.uninstall,
                  minWidth: 72.0,
                  onPressed: (state?.status != ToolStatus.notInstalled &&
                          !isBusy &&
                          !isChecking)
                      ? () => _handleUninstall(tool)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction({
    required Key key,
    required String label,
    required bool enabled,
    required bool busy,
    required VoidCallback onPressed,
  }) {
    // Same reason as the create screen's Create button: a button that becomes
    // a bare spinner loses both its width and its name (audit CI-15).
    return BusyButton(
      key: key,
      filled: true,
      label: label,
      busy: busy,
      minWidth: 72.0,
      onPressed: enabled ? onPressed : null,
    );
  }

  Widget _statusBadge(ToolStatus? status) =>
      _badge(_statusLabel(status), _statusColors(status));

  /// The pill itself. Taken out of [_statusBadge] because an install is not a
  /// [ToolStatus] — it is a transition between two of them — and it still has
  /// to be able to say so (audit PS-19).
  Widget _badge(String label, _StatusColors colors, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: colors.foreground,
        ),
      ),
    );
  }

  /// The palette a status renders with, per theme brightness.
  ///
  /// The old single-colour version painted `Colors.orange` on 10% of itself —
  /// 2.70:1 in light, and the `Colors.grey` fallback was **1.03:1** against a
  /// dark card, an invisible pill (audit TL-01, TL-04, PS-20). Each
  /// brightness now gets a text shade measured against its own tint; every
  /// pair below clears AA's 4.5:1 on both page colours. `notInstalled` uses
  /// the theme's own secondary text instead of a status colour, so the state
  /// that means "nothing here" stops being the most assertive of the four
  /// (PS-24).
  _StatusColors _statusColors(ToolStatus? status, {bool installing = false}) {
    final dark = FluentTheme.of(context).brightness.isDark;
    _StatusColors of(AccentColor base, Color darkFg) => _StatusColors(
          foreground: dark ? darkFg : base.darkest,
          tint: base.normal.withValues(alpha: 0.15),
          dot: base.defaultBrushFor(
              dark ? Brightness.dark : Brightness.light),
        );
    if (installing || status == ToolStatus.starting) {
      return of(Colors.blue, Colors.blue.lightest);
    }
    switch (status) {
      case ToolStatus.running:
        return of(Colors.green, const Color(0xFF8FC48F));
      case ToolStatus.stopped:
        return of(Colors.orange, Colors.orange.lightest);
      case ToolStatus.error:
        return of(Colors.red, const Color(0xFFF4949C));
      default:
        return _StatusColors(
          foreground: secondaryTextColor(context),
          tint: subtleFillColor(context),
          dot: disabledTextColor(context),
        );
    }
  }

  /// A tooltip only where it says something the label does not (audit
  /// PS-30). A null [message] leaves [child] bare.
  Widget _maybeTooltip(String? message, Widget child) =>
      message == null ? child : Tooltip(message: message, child: child);

  String _statusLabel(ToolStatus? status) {
    if (status == ToolStatus.running) return 'running-text'.i18n();
    if (status == ToolStatus.starting) return 'startingup-text'.i18n();
    if (status == ToolStatus.stopped) return 'stopped-text'.i18n();
    if (status == ToolStatus.error) return 'error-text'.i18n();
    return 'notinstalled-text'.i18n();
  }
}

/// The colours one status pill needs: an AA-checked text colour for the
/// current brightness, the tint behind it, and the dot beside the tool name.
class _StatusColors {
  const _StatusColors(
      {required this.foreground, required this.tint, required this.dot});
  final Color foreground;
  final Color tint;
  final Color dot;
}
