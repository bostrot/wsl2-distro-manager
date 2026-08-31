// The WSL tools exposed over MCP: list distros, run one-shot commands,
// drive persistent terminal sessions, stop a distro.
//
// Deliberately non-destructive. Create, delete, export and move stay
// GUI-only — one-way or disk-heavy actions need a human confirming them.

import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:wsl2distromanager/api/wsl.dart';

List<McpTool> buildWslMcpTools(
  WSLApi wslApi,
  WslTerminalManager terminalManager,
) {
  return [
    McpTool(
      name: 'wsl_list_distros',
      description:
          'List installed WSL distros and which of them are currently running.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final instances = await wslApi.list(false);
        final lines = instances.all.map((name) {
          final running = instances.running.contains(name);
          return '$name (${running ? "running" : "stopped"})';
        });
        return lines.isEmpty ? 'No WSL distros installed.' : lines.join('\n');
      },
    ),
    McpTool(
      name: 'wsl_run_command',
      description:
          'Run a shell command as root inside a named WSL distro and return '
          'its output. Starts the distro first if it is not already running.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro to run the command in.',
          },
          'command': {
            'type': 'string',
            'description': 'Shell command to execute.',
          },
        },
        'required': ['distro', 'command'],
      },
      handler: (args) async {
        final distro = args['distro'] as String?;
        final command = args['command'] as String?;
        if (distro == null || distro.trim().isEmpty) {
          throw ArgumentError('distro is required');
        }
        if (command == null || command.trim().isEmpty) {
          throw ArgumentError('command is required');
        }
        final output = await wslApi.execCmdAsRoot(distro, command);
        return output.isEmpty ? '(no output)' : output;
      },
    ),
    McpTool(
      name: 'wsl_stop_distro',
      description: 'Stop (terminate) a running WSL distro.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro to stop.',
          },
        },
        'required': ['distro'],
      },
      handler: (args) async {
        final distro = args['distro'] as String?;
        if (distro == null || distro.trim().isEmpty) {
          throw ArgumentError('distro is required');
        }
        await wslApi.stop(distro);
        return 'Stopped $distro.';
      },
    ),
    McpTool(
      name: 'wsl_terminal_start',
      description:
          'Start a persistent interactive shell session in a WSL distro. '
          'Unlike wsl_run_command, the session stays open across multiple '
          'calls — use wsl_terminal_send to run commands in it and '
          'wsl_terminal_read to poll for output, e.g. for a REPL, a build '
          'watcher, or anything that needs input after starting. Returns a '
          'session_id to use with the other wsl_terminal_* tools.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro to open a shell in.',
          },
          'user': {
            'type': 'string',
            'description': 'User to run the shell as. Defaults to root.',
          },
        },
        'required': ['distro'],
      },
      handler: (args) async {
        final distro = args['distro'] as String?;
        if (distro == null || distro.trim().isEmpty) {
          throw ArgumentError('distro is required');
        }
        final user = args['user'] as String?;
        final session =
            await terminalManager.startSession(distro, user: user);
        return 'Started terminal session ${session.id} in $distro '
            '(user: ${session.user}).';
      },
    ),
    McpTool(
      name: 'wsl_terminal_send',
      description:
          'Send a line of input to an open terminal session (as if typed '
          'and followed by Enter), then briefly wait and return any output '
          'produced. For long-running commands, follow up with '
          'wsl_terminal_read to keep polling — this only waits about half '
          'a second before returning.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'session_id': {
            'type': 'string',
            'description': 'Session id returned by wsl_terminal_start.',
          },
          'input': {
            'type': 'string',
            'description': 'Text to send, e.g. a shell command.',
          },
        },
        'required': ['session_id', 'input'],
      },
      handler: (args) async {
        final session = _requireSession(terminalManager, args);
        final input = args['input'] as String?;
        if (input == null) {
          throw ArgumentError('input is required');
        }
        session.sendInput(input);
        await Future.delayed(const Duration(milliseconds: 600));
        final output = session.readNewOutput();
        return output.isEmpty ? '(no output yet)' : output;
      },
    ),
    McpTool(
      name: 'wsl_terminal_read',
      description:
          'Read any output an open terminal session has produced since the '
          'last read (or since it started, on the first read). Use this to '
          'poll a long-running command started with wsl_terminal_send.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'session_id': {
            'type': 'string',
            'description': 'Session id returned by wsl_terminal_start.',
          },
        },
        'required': ['session_id'],
      },
      handler: (args) async {
        final session = _requireSession(terminalManager, args);
        final output = session.readNewOutput();
        return output.isEmpty ? '(no new output)' : output;
      },
    ),
    McpTool(
      name: 'wsl_terminal_list',
      description: 'List currently open terminal sessions.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        if (terminalManager.sessions.isEmpty) {
          return 'No open terminal sessions.';
        }
        return terminalManager.sessions
            .map((s) =>
                '${s.id}: ${s.distribution} (user: ${s.user}, '
                '${s.isAlive ? "alive" : "exited"}, started ${s.startedAt.toIso8601String()})')
            .join('\n');
      },
    ),
    McpTool(
      name: 'wsl_terminal_close',
      description: 'Close an open terminal session.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'session_id': {
            'type': 'string',
            'description': 'Session id returned by wsl_terminal_start.',
          },
        },
        'required': ['session_id'],
      },
      handler: (args) async {
        final sessionId = args['session_id'] as String?;
        if (sessionId == null || sessionId.trim().isEmpty) {
          throw ArgumentError('session_id is required');
        }
        if (terminalManager.session(sessionId) == null) {
          throw ArgumentError('Unknown session_id: $sessionId');
        }
        await terminalManager.closeSession(sessionId);
        return 'Closed session $sessionId.';
      },
    ),
  ];
}

WslTerminalSession _requireSession(
    WslTerminalManager manager, Map<String, dynamic> args) {
  final sessionId = args['session_id'] as String?;
  if (sessionId == null || sessionId.trim().isEmpty) {
    throw ArgumentError('session_id is required');
  }
  final session = manager.session(sessionId);
  if (session == null) {
    throw ArgumentError('Unknown session_id: $sessionId');
  }
  if (!session.isAlive) {
    throw ArgumentError('Session $sessionId has already closed.');
  }
  return session;
}
