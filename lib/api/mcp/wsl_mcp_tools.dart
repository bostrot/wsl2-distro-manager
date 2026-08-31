// The WSL tools exposed over MCP: the full lifecycle (create, configure,
// operate, destroy), global and per-distro configuration, introspection,
// file transfer and disk management.
//
// The one-way operations are gated instead of hidden: unregistering needs an
// explicit confirm flag and points at the export tool first, so an agent can
// provision and tear down distros without a human clicking through the GUI —
// but never deletes one on a whim.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:wsl2distromanager/api/app.dart';
import 'package:wsl2distromanager/api/distro_package.dart';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:wsl2distromanager/api/mount_service.dart';
import 'package:wsl2distromanager/api/quick_actions.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/api/wsl_capabilities.dart';

List<McpTool> buildWslMcpTools(
  WSLApi wslApi,
  WslTerminalManager terminalManager, {
  MountService? mountService,
  Dio? dio,
  App? app,
  DistroPackager? packager,
}) {
  final mount = mountService ?? MountService();
  final http = dio ?? Dio();
  final catalog = app ?? App();
  final distroPackager = packager ?? DistroPackager(api: wslApi);
  return [
    // =========================================================================
    // Introspection
    // =========================================================================
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
      name: 'wsl_distro_info',
      description:
          'Details for one installed distro: state, install path and disk '
          'size.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
        },
        'required': ['distro'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final instances = await wslApi.list(false);
        if (!instances.all.contains(distro)) {
          throw ArgumentError('No distro named "$distro". Installed: '
              '${instances.all.isEmpty ? "none" : instances.all.join(", ")}');
        }
        final running = instances.running.contains(distro);
        final path = wslApi.currentDistroPath(distro);
        final size = await wslApi.getSize(distro);
        return [
          'Name: $distro',
          'State: ${running ? "running" : "stopped"}',
          'Install path: $path',
          'Disk size: ${size == null || size.isEmpty ? "unknown" : size}',
        ].join('\n');
      },
    ),
    McpTool(
      name: 'wsl_status',
      description:
          'Global WSL status: version of WSL itself, kernel, default distro '
          'and default WSL version (wsl --status plus wsl --version).',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final status = await wslApi.statusInfo();
        final version = await wslApi.versionInfo();
        final parts = [
          if (status.text.isNotEmpty) status.text,
          if (version.text.isNotEmpty) version.text,
        ];
        return parts.isEmpty ? 'WSL returned no status output.' : parts.join('\n\n');
      },
    ),
    // =========================================================================
    // Lifecycle
    // =========================================================================
    McpTool(
      name: 'wsl_list_online_distros',
      description:
          'List the distros available from the online catalog '
          '(wsl --list --online). A distro not listed here needs '
          'wsl_import_distro with a rootfs tarball instead.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final out = await wslApi.listOnline();
        return _verbReport(out, 'No catalog output.');
      },
    ),
    McpTool(
      name: 'wsl_list_catalog',
      description:
          'List the distros the app can create from its own curated catalog '
          '(the "Add an instance" screen) — names mapped to rootfs URLs. '
          'Install one by passing its URL to wsl_import_distro as the '
          'tarball.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final links = await catalog.getDistroLinks();
        if (links.isEmpty) return 'The catalog is empty or unreachable.';
        final entries = links.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return entries.map((e) => '${e.key}: ${e.value}').join('\n');
      },
    ),
    McpTool(
      name: 'wsl_install_distro',
      description:
          'Install a distro from the online catalog (wsl --install). Use '
          'wsl_list_online_distros for the accepted names. Runs headless '
          'with --no-launch, so the first shell is never opened here.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Catalog name, e.g. Ubuntu-24.04.',
          },
        },
        'required': ['distro'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final out = await wslApi.installOnline(distro);
        return _verbReport(out, 'Installed $distro.');
      },
    ),
    McpTool(
      name: 'wsl_import_distro',
      description:
          'Create a distro from a rootfs tarball (wsl --import). The tarball '
          'can be a local path or an http(s) URL, which is downloaded first. '
          'Omit install_path to use the app\'s configured distro location. '
          'Set vhd for a .vhdx instead of a tarball.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Name to register the new distro under.',
          },
          'tarball': {
            'type': 'string',
            'description':
                'Local path or http(s) URL of the rootfs tar/tar.gz/tar.xz.',
          },
          'install_path': {
            'type': 'string',
            'description':
                'Directory for the new distro\'s disk. Optional.',
          },
          'vhd': {
            'type': 'boolean',
            'description': 'The source is a .vhdx image, not a tarball.',
          },
        },
        'required': ['name', 'tarball'],
      },
      handler: (args) async {
        final name = _requireString(args, 'name');
        final tarball = _requireString(args, 'tarball');
        final installPath = (args['install_path'] as String?)?.trim() ?? '';
        final isVhd = args['vhd'] == true;

        var file = tarball;
        if (tarball.startsWith('http://') ||
            tarball.startsWith('https://')) {
          final target = '${Directory.systemTemp.path}'
              '${Platform.pathSeparator}wsl2dm-mcp-import-'
              '${DateTime.now().millisecondsSinceEpoch}.tar';
          await http.download(tarball, target);
          file = target;
        } else if (!File(tarball).existsSync()) {
          throw ArgumentError('tarball not found: $tarball');
        }

        final result = await wslApi.import(name, installPath, file,
            isVhd: isVhd);
        return result.trim().isEmpty ? 'Imported $name.' : result.trim();
      },
    ),
    McpTool(
      name: 'wsl_import_in_place',
      description:
          'Register an existing .vhdx as a distro where it lies '
          '(wsl --import-in-place). Nothing is copied.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Name to register the distro under.',
          },
          'vhdx_path': {
            'type': 'string',
            'description': 'Windows path of the existing .vhdx.',
          },
        },
        'required': ['name', 'vhdx_path'],
      },
      handler: (args) async {
        final name = _requireString(args, 'name');
        final vhdx = _requireString(args, 'vhdx_path');
        if (!File(vhdx).existsSync()) {
          throw ArgumentError('vhdx_path not found: $vhdx');
        }
        final out = await wslApi.importInPlace(name, vhdx);
        return _verbReport(out, 'Registered $name from $vhdx.');
      },
    ),
    McpTool(
      name: 'wsl_export_distro',
      description:
          'Export a distro to a file (wsl --export) — the backup to take '
          'before a risky change or an unregister. Format defaults to an '
          'uncompressed tar; pass tar.gz, tar.xz or vhd to change it.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro to export.',
          },
          'out_path': {
            'type': 'string',
            'description': 'Windows path of the file to write.',
          },
          'format': {
            'type': 'string',
            'enum': ['tar', 'tar.gz', 'tar.xz', 'vhd'],
            'description': 'Archive format. Optional.',
          },
        },
        'required': ['distro', 'out_path'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final outPath = _requireString(args, 'out_path');
        final format = (args['format'] as String?)?.trim();
        final result = await wslApi.export(distro, outPath,
            format: format == null || format.isEmpty || format == 'tar'
                ? null
                : format);
        return result.trim().isEmpty
            ? 'Exported $distro to $outPath.'
            : result.trim();
      },
    ),
    McpTool(
      name: 'wsl_package_distro',
      description:
          'Package a distro as a portable .wsl file (the "Distro packages" '
          'screen): configures then exports it so it installs on any machine '
          'via wsl_install_package or `wsl --install --from-file`. Omit '
          'out_path to use the app\'s default packages folder. Needs WSL '
          '2.4.4.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the distro to package.',
          },
          'out_path': {
            'type': 'string',
            'description':
                'Windows path of the .wsl file to write. Optional.',
          },
          'format': {
            'type': 'string',
            'enum': ['tar.gz', 'tar.xz'],
            'description': 'Archive format inside the package. Default tar.gz.',
          },
        },
        'required': ['distro'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final outPath = (args['out_path'] as String?)?.trim().isNotEmpty == true
            ? (args['out_path'] as String).trim()
            : distroPackager.defaultPackageFile(distro);
        final format = (args['format'] as String?)?.trim();
        final result = await distroPackager.package(distro, outPath,
            format: format == null || format.isEmpty ? 'tar.gz' : format);
        if (!result.ok) {
          throw StateError('Packaging failed: ${result.error}');
        }
        return 'Packaged $distro to ${result.path} '
            '(${result.bytes} bytes).';
      },
    ),
    McpTool(
      name: 'wsl_install_package',
      description:
          'Install a .wsl package (wsl --install --from-file). Unlike '
          'wsl_import_distro this honours the package\'s wsl-distribution.conf '
          '— first-run setup, default user, Start-menu shortcut. Needs WSL '
          '2.4.4.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Windows path of the .wsl file.',
          },
          'name': {
            'type': 'string',
            'description':
                'Name to register under, overriding the package default. '
                'Optional.',
          },
        },
        'required': ['path'],
      },
      handler: (args) async {
        final path = _requireString(args, 'path');
        if (!File(path).existsSync()) {
          throw ArgumentError('package not found: $path');
        }
        final name = (args['name'] as String?)?.trim();
        final out = await distroPackager.install(path,
            name: name == null || name.isEmpty ? null : name);
        return _verbReport(
            out, 'Installed ${name == null || name.isEmpty ? path : name}.');
      },
    ),
    McpTool(
      name: 'wsl_unregister_distro',
      description:
          'PERMANENTLY delete a distro and its disk (wsl --unregister). '
          'Unrecoverable — take a backup with wsl_export_distro first. '
          'Refuses to run unless confirm is true.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro to delete.',
          },
          'confirm': {
            'type': 'boolean',
            'description':
                'Must be true. Confirms the permanent deletion is intended.',
          },
        },
        'required': ['distro', 'confirm'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        if (args['confirm'] != true) {
          throw ArgumentError(
              'Refused: unregistering permanently deletes "$distro" and its '
              'disk. Export a backup first (wsl_export_distro), then call '
              'again with confirm: true.');
        }
        await wslApi.remove(distro);
        return 'Unregistered $distro. Its disk is gone.';
      },
    ),
    // =========================================================================
    // Configuration
    // =========================================================================
    McpTool(
      name: 'wsl_get_wsl_conf',
      description:
          'Read /etc/wsl.conf from a distro, verbatim. Starts the distro if '
          'needed.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
        },
        'required': ['distro'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final conf = await wslApi.readWSLConf(distro);
        if (conf == null) {
          return '(no /etc/wsl.conf in $distro, or the distro is unreachable)';
        }
        final text = conf.serialize().trim();
        return text.isEmpty ? '(empty /etc/wsl.conf)' : text;
      },
    ),
    McpTool(
      name: 'wsl_set_wsl_conf',
      description:
          'Set one key in a distro\'s /etc/wsl.conf, preserving everything '
          'else in the file — e.g. section "boot" key "command" to autostart '
          'a daemon, or "boot"/"systemd". An empty value removes the key. '
          'Takes effect after the distro restarts (wsl_stop_distro, then any '
          'command).',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
          'section': {
            'type': 'string',
            'description': 'INI section: boot, automount, network, '
                'interop or user.',
          },
          'key': {
            'type': 'string',
            'description': 'Key inside the section, e.g. command or systemd.',
          },
          'value': {
            'type': 'string',
            'description': 'Value to write. Empty string removes the key.',
          },
        },
        'required': ['distro', 'section', 'key', 'value'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final section = _requireString(args, 'section');
        final key = _requireString(args, 'key');
        final value = (args['value'] as String?) ?? '';
        final ok = await wslApi.updateWSLConf(
            distro,
            (conf) => value.trim().isEmpty
                ? conf.remove(section, key)
                : conf.set(section, key, value));
        if (!ok) {
          throw StateError(
              'Could not read /etc/wsl.conf in $distro — is it reachable?');
        }
        return value.trim().isEmpty
            ? 'Removed [$section] $key from $distro. Restart the distro to '
                'apply.'
            : 'Set [$section] $key=$value in $distro. Restart the distro to '
                'apply.';
      },
    ),
    McpTool(
      name: 'wsl_get_wslconfig',
      description:
          'Read the global %USERPROFILE%\\.wslconfig, verbatim.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final config = await wslApi.readWslConfig();
        if (config == null) return '(no .wslconfig found)';
        final text = config.serialize().trim();
        return text.isEmpty ? '(empty .wslconfig)' : text;
      },
    ),
    McpTool(
      name: 'wsl_set_wslconfig',
      description:
          'Set one key in the global .wslconfig (memory, processors, swap, '
          'networkingMode, ...). The key is placed in the section WSL reads '
          'it from; an empty value removes it. Applies after wsl_shutdown.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'key': {
            'type': 'string',
            'description': 'Key name, e.g. memory or networkingMode.',
          },
          'value': {
            'type': 'string',
            'description': 'Value to write. Empty string removes the key.',
          },
        },
        'required': ['key', 'value'],
      },
      handler: (args) async {
        final key = _requireString(args, 'key');
        final value = (args['value'] as String?) ?? '';
        final ok = value.trim().isEmpty
            ? await wslApi.removeConfig(key)
            : await wslApi.setConfig(key, value);
        if (!ok) {
          throw StateError('Could not update .wslconfig.');
        }
        return value.trim().isEmpty
            ? 'Removed $key from .wslconfig. Run wsl_shutdown to apply.'
            : 'Set $key=$value in .wslconfig. Run wsl_shutdown to apply.';
      },
    ),
    McpTool(
      name: 'wsl_set_default_user',
      description:
          'Set the default login user of a distro '
          '(wsl --manage --set-default-user). Needs WSL 2.5+.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
          'user': {
            'type': 'string',
            'description': 'Existing Linux user name.',
          },
        },
        'required': ['distro', 'user'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final user = _requireString(args, 'user');
        final out = await wslApi.manageSetDefaultUser(distro, user);
        return _verbReport(out, 'Default user of $distro is now $user.');
      },
    ),
    McpTool(
      name: 'wsl_set_default_distro',
      description: 'Make a distro the default one (wsl --set-default).',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
        },
        'required': ['distro'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final out = await wslApi.setDefaultDistro(distro);
        return _verbReport(out, '$distro is now the default distro.');
      },
    ),
    McpTool(
      name: 'wsl_set_version',
      description:
          'Convert a distro between WSL 1 and WSL 2 (wsl --set-version). '
          'Converts the whole disk — can take minutes.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
          'version': {
            'type': 'integer',
            'enum': [1, 2],
            'description': 'Target WSL version.',
          },
        },
        'required': ['distro', 'version'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final version = args['version'];
        if (version != 1 && version != 2) {
          throw ArgumentError('version must be 1 or 2');
        }
        final out = await wslApi.setVersion(distro, version as int);
        return _verbReport(out, '$distro is now WSL $version.');
      },
    ),
    // =========================================================================
    // Operate
    // =========================================================================
    McpTool(
      name: 'wsl_run_command',
      description:
          'Run a shell command inside a named WSL distro and return its '
          'output. Starts the distro first if it is not already running. '
          'Defaults to root, the distro\'s home directory and a 300s '
          'timeout; override with user, cwd and timeout_seconds.',
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
          'user': {
            'type': 'string',
            'description': 'Linux user to run as. Defaults to root.',
          },
          'cwd': {
            'type': 'string',
            'description':
                'Working directory inside the distro (Linux path), or a '
                'Windows path like C:\\src.',
          },
          'timeout_seconds': {
            'type': 'integer',
            'description':
                'Kill the command after this many seconds. Default 300, '
                'max 3600.',
          },
        },
        'required': ['distro', 'command'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final command = _requireString(args, 'command');
        final user = (args['user'] as String?)?.trim() ?? '';
        final cwd = (args['cwd'] as String?)?.trim() ?? '';
        final timeoutSeconds =
            ((args['timeout_seconds'] as num?)?.toInt() ?? 300)
                .clamp(1, 3600);
        final out = await wslApi.runVerb([
          '-d',
          distro,
          if (cwd.isNotEmpty) ...['--cd', cwd],
          '-u',
          user.isEmpty ? 'root' : user,
          '--exec',
          'bash',
          '-c',
          command,
        ], timeout: Duration(seconds: timeoutSeconds));
        if (out.exitCode != 0) {
          return 'Exit code ${out.exitCode}.'
              '${out.text.isEmpty ? "" : "\n${out.text}"}';
        }
        return out.text.isEmpty ? '(no output)' : out.text;
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
        final distro = _requireString(args, 'distro');
        await wslApi.stop(distro);
        return 'Stopped $distro.';
      },
    ),
    McpTool(
      name: 'wsl_shutdown',
      description:
          'Shut down every running distro and the WSL VM at once '
          '(wsl --shutdown). Required for .wslconfig changes to apply. '
          'wsl_stop_distro stops a single distro instead.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final result = await wslApi.shutdown();
        return result.trim().isEmpty ? 'WSL shut down.' : result.trim();
      },
    ),
    // =========================================================================
    // File transfer
    // =========================================================================
    McpTool(
      name: 'wsl_copy_to',
      description:
          'Copy one file from Windows into a distro. Starts the distro and '
          'creates the target directory if needed. Single files only.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
          'windows_path': {
            'type': 'string',
            'description': 'Source file on Windows, e.g. C:\\data\\app.conf.',
          },
          'linux_path': {
            'type': 'string',
            'description': 'Absolute destination path inside the distro.',
          },
        },
        'required': ['distro', 'windows_path', 'linux_path'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final winPath = _requireString(args, 'windows_path');
        final linuxPath = _requireString(args, 'linux_path');
        if (!File(winPath).existsSync()) {
          throw ArgumentError('windows_path not found: $winPath');
        }
        if (!linuxPath.startsWith('/')) {
          throw ArgumentError('linux_path must be absolute: $linuxPath');
        }
        // Boots the distro and makes sure the directory exists — a UNC copy
        // into a missing directory just fails.
        final dir = linuxPath.substring(0, linuxPath.lastIndexOf('/'));
        if (dir.isNotEmpty) {
          await wslApi.execCmdAsRoot(distro, 'mkdir -p ${_shellQuote(dir)}');
        }
        await File(winPath).copy(_uncPath(distro, linuxPath));
        return 'Copied $winPath to $distro:$linuxPath.';
      },
    ),
    McpTool(
      name: 'wsl_copy_from',
      description:
          'Copy one file out of a distro to Windows. Starts the distro and '
          'creates the target directory if needed. Single files only.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
          'linux_path': {
            'type': 'string',
            'description': 'Absolute source path inside the distro.',
          },
          'windows_path': {
            'type': 'string',
            'description': 'Destination file on Windows.',
          },
        },
        'required': ['distro', 'linux_path', 'windows_path'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final linuxPath = _requireString(args, 'linux_path');
        final winPath = _requireString(args, 'windows_path');
        if (!linuxPath.startsWith('/')) {
          throw ArgumentError('linux_path must be absolute: $linuxPath');
        }
        // Boots the distro so the \\wsl$ share answers.
        await wslApi.execCmdAsRoot(distro, 'true');
        final source = File(_uncPath(distro, linuxPath));
        if (!source.existsSync()) {
          throw ArgumentError('linux_path not found in $distro: $linuxPath');
        }
        await File(winPath).parent.create(recursive: true);
        await source.copy(winPath);
        return 'Copied $distro:$linuxPath to $winPath.';
      },
    ),
    // =========================================================================
    // Disks
    // =========================================================================
    McpTool(
      name: 'wsl_move_distro',
      description:
          'Move a distro\'s storage to another directory '
          '(wsl --manage --move). Copies the whole disk — can take a long '
          'time. Needs WSL 2.5+.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
          'new_location': {
            'type': 'string',
            'description': 'Destination directory on Windows.',
          },
        },
        'required': ['distro', 'new_location'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final location = _requireString(args, 'new_location');
        final out = await wslApi.manageMove(distro, location);
        return _verbReport(out, 'Moved $distro to $location.');
      },
    ),
    McpTool(
      name: 'wsl_resize_distro',
      description:
          'Grow a distro\'s virtual disk (wsl --manage --resize). Size like '
          '512GB or 1TB, whole numbers only. Stop WSL first (wsl_shutdown). '
          'Needs WSL 2.5+.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
          'size': {
            'type': 'string',
            'description': 'New size, e.g. 512GB. Decimals are rejected.',
          },
        },
        'required': ['distro', 'size'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final size = _requireString(args, 'size');
        final out = await wslApi.manageResize(distro, size);
        return _verbReport(out, 'Resized $distro to $size.');
      },
    ),
    McpTool(
      name: 'wsl_compact_disk',
      description:
          'Compact a distro\'s virtual disk so freed space returns to '
          'Windows (diskpart, not a wsl.exe flag). Stops the distro first; '
          'can take minutes.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'distro': {
            'type': 'string',
            'description': 'Name of the WSL distro.',
          },
        },
        'required': ['distro'],
      },
      handler: (args) async {
        final distro = _requireString(args, 'distro');
        final result = await wslApi.cleanup(distro);
        return result.trim().isEmpty
            ? 'Compacted the disk of $distro.'
            : result.trim();
      },
    ),
    McpTool(
      name: 'wsl_mount_disk',
      description:
          'Mount a physical disk or partition into WSL (wsl --mount). '
          'Needs administrator rights, which Windows prompts for.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'disk': {
            'type': 'string',
            'description': r'Device path, e.g. \\.\PHYSICALDRIVE1.',
          },
          'partition': {
            'type': 'string',
            'description': 'Partition number. Optional.',
          },
          'type': {
            'type': 'string',
            'description': 'Filesystem type, e.g. ext4. Optional.',
          },
          'options': {
            'type': 'string',
            'description': 'Mount options, e.g. data=ordered. Optional.',
          },
          'name': {
            'type': 'string',
            'description': 'Mount point name. Optional.',
          },
          'bare': {
            'type': 'boolean',
            'description': 'Attach without mounting a filesystem.',
          },
        },
        'required': ['disk'],
      },
      handler: (args) async {
        final disk = _requireString(args, 'disk');
        await mount.mountDisk(
          disk,
          partition: (args['partition'] as String?) ?? '',
          type: (args['type'] as String?) ?? '',
          options: (args['options'] as String?) ?? '',
          name: (args['name'] as String?) ?? '',
          bare: args['bare'] == true,
        );
        return 'Mounted $disk. It appears under /mnt/wsl in every distro.';
      },
    ),
    McpTool(
      name: 'wsl_unmount_disk',
      description:
          'Unmount a disk previously mounted into WSL (wsl --unmount).',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'disk': {
            'type': 'string',
            'description': 'Device path or mount name used when mounting.',
          },
        },
        'required': ['disk'],
      },
      handler: (args) async {
        final disk = _requireString(args, 'disk');
        await mount.unmount(disk);
        return 'Unmounted $disk.';
      },
    ),
    // =========================================================================
    // Snippets (the Snippets screen's quick actions)
    // =========================================================================
    McpTool(
      name: 'wsl_list_snippets',
      description:
          'List saved snippets (Snippets screen) — reusable shell scripts by '
          'name.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final items = QuickAction().getFromPrefs();
        if (items.isEmpty) return 'No snippets saved.';
        return items
            .map((s) => s.description.isEmpty
                ? s.name
                : '${s.name} — ${s.description}')
            .join('\n');
      },
    ),
    McpTool(
      name: 'wsl_get_snippet',
      description: 'Return the script body of a saved snippet by name.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Snippet name.'},
        },
        'required': ['name'],
      },
      handler: (args) async {
        final name = _requireString(args, 'name');
        final items = QuickAction().getFromPrefs();
        for (final s in items) {
          if (s.name == name) {
            return s.content.isEmpty ? '(empty snippet)' : s.content;
          }
        }
        throw ArgumentError('No snippet named "$name".');
      },
    ),
    McpTool(
      name: 'wsl_create_snippet',
      description:
          'Create or update a snippet (Snippets screen): a named, reusable '
          'shell script the user can run against a distro later.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Snippet name.'},
          'content': {
            'type': 'string',
            'description': 'The shell script body.',
          },
          'description': {
            'type': 'string',
            'description': 'Short description. Optional.',
          },
        },
        'required': ['name', 'content'],
      },
      handler: (args) async {
        final name = _requireString(args, 'name');
        final content = _requireString(args, 'content');
        final description = (args['description'] as String?)?.trim() ?? '';
        final existed =
            QuickAction().getFromPrefs().any((s) => s.name == name);
        QuickAction.addToPrefs(QuickActionItem(
          name: name,
          content: content,
          description: description,
        ));
        return existed
            ? 'Updated snippet "$name".'
            : 'Created snippet "$name".';
      },
    ),
    McpTool(
      name: 'wsl_delete_snippet',
      description: 'Delete a saved snippet by name.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Snippet name.'},
        },
        'required': ['name'],
      },
      handler: (args) async {
        final name = _requireString(args, 'name');
        final items = QuickAction().getFromPrefs();
        if (!items.any((s) => s.name == name)) {
          throw ArgumentError('No snippet named "$name".');
        }
        QuickAction.removeFromPrefs(QuickActionItem(name: name, content: ''));
        return 'Deleted snippet "$name".';
      },
    ),
    // =========================================================================
    // Disk discovery (the Mount disk screen)
    // =========================================================================
    McpTool(
      name: 'wsl_list_physical_disks',
      description:
          'List the physical disks on the machine that can be mounted into '
          'WSL (device id, model, size).',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final disks = await mount.getPhysicalDisks();
        if (disks.isEmpty) return 'No physical disks found.';
        return disks
            .map((d) => '${d.deviceId} — ${d.model} (${d.size})')
            .join('\n');
      },
    ),
    McpTool(
      name: 'wsl_list_mounted_disks',
      description: 'List disks currently mounted into WSL.',
      inputSchema: const {
        'type': 'object',
        'properties': {},
      },
      handler: (_) async {
        final disks = await mount.getMountedDisks();
        return disks.isEmpty ? 'No disks are mounted.' : disks.join('\n');
      },
    ),
    // =========================================================================
    // Terminal sessions
    // =========================================================================
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
        final distro = _requireString(args, 'distro');
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
          'and followed by Enter), then wait and return any output '
          'produced. wait_ms sets how long to wait (default 600, max '
          '30000); wait_for is a regex that returns as soon as the output '
          'matches it, instead of waiting the full time. For longer runs, '
          'keep polling with wsl_terminal_read.',
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
          'wait_ms': {
            'type': 'integer',
            'description':
                'Milliseconds to wait for output. Default 600, max 30000.',
          },
          'wait_for': {
            'type': 'string',
            'description':
                'Regex; return as soon as the collected output matches.',
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
        final waitMs =
            ((args['wait_ms'] as num?)?.toInt() ?? 600).clamp(50, 30000);
        final pattern = (args['wait_for'] as String?)?.isNotEmpty == true
            ? RegExp(args['wait_for'] as String)
            : null;
        session.sendInput(input);

        final collected = StringBuffer();
        final deadline =
            DateTime.now().add(Duration(milliseconds: waitMs));
        while (true) {
          await Future.delayed(const Duration(milliseconds: 150));
          collected.write(session.readNewOutput());
          if (pattern != null && pattern.hasMatch(collected.toString())) {
            break;
          }
          if (!DateTime.now().isBefore(deadline)) break;
        }
        final output = collected.toString();
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
      name: 'wsl_terminal_signal',
      description:
          'Interrupt or end an open terminal session: ctrl-c and ctrl-d '
          'send the control byte (best effort — the session is a pipe, not '
          'a TTY, so some programs ignore them), eof closes stdin for a '
          'true end-of-file, and kill terminates the session outright — '
          'the reliable way to unstick a hung command.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'session_id': {
            'type': 'string',
            'description': 'Session id returned by wsl_terminal_start.',
          },
          'signal': {
            'type': 'string',
            'enum': ['ctrl-c', 'ctrl-d', 'eof', 'kill'],
            'description': 'What to send.',
          },
        },
        'required': ['session_id', 'signal'],
      },
      handler: (args) async {
        final signal = _requireString(args, 'signal');
        if (signal == 'kill') {
          final sessionId = _requireString(args, 'session_id');
          if (terminalManager.session(sessionId) == null) {
            throw ArgumentError('Unknown session_id: $sessionId');
          }
          await terminalManager.closeSession(sessionId);
          return 'Killed session $sessionId.';
        }
        final session = _requireSession(terminalManager, args);
        switch (signal) {
          case 'ctrl-c':
            session.sendControl(0x03);
            return 'Sent Ctrl-C. If the command is still running, use '
                'signal "kill".';
          case 'ctrl-d':
            session.sendControl(0x04);
            return 'Sent Ctrl-D.';
          case 'eof':
            await session.sendEof();
            return 'Closed stdin (end-of-file).';
          default:
            throw ArgumentError(
                'signal must be one of ctrl-c, ctrl-d, eof, kill');
        }
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
        final sessionId = _requireString(args, 'session_id');
        if (terminalManager.session(sessionId) == null) {
          throw ArgumentError('Unknown session_id: $sessionId');
        }
        await terminalManager.closeSession(sessionId);
        return 'Closed session $sessionId.';
      },
    ),
  ];
}

