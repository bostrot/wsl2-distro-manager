// Minimal Model Context Protocol (MCP) server core.
//
// Implements the synchronous request/response subset of MCP's JSON-RPC
// message set (initialize, tools/list, tools/call) needed for an MCP client
// to discover and invoke tools over a single HTTP POST endpoint. This is
// intentionally not a full implementation of MCP's Streamable HTTP transport
// (no SSE streaming, no resumable sessions) — sufficient for clients that
// call a tool and wait for one reply, which covers typical "run a command"
// use cases.
//
// Kept transport-agnostic (operates on decoded JSON maps, not HTTP) so the
// protocol logic can be unit tested without spinning up a real server.

const String mcpProtocolVersion = '2025-06-18';

/// A single tool exposed to MCP clients.
class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<String> Function(Map<String, dynamic> arguments) handler;

  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });
}

class McpServer {
  final String serverName;
  final String serverVersion;
  final List<McpTool> tools;

  McpServer({
    required this.serverName,
    required this.serverVersion,
    required this.tools,
  });

  /// Handle one decoded JSON-RPC message. Returns the JSON-RPC response map,
  /// or null if [message] was a notification (no `id`) that expects no reply.
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> message) async {
    final id = message['id'];
    final method = message['method'] as String?;

    if (method == null) {
      return id == null ? null : _error(id, -32600, 'Invalid Request');
    }

    // Notifications (no id) never get a response, even on error — the
    // client isn't listening for one.
    if (id == null) {
      return null;
    }

    switch (method) {
      case 'initialize':
        return _result(id, {
          'protocolVersion': mcpProtocolVersion,
          'capabilities': {'tools': {}},
          'serverInfo': {'name': serverName, 'version': serverVersion},
        });

      case 'tools/list':
        return _result(id, {
          'tools': tools
              .map((t) => {
                    'name': t.name,
                    'description': t.description,
                    'inputSchema': t.inputSchema,
                  })
              .toList(),
        });

      case 'tools/call':
        // Don't rely on the incoming map's generic parameters matching
        // exactly: real requests arrive via json.decode (which does produce
        // Map<String, dynamic>), but callers constructing messages directly
        // (tests, or future in-process callers) may pass a differently
        // "shaped" Map literal — a rigid `as Map<String, dynamic>` cast
        // throws on those even though the keys are all strings.
        final rawParams = message['params'];
        final params =
            rawParams is Map ? Map<String, dynamic>.from(rawParams) : null;
        final toolName = params?['name'] as String?;
        final rawArguments = params?['arguments'];
        final arguments = rawArguments is Map
            ? Map<String, dynamic>.from(rawArguments)
            : <String, dynamic>{};

        final tool = tools.where((t) => t.name == toolName).firstOrNull;
        if (tool == null) {
          return _error(id, -32602, 'Unknown tool: $toolName');
        }

        try {
          final text = await tool.handler(arguments);
          return _result(id, {
            'content': [
              {'type': 'text', 'text': text}
            ],
            'isError': false,
          });
        } catch (e) {
          return _result(id, {
            'content': [
              {'type': 'text', 'text': e.toString()}
            ],
            'isError': true,
          });
        }

      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  Map<String, dynamic> _result(dynamic id, Map<String, dynamic> result) => {
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      };

  Map<String, dynamic> _error(dynamic id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
