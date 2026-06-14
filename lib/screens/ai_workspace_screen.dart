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
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _handleInstall(AiWorkspaceTool tool) async {
    // TODO: Show progress dialog.
    await _service.install(tool);
    setState(() {});
  }

  Future<void> _handleStart(AiWorkspaceTool tool) async {
    await _service.start(tool);
    setState(() {});
  }

  Future<void> _handleStop(AiWorkspaceTool tool) async {
    await _service.stop(tool);
    setState(() {});
  }

  Future<void> _handleUninstall(AiWorkspaceTool tool) async {
    // TODO: Show confirmation dialog first.
    await _service.uninstall(tool);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: ProgressRing());
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
              child: const Text('Retry'),
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
            'Manage AI workspace tools for your WSL environment.',
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
    final config = const {
      AiWorkspaceTool.hermesAgent: 'Hermes Agent',
      AiWorkspaceTool.openClaw: 'OpenClaw',
      AiWorkspaceTool.openWebUi: 'Open WebUI',
    }[tool]!;

    final statusColor = _statusToColor(state?.status);

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
                Text(config, style: FluentTheme.of(context).typography.subtitle),
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
                FilledButton(
                  onPressed: state?.status == ToolStatus.notInstalled
                      ? () => _handleInstall(tool)
                      : null,
                  child: Text(state?.status == ToolStatus.notInstalled
                      ? 'Install'
                      : 'Installed'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: state?.status == ToolStatus.stopped
                      ? () => _handleStart(tool)
                      : null,
                  child: const Text('Start'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: state?.status == ToolStatus.running
                      ? () => _handleStop(tool)
                      : null,
                  child: const Text('Stop'),
                ),
                const Spacer(),
                Button(
                  onPressed: state?.status != ToolStatus.notInstalled
                      ? () => _handleUninstall(tool)
                      : null,
                  child: const Text('Uninstall'),
                ),
              ],
            ),
          ],
        ),
      ),
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
    if (status == ToolStatus.running) return 'Running';
    if (status == ToolStatus.stopped) return 'Stopped';
    if (status == ToolStatus.error) return 'Error';
    return 'Not installed';
  }
}