String _requireString(Map<String, dynamic> args, String key) {
  final value = args[key] as String?;
  if (value == null || value.trim().isEmpty) {
    throw ArgumentError('$key is required');
  }
  return value;
}

/// Success gets the verb's own output (or [okMessage] when it printed
/// nothing); failure gets the exit code plus whatever wsl.exe said.
String _verbReport(WslOutput out, String okMessage) {
  if (out.exitCode == 0) {
    return out.text.isEmpty ? okMessage : out.text;
  }
  return 'Failed (exit code ${out.exitCode})'
      '${out.text.isEmpty ? "." : ": ${out.text}"}';
}

/// `/etc/passwd` in `Ubuntu` → `\\wsl$\Ubuntu\etc\passwd`.
String _uncPath(String distro, String linuxPath) =>
    '\\\\wsl\$\\$distro${linuxPath.replaceAll('/', '\\')}';

/// Single-quote [value] for a POSIX shell.
String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

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

/// A locked-down tool set confined to a single [distro] — the sandbox chat.
///
/// The model gets no lifecycle, no `.wslconfig`, no other distro and no
/// Windows host: every tool here hardcodes [distro], so the LLM can only ever
/// see and act inside that one sandbox. That is what makes "all the LLM sees
/// is the inside of the sandbox" a property of the tools, not just a request
/// in the prompt.
List<McpTool> buildSandboxTools(
  WSLApi wslApi,
  WslTerminalManager terminalManager,
  String distro,
) {
  return [
    McpTool(
      name: 'sandbox_run_command',
      description:
          'Run a shell command inside the sandbox and return its output. '
          'There is no other machine or distro you can reach.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': 'Shell command.'},
          'user': {
            'type': 'string',
            'description': 'Linux user. Defaults to root.',
          },
          'cwd': {
            'type': 'string',
            'description': 'Working directory inside the sandbox.',
          },
          'timeout_seconds': {
            'type': 'integer',
            'description': 'Kill after N seconds. Default 300, max 3600.',
          },
        },
        'required': ['command'],
      },
      handler: (args) async {
        final command = _requireString(args, 'command');
        final user = (args['user'] as String?)?.trim() ?? '';
        final cwd = (args['cwd'] as String?)?.trim() ?? '';
        final timeoutSeconds =
            ((args['timeout_seconds'] as num?)?.toInt() ?? 300).clamp(1, 3600);
        final out = await wslApi.runVerb([
          '-d',
          distro,
          if (cwd.isNotEmpty) ...['--cd', cwd],
          '-u',
          user.isEmpty ? 'root' : user,
          '--exec',
          'bash',
          '-c',
          command,
        ], timeout: Duration(seconds: timeoutSeconds));
        if (out.exitCode != 0) {
          return 'Exit code ${out.exitCode}.'
              '${out.text.isEmpty ? "" : "\n${out.text}"}';
        }
        return out.text.isEmpty ? '(no output)' : out.text;
      },
    ),
    McpTool(
      name: 'sandbox_write_file',
      description: 'Write a text file inside the sandbox (creating parents).',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute path inside the sandbox.',
          },
          'content': {'type': 'string', 'description': 'File contents.'},
        },
        'required': ['path', 'content'],
      },
      handler: (args) async {
        final path = _requireString(args, 'path');
        final content = args['content'] as String? ?? '';
        if (!path.startsWith('/')) {
          throw ArgumentError('path must be absolute: $path');
        }
        final ok = await wslApi.writeDistroFile(distro, path, content);
        if (!ok) throw StateError('Could not write $path.');
        return 'Wrote ${content.length} bytes to $path.';
      },
    ),
    McpTool(
      name: 'sandbox_read_file',
      description: 'Read a text file from inside the sandbox.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute path inside the sandbox.',
          },
        },
        'required': ['path'],
      },
      handler: (args) async {
        final path = _requireString(args, 'path');
        final text = await wslApi.readDistroFile(distro, path);
        if (text == null) throw ArgumentError('Could not read $path.');
        return text.isEmpty ? '(empty file)' : text;
      },
    ),
    McpTool(
      name: 'sandbox_terminal_start',
      description:
          'Open a persistent shell in the sandbox; returns a session_id for '
          'sandbox_terminal_send / _read / _close.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'user': {
            'type': 'string',
            'description': 'Linux user. Defaults to root.',
          },
        },
      },
      handler: (args) async {
        final user = args['user'] as String?;
        final session = await terminalManager.startSession(distro, user: user);
        return 'Started sandbox session ${session.id} (user: ${session.user}).';
      },
    ),
    McpTool(
      name: 'sandbox_terminal_send',
      description:
          'Send a line to a sandbox shell session and return output. wait_ms '
          '(default 600, max 30000) and wait_for (regex) control the wait.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'session_id': {'type': 'string'},
          'input': {'type': 'string'},
          'wait_ms': {'type': 'integer'},
          'wait_for': {'type': 'string'},
        },
        'required': ['session_id', 'input'],
      },
      handler: (args) async {
        final session = _requireSandboxSession(terminalManager, distro, args);
        final input = args['input'] as String?;
        if (input == null) throw ArgumentError('input is required');
        final waitMs =
            ((args['wait_ms'] as num?)?.toInt() ?? 600).clamp(50, 30000);
        final pattern = (args['wait_for'] as String?)?.isNotEmpty == true
            ? RegExp(args['wait_for'] as String)
            : null;
        session.sendInput(input);
        final collected = StringBuffer();
        final deadline = DateTime.now().add(Duration(milliseconds: waitMs));
        while (true) {
          await Future.delayed(const Duration(milliseconds: 150));
          collected.write(session.readNewOutput());
          if (pattern != null && pattern.hasMatch(collected.toString())) break;
          if (!DateTime.now().isBefore(deadline)) break;
        }
        final output = collected.toString();
        return output.isEmpty ? '(no output yet)' : output;
      },
    ),
    McpTool(
      name: 'sandbox_terminal_read',
      description: 'Read new output from a sandbox shell session.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'session_id': {'type': 'string'},
        },
        'required': ['session_id'],
      },
      handler: (args) async {
        final session = _requireSandboxSession(terminalManager, distro, args);
        final output = session.readNewOutput();
        return output.isEmpty ? '(no new output)' : output;
      },
    ),
    McpTool(
      name: 'sandbox_terminal_close',
      description: 'Close a sandbox shell session.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'session_id': {'type': 'string'},
        },
        'required': ['session_id'],
      },
      handler: (args) async {
        final sessionId = _requireString(args, 'session_id');
        final session = terminalManager.session(sessionId);
        if (session == null || session.distribution != distro) {
          throw ArgumentError('Unknown session_id: $sessionId');
        }
        await terminalManager.closeSession(sessionId);
        return 'Closed session $sessionId.';
      },
    ),
  ];
}

/// Like [_requireSession] but also refuses a session belonging to a different
/// distro — a sandbox tool must never reach outside its distro.
WslTerminalSession _requireSandboxSession(
    WslTerminalManager manager, String distro, Map<String, dynamic> args) {
  final session = _requireSession(manager, args);
  if (session.distribution != distro) {
    throw ArgumentError('Unknown session_id: ${args['session_id']}');
  }
  return session;
}
