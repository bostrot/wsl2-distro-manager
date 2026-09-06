# AI Workspace Plan

## Overview
AI Workspace provides lifecycle management for local AI tooling within WSL distributions, enabling users to install, start, stop, and uninstall AI services directly from the WSL2 Distro Manager UI.

## Supported Tools

| Tool | Port | Description | Install Method |
|------|------|-------------|----------------|
| **Hermes Agent** | 8081 | Local LLM inference engine | Shell script in distro |
| **OpenClaw** | 8082 | AI agent framework | Shell script in distro |
| **Open WebUI** | 8083 | Chat interface (via Docker) | Docker container |

## Architecture

### Service Layer (`lib/api/ai_workspace/service.dart`)
```dart
class AiWorkspaceService {
  final ExecutionBroker broker;
  
  // Lifecycle operations per tool
  Future<bool> isInstalled(String distro, String tool);
  Future<bool> isRunning(String distro, String tool);
  Future<void> install(String distro, String tool);
  Future<void> start(String distro, String tool);
  Future<void> stop(String distro, String tool);
  Future<void> uninstall(String distro, String tool);
}
```

**Key Design Decisions:**
- All shell commands routed through `ExecutionBroker` for policy enforcement + audit trail
- Each tool has install/start/stop/uninstall scripts stored in the target distro
- Health checks via HTTP port probing (curl to localhost:PORT)
- Open WebUI runs as Docker container; others run as background processes

### UI Layer (`lib/screens/ai_workspace_screen.dart`)
- Card-based layout showing each tool's status per selected distro
- Actions: Install → Start → Stop / Uninstall buttons with loading states
- Status indicators: installed, running, stopped badges
- Broker wired via `Provider<ExecutionBroker>` from app initialization

### Routing
- Route: `/ai-workspace` in `lib/nav/router.dart`
- Accessible from navigation sidebar

## Security Considerations
- All commands pass through ExecutionBroker policy enforcement
- `allowedCommands` whitelist restricts which shell commands can execute
- `readOnly` mode blocks package installation (apt/pip/npm) unless explicitly allowed
- Audit trail records every install/start/stop/uninstall operation with timestamp, command, exit code, and duration

## Future Enhancements
- [ ] Configurable tool ports per distro
- [ ] Resource usage monitoring (CPU/RAM per service)
- [ ] Multi-distro AI cluster support
- [ ] Tool configuration UI (model selection, context window size)
- [ ] Automatic health check scheduling
