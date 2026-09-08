// Value types shared by the container layer.
//
// Containers are deliberately *not* [Instances]: a WSL distro or an Apple VM
// is a machine the app owns for its whole life, while a container is one
// process tree spawned from an image that someone else's engine owns. Mixing
// the two into one list would have meant a "start" that means two different
// things and a delete that is destructive in one case and free in the other,
// so they keep their own model, their own screen and their own MCP tools.

/// A container engine the app can drive, in the order [ContainerService]
/// probes for one.
///
/// Only CLI-compatible engines belong here: everything below goes through the
/// same `ps/start/stop/rm/logs/exec` argument shapes, which is what lets one
/// service speak to all of them.
enum ContainerEngine {
  /// Docker Engine / Docker Desktop.
  docker('docker', 'Docker'),

  /// Podman, including `podman machine` on macOS and Windows.
  podman('podman', 'Podman');

  const ContainerEngine(this.executable, this.label);

  /// The binary invoked on the host, resolved through `PATH`.
  final String executable;

  /// Name shown to the user.
  final String label;

  /// The engine stored under [executable], or null when the value is stale —
  /// an engine the user had configured and that a later build dropped.
  static ContainerEngine? byExecutable(String? value) {
    for (final engine in ContainerEngine.values) {
      if (engine.executable == value) return engine;
    }
    return null;
  }
}

/// Lifecycle state of a container, normalised across engines.
///
/// Docker and Podman agree on the vocabulary but not on the casing, and
/// Podman adds `configured`/`stopping`. Anything unrecognised lands on
/// [unknown] rather than being dropped, so a row still renders.
enum ContainerState {
  created,
  running,
  paused,
  restarting,
  removing,
  exited,
  dead,
  unknown;

  /// Whether the container is doing work right now — the only distinction the
  /// list rows and the start/stop buttons care about.
  bool get isRunning => this == running || this == restarting;

  static ContainerState parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'created':
      case 'configured':
        return created;
      case 'running':
      case 'up':
        return running;
      case 'paused':
        return paused;
      case 'restarting':
        return restarting;
      case 'removing':
      case 'stopping':
        return removing;
      case 'exited':
      case 'stopped':
        return exited;
      case 'dead':
        return dead;
      default:
        return unknown;
    }
  }
}

/// One container as reported by `<engine> ps`.
class ContainerInfo {
  /// Engine-assigned id. Truncated to 12 characters by the CLI, which is
  /// still unique enough to address the container in every later command.
  final String id;

  /// The container's name. Engines always assign one, generating a random
  /// pair of words when the user did not pick any.
  final String name;

  /// Image reference the container was created from.
  final String image;

  final ContainerState state;

  /// The engine's own human-readable status ("Up 3 hours", "Exited (0) …").
  final String status;

  /// Published port mappings, verbatim from the engine.
  final String ports;

  /// Which engine reported it — the same name can exist under Docker and
  /// Podman at once, so every row carries its origin.
  final ContainerEngine engine;

  const ContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.engine,
    this.status = '',
    this.ports = '',
  });

  /// What later commands address the container by. The name reads better in
  /// logs and is what the user typed; the id is the fallback for the rare
  /// container without one.
  String get ref => name.isNotEmpty ? name : id;

  /// A one-line summary for the MCP tools and the AI chat.
  String get summary {
    final parts = <String>[
      '$ref (${state.name})',
      'image=$image',
      if (ports.isNotEmpty) 'ports=$ports',
      if (status.isNotEmpty) 'status=$status',
    ];
    return parts.join(' ');
  }
}

/// Raised when an engine command fails or no engine is installed. Carries the
/// engine's own stderr so the UI can show it instead of a generic failure.
class ContainerException implements Exception {
  final String message;

  const ContainerException(this.message);

  @override
  String toString() => message;
}
