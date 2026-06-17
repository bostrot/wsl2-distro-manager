// AI Workspace screen for managing Hermes Agent, OpenClaw, and Open WebUI tools.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:provider/provider.dart';
import 'package:wsl2distromanager/api/ai_workspace/service.dart';
import 'package:wsl2distromanager/api/execution/broker.dart';

class AiWorkspacePage extends StatefulWidget {
  const AiWorkspacePage({super.key});

  @override
  State<AiWorkspacePage> createState() => _AiWorkspacePageState();
}

class _AiWorkspacePageState extends State<AiWorkspacePage> {
  late final AiWorkspaceService _service;
  bool _loading = true;
  String? _error;
  final Set<AiWorkspaceTool> _busyTools = {};

  @override
  void initState() {
    super.initState();
    // Wire ExecutionBroker from app initialization.
    _service = AiWorkspaceService(
      broker: context.read<ExecutionBroker>(),
    );
    _initService();
  }

  Future<void> _initService() async {
    try {
      await _service.init();
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleInstall(AiWorkspaceTool tool) async {
    setState(() => _busyTools.add(tool));
    try {
      await _service.install(tool);
    } finally {
      if (mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
  }

  Future<void> _handleStart(AiWorkspaceTool tool) async {
    setState(() => _busyTools.add(tool));
    try {
      await _service.start(tool);
    } finally {
      if (mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
  }

  Future<void> _handleStop(AiWorkspaceTool tool) async {
    setState(() => _busyTools.add(tool));
    try {
      await _service.stop(tool);
    } finally {
      if (mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
  }

  Future<void> _handleUninstall(AiWorkspaceTool tool) async {
    // Show confirmation dialog first.
    final confirmed = await showDialog<bool>(
      context: context,
          builder: (_) => ContentDialog(
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
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('ai-workspace-uninstall-btn'.i18n()),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel-text'.i18n()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busyTools.add(tool));
    try {
      await _service.uninstall(tool);
    } finally {
      if (mounted) {
        setState(() => _busyTools.remove(tool));
      }
    }
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
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 32,
          child: ProgressRing(),
        ),
      );
    }

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
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _initService();
              },
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
          Text(
            'ai-workspace-title'.i18n(),
            style: FluentTheme.of(context).typography.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'ai-workspace-subtitle'.i18n(),
            style: FluentTheme.of(context).typography.bodyStrong,
          ),
          const SizedBox(height: 24),
          ...AiWorkspaceTool.values.map((tool) => _buildToolCard(tool)),
        ],
      ),
    );
  }

  Widget _buildToolCard(AiWorkspaceTool tool) {
    final state = _service.getState(tool);
    final name = const {
      AiWorkspaceTool.hermesAgent: 'Hermes Agent',
      AiWorkspaceTool.openClaw: 'OpenClaw',
      AiWorkspaceTool.openWebUi: 'Open WebUI',
    }[tool]!;

    final statusColor = _statusToColor(state?.status);
    final isBusy = _busyTools.contains(tool);

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
                _statusBadge(state?.status),
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
                  label: state?.status == ToolStatus.notInstalled
                      ? 'install-text'.i18n()
                      : 'installed-text'.i18n(),
                  enabled: state?.status == ToolStatus.notInstalled && !isBusy,
                  busy: isBusy && state?.status == ToolStatus.notInstalled,
                  onPressed: () => _handleInstall(tool),
                ),
                const SizedBox(width: 8),
                _buildAction(
                  label: 'start-text'.i18n(),
                  enabled: state?.status == ToolStatus.stopped && !isBusy,
                  busy: isBusy && state?.status == ToolStatus.stopped,
                  onPressed: () => _handleStart(tool),
                ),
                const SizedBox(width: 8),
                _buildAction(
                  label: 'stop-text'.i18n(),
                  enabled: state?.status == ToolStatus.running && !isBusy,
                  busy: isBusy && state?.status == ToolStatus.running,
                  onPressed: () => _handleStop(tool),
                ),
                const Spacer(),
                Button(
                  onPressed: (state?.status != ToolStatus.notInstalled && !isBusy)
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
