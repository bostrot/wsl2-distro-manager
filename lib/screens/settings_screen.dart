import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/beta_badge.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/mcp/cloudflare_tunnel_service.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_service.dart';
import 'package:wsl2distromanager/api/remote_target.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/api/wsl_capabilities.dart';
import 'package:wsl2distromanager/api/wslconfig.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/components/wsl_size.dart';
import 'package:system_info2/system_info2.dart';
import 'package:wsl2distromanager/nav/router.dart';
import 'package:wsl2distromanager/theme.dart';

/// How a `.wslconfig` key is rendered. One member per documented value type in
/// `wsl-config.md`: `size` is byte-valued and carries an optional unit suffix,
/// `number` is a plain count, and `enumeration` is a closed set of values that
/// must not be typeable by hand (doc/audit/wsl-docs/ P05-09, P05-11).
enum SettingsType { bool, text, size, number, enumeration }

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  Map<String, TextEditingController> _settings =
      <String, TextEditingController>{};

  /// The `.wslconfig` file as it was read, mutated in place by Save.
  WslConfigFile? _config;

  /// Every documented key's value at load time.
  ///
  /// Save compares against this and writes **only** what changed. That is what
  /// makes "load → Save leaves the file byte-identical apart from the key the
  /// user edited" true: the old loop re-emitted every non-empty key into
  /// `[wsl2]` on every Save, which is how a hand-added `[experimental]` key was
  /// silently relocated into a section WSL ignores it in (audit CC-3, R-4).
  Map<String, String> _loadedConfig = <String, String>{};

  /// What the installed wsl.exe can do, once the probe answers.
  WslCapabilities? _capabilities;

  final TextEditingController _syncIpTextController = TextEditingController();
  final TextEditingController _syncPasswordController = TextEditingController();
  final TextEditingController _repoTextController = TextEditingController();
  final TextEditingController _dockerrepoController = TextEditingController();
  final TextEditingController _editorController = TextEditingController();
  final TextEditingController _terminalController = TextEditingController();
  final TextEditingController _vscodeController = TextEditingController();
  final TextEditingController _dockerMirrorController = TextEditingController();
  final TextEditingController _remoteWslTargetController =
      TextEditingController();
  final TextEditingController _byokBaseUrlController = TextEditingController();
  final TextEditingController _byokApiKeyController = TextEditingController();
  final TextEditingController _byokModelController = TextEditingController();
  bool _useRemoteWsl = false;
  bool _mcpEnabled = false;
  bool _mcpTokenVisible = false;
  bool _tunnelStarting = false;
  String? _tunnelError;
  bool showDocker = false;
  BuildContext? currentContext;
  final AiService _aiService = AiService();
  final LicenseManager _licenseManager = LicenseManager();
  final WslMcpService _mcpService = WslMcpService();
  final CloudflareTunnelService _tunnelService = CloudflareTunnelService();

  bool _isRemoteWslTargetValid(String target) => isValidRemoteTarget(target);

  @override
  void initState() {
    super.initState();
    readData();
  }

  @override
  void dispose() {
    // Save settings
    if (currentContext != null) {
      saveSettings(currentContext!, dispose: true);
    }
    _byokBaseUrlController.dispose();
    _byokApiKeyController.dispose();
    _byokModelController.dispose();
    super.dispose();
  }

  void readData() async {
    // The whole file, not a flat key→value map: Save writes back into this
    // model so comments, blank lines, key order, unknown keys and the sections
    // they sit in all survive a round trip (doc/audit/wsl-docs/ P05-02).
    _config = await WSLApi().readWslConfig();
    if (_config == null) {
      // Unreadable, not empty. Every control still renders, but Save is a
      // no-op — replacing a file we could not read with the one key the user
      // touched is worse than not saving.
      Notify.message('wslconfigwritefailed-text'.i18n());
    }
    final Map<String, String> settings =
        _config?.flatten() ?? <String, String>{};
    _loadedConfig = Map<String, String>.from(settings);
    settings.forEach((key, value) {
      _settings[key] = TextEditingController(text: value);
    });
    // The version the `--manage` affordances gate on, and the answer to
    // "which WSL do I have" the app never used to give (P05-08).
    WSLApi().capabilities.load().then((capabilities) {
      if (mounted) setState(() => _capabilities = capabilities);
    });
    String? syncIP = prefs.getString('SyncIP');
    if (syncIP != null && syncIP != '') {
      _syncIpTextController.text = syncIP;
    }
    String? syncPassword = prefs.getString('SyncPassword');
    if (syncPassword != null && syncPassword != '') {
      _syncPasswordController.text = syncPassword;
    }
    String? repoLink = prefs.getString('RepoLink');
    if (repoLink != null && repoLink != '') {
      _repoTextController.text = repoLink;
    }
    if (prefs.containsKey('DockerRepoLink')) {
      String? dockerRepoLink = prefs.getString('DockerRepoLink');
      if (dockerRepoLink != null && dockerRepoLink != '') {
        _dockerrepoController.text = dockerRepoLink;
      }
    }
    String? editor = prefs.getString('Editor');
    if (editor != null && editor != '') {
      _editorController.text = editor;
    }
    String? terminal = prefs.getString('Terminal');
    if (terminal != null && terminal != '') {
      _terminalController.text = terminal;
    }
    String? vscodeCmd = prefs.getString('VSCodeCmd');
    if (vscodeCmd != null && vscodeCmd != '') {
      _vscodeController.text = vscodeCmd;
    }
    String? dockerMirror = prefs.getString('DockerMirror');
    if (dockerMirror != null && dockerMirror != '') {
      _dockerMirrorController.text = dockerMirror;
    }
    _useRemoteWsl = prefs.getBool('UseRemoteWSL') ?? false;
    String? remoteTarget = prefs.getString('RemoteWSLTarget');
    if (remoteTarget != null && remoteTarget.trim().isNotEmpty) {
      _remoteWslTargetController.text = remoteTarget;
    }
    showDocker = prefs.getBool('showDocker') ?? false;
    _byokBaseUrlController.text = prefs.getString('ByokBaseUrl') ?? '';
    _byokApiKeyController.text = _aiService.byokApiKey;
    _byokModelController.text = prefs.getString('ByokModel') ?? '';
    _mcpEnabled = _mcpService.enabled;
    if (!mounted) return;
    setState(() {
      _settings = _settings;
    });
  }

  @override
  Widget build(BuildContext context) {
    currentContext = context;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0),
            child: SizedBox(
              child: settingsList(context),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
              left: 20.0, right: 20.0, bottom: 8.0, top: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: 'editwslconfig-text'.i18n(),
                child: Button(
                    style: ButtonStyle(
                        padding: ButtonState.all(const EdgeInsets.only(
                            left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                    onPressed: () {
                      WSLApi().editConfig();
                    },
                    child: Text('editwslconfig-text'.i18n())),
              ),
              const SizedBox(
                width: 10.0,
              ),
              Row(
                children: [
                  Tooltip(
                    message: 'stopwsl-text'.i18n(),
                    child: Button(
                        style: ButtonStyle(
                            padding: ButtonState.all(const EdgeInsets.only(
                                left: 15.0,
                                right: 15.0,
                                top: 10.0,
                                bottom: 10.0))),
                        onPressed: () {
                          WSLApi().restart();
                          hasPushed = false;

                          Navigator.popAndPushNamed(context, '/');
                        },
                        child: Text('stopwsl-text'.i18n())),
                  ),
                  const SizedBox(
                    width: 10.0,
                  ),
                  Tooltip(
                    message: 'save-text'.i18n(),
                    child: Button(
                        style: ButtonStyle(
                            padding: ButtonState.all(const EdgeInsets.only(
                                left: 15.0,
                                right: 20.0,
                                top: 10.0,
                                bottom: 10.0))),
                        onPressed: () {
                          saveSettings(context);
                        },
                        child: Text('save-text'.i18n())),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> saveSettings(BuildContext context,
      {bool dispose = false}) async {
    final remoteTarget = _remoteWslTargetController.text.trim();
    if (_useRemoteWsl && !_isRemoteWslTargetValid(remoteTarget)) {
      if (!dispose) {
        Notify.message('remote-wsl-target-required-text'.i18n());
        return;
      }
      _useRemoteWsl = false;
    }

    plausible.event(name: "global_settings_saved");
    // Sync target ip setting _syncIpTextController
    if (_syncIpTextController.text.isNotEmpty) {
      prefs.setString("SyncIP", _syncIpTextController.text);
    }

    // Sync password
    if (_syncPasswordController.text.isNotEmpty) {
      prefs.setString("SyncPassword", _syncPasswordController.text);
    } else {
      prefs.remove("SyncPassword");
    }

    // Save repo link
    if (_repoTextController.text.isNotEmpty) {
      prefs.setString("RepoLink", _repoTextController.text);
    } else {
      prefs.setString("RepoLink", defaultRepoLink);
    }

    // Save docker repo link
    if (_dockerrepoController.text.isNotEmpty) {
      prefs.setString("DockerRepoLink", _dockerrepoController.text);
    } else {
      prefs.setString("DockerRepoLink", "https://registry-1.docker.io");
    }

    // Save editor
    if (_editorController.text.isNotEmpty) {
      prefs.setString("Editor", _editorController.text);
    } else {
      prefs.remove("Editor");
    }

    // Save terminal
    if (_terminalController.text.isNotEmpty) {
      prefs.setString("Terminal", _terminalController.text);
    } else {
      prefs.remove("Terminal");
    }

    // Save vscode command
    if (_vscodeController.text.isNotEmpty) {
      prefs.setString("VSCodeCmd", _vscodeController.text);
    } else {
      prefs.remove("VSCodeCmd");
    }

    // Save docker mirror
    if (_dockerMirrorController.text.isNotEmpty) {
      prefs.setString("DockerMirror", _dockerMirrorController.text);
    } else {
      prefs.remove("DockerMirror");
    }

    prefs.setBool("UseRemoteWSL", _useRemoteWsl);
    if (_isRemoteWslTargetValid(remoteTarget)) {
      prefs.setString("RemoteWSLTarget", remoteTarget);
    } else {
      prefs.remove("RemoteWSLTarget");
    }

    // BYOK settings
    _aiService.setByokBaseUrl(_byokBaseUrlController.text);
    _aiService.setByokApiKey(_byokApiKeyController.text);
    _aiService.setByokModel(_byokModelController.text);

    // Distro location setting
    if (_settings['Default Distro Location']!.text.isNotEmpty) {
      prefs.setString("DistroPath", _settings['Default Distro Location']!.text);
    }
    // Data location setting
    if (_settings['General Data Location']!.text.isNotEmpty) {
      prefs.setString("DataPath", _settings['General Data Location']!.text);
    }

    await _saveWslConfig();
    hasPushed = false;

    if (!dispose) {
      router.pushNamed('home');
    }
  }

  /// The two `settingsWidget` names that are app preferences rather than
  /// `.wslconfig` keys, and must never reach the file.
  static const Set<String> _appPreferenceSettings = <String>{
    'Default Distro Location',
    'General Data Location',
  };

  /// Write back only what the user actually changed — see
  /// [applyWslConfigEdits], which is where the diff and its reasoning live.
  Future<void> _saveWslConfig() async {
    final config = _config;
    if (config == null) return;

    final edits = <String, String>{};
    _settings.forEach((key, controller) {
      if (_appPreferenceSettings.contains(key)) return;
      edits[key] = controller.text;
    });

    if (applyWslConfigEdits(config, _loadedConfig, edits) == 0) return;
    if (!await WSLApi().writeWslConfig(config)) {
      Notify.message('wslconfigwritefailed-text'.i18n());
    }
  }

  Widget settingsList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expander(
          header: Text('generalsettings-text'.i18n()),
          content: _buildGeneralSettings(context),
        ),
        const SizedBox(height: 10),
        Expander(
          header: Text('dockersettings-text'.i18n()),
          content: _buildDockerSettings(context),
        ),
        const SizedBox(height: 10),
        Expander(
          header: _betaHeader('byok-settings-text'.i18n()),
          content: _buildAiSettings(context),
        ),
        const SizedBox(height: 10),
        Expander(
          header: _betaHeader('mcp-settings-text'.i18n()),
          content: _buildMcpSettings(context),
        ),
        const SizedBox(height: 10),
        Expander(
          header: Text('syncsettings-text'.i18n()),
          content: _buildSyncSettings(context),
        ),
        const SizedBox(height: 10),
        Expander(
          header: Text('globalconfiguration-text'.i18n()),
          content: _buildGlobalConfigSettings(context),
        ),
        const SizedBox(height: 10),
        Expander(
          header: Text('experimental-text'.i18n()),
          content: _buildExperimentalSettings(context),
        ),
      ],
    );
  }

  Widget _buildGeneralSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsWidget(context,
            title: 'defaultdistrolocation-text'.i18n(),
            name: 'Default Distro Location',
            tooltip: 'distropath-text'.i18n(),
            suffix: IconButton(
              icon: const Icon(FluentIcons.open_folder_horizontal, size: 15.0),
              onPressed: () async {
                String? path = await FilePicker.platform.getDirectoryPath(
                  initialDirectory: prefs.getString("DistroPath") ??
                      getDefaultStorageRootPath(),
                );
                if (path != null &&
                    _settings['Default Distro Location'] != null) {
                  _settings['Default Distro Location']!.text = path;
                } else {
                  // User canceled the picker
                }
              },
            ),
            placeholder:
              prefs.getString("DistroPath") ?? getDefaultStorageRootPath()),
        settingsWidget(context,
            title: 'defaultdatalocation-text'.i18n(),
            name: 'General Data Location',
            tooltip: 'datapath-text'.i18n(),
            suffix: IconButton(
              icon: const Icon(FluentIcons.open_folder_horizontal, size: 15.0),
              onPressed: () async {
                String? path = await FilePicker.platform.getDirectoryPath(
                  initialDirectory: prefs.getString("DataPath") ??
                      prefs.getString("DistroPath") ??
                      getDefaultStorageRootPath(),
                );
                if (path != null &&
                    _settings['General Data Location'] != null) {
                  _settings['General Data Location']!.text = path;
                } else {
                  // User canceled the picker
                }
              },
            ),
            placeholder: prefs.getString("DataPath") ??
                prefs.getString("DistroPath") ??
              getDefaultStorageRootPath()),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'defaulteditor-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'defaulteditor-text'.i18n(),
              child: TextBox(
                controller: _editorController,
                placeholder: 'notepad.exe',
                suffix: IconButton(
                  icon: const Icon(FluentIcons.open_folder_horizontal,
                      size: 15.0),
                  onPressed: () async {
                    FilePickerResult? result =
                        await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['exe'],
                    );
                    if (result != null) {
                      _editorController.text = result.files.single.path!;
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'defaultterminal-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'defaultterminal-text'.i18n(),
              child: TextBox(
                controller: _terminalController,
                placeholder: 'wt.exe',
                suffix: IconButton(
                  icon: const Icon(FluentIcons.open_folder_horizontal,
                      size: 15.0),
                  onPressed: () async {
                    FilePickerResult? result =
                        await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['exe'],
                    );
                    if (result != null) {
                      _terminalController.text = result.files.single.path!;
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'defaultvscode-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'defaultvscode-text'.i18n(),
              child: TextBox(
                controller: _vscodeController,
                placeholder: 'code',
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'remote-wsl-over-ssh-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Row(
              children: [
                ToggleSwitch(
                  checked: _useRemoteWsl,
                  onChanged: (value) {
                    setState(() {
                      _useRemoteWsl = value;
                    });
                  },
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text(
                    'remote-wsl-over-ssh-info-text'.i18n(),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'remote-ssh-target-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'remote-ssh-target-format-text'.i18n(),
              child: TextBox(
                controller: _remoteWslTargetController,
                placeholder: 'remote-ssh-target-placeholder-text'.i18n(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'language-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
                message: 'language-text'.i18n(),
                // Menu
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'languagechange-text'.i18n(),
                    ),
                    const SizedBox(
                      height: 20.0,
                    ),
                    Builder(
                      builder: (context) {
                        var lang = Localizations.localeOf(context).languageCode;
                        var selectedLanguage =
                            prefs.getString('language') ?? lang;

                        // Language menu
                        // Every zh variant collapsed to the same languageCode
                        // before, which left the ComboBox with duplicate
                        // values and showed raw locale codes as labels.
                        if (!languageOptions.containsKey(selectedLanguage)) {
                          selectedLanguage = 'en';
                        }
                        return ComboBox<String>(
                            value: selectedLanguage,
                            items: languageOptions.entries
                                .map((e) => ComboBoxItem(
                                    value: e.key, child: Text(e.value)))
                                .toList(),
                            onChanged: (language) {
                              String curLanguage = language ?? lang;
                              prefs.setString('language', curLanguage);
                              setState(() {
                                selectedLanguage = curLanguage;
                              });
                            });
                      },
                    ),
                  ],
                )),
          ),
        ),
      ],
    );
  }

  Widget _betaHeader(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 8),
        const BetaBadge(),
      ],
    );
  }

  Widget _buildAiSettings(BuildContext context) {
    final isPro = _licenseManager.isPro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Text(
            'byok-info-text'.i18n(),
            style: const TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic),
          ),
        ),
        if (!isPro)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoBar(
              title: Text('byok-pro-required-text'.i18n()),
              severity: InfoBarSeverity.info,
              action: Button(
                key: const ValueKey('test-byok-upgrade'),
                onPressed: () => router.pushNamed('license'),
                child: Text('upgrade-text'.i18n()),
              ),
            ),
          ),
        // No enable toggle — the key is the only chat path, not an option.
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'byok-baseurl-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'byok-baseurl-hint-text'.i18n(),
              child: TextBox(
                key: const ValueKey('test-byok-baseurl-input'),
                controller: _byokBaseUrlController,
                enabled: isPro,
                placeholder: AiService.defaultByokBaseUrl,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'byok-apikey-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'byok-apikey-hint-text'.i18n(),
              child: TextBox(
                key: const ValueKey('test-byok-apikey-input'),
                controller: _byokApiKeyController,
                enabled: isPro,
                obscureText: true,
                placeholder: 'sk-...',
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'byok-model-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'byok-model-hint-text'.i18n(),
              child: TextBox(
                key: const ValueKey('test-byok-model-input'),
                controller: _byokModelController,
                enabled: isPro,
                placeholder: AiService.defaultByokModel,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMcpSettings(BuildContext context) {
    final isPro = _licenseManager.isPro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Text(
            'mcp-info-text'.i18n(),
            style: const TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic),
          ),
        ),
        if (!isPro)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoBar(
              title: Text('mcp-pro-required-text'.i18n()),
              severity: InfoBarSeverity.info,
              action: Button(
                key: const ValueKey('test-mcp-upgrade'),
                onPressed: () => router.pushNamed('license'),
                child: Text('upgrade-text'.i18n()),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'mcp-toggle-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Row(
              children: [
                ToggleSwitch(
                  key: const ValueKey('test-mcp-toggle'),
                  checked: _mcpEnabled && isPro,
                  onChanged: (value) {
                    if (!isPro) {
                      router.pushNamed('license');
                      return;
                    }
                    setState(() => _mcpEnabled = value);
                    _mcpService.setEnabled(value);
                  },
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text('mcp-toggle-hint-text'.i18n()),
                ),
              ],
            ),
          ),
        ),
        if (_mcpEnabled && isPro) ...[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'mcp-endpoint-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Row(
                children: [
                  Expanded(
                    child: TextBox(
                      key: const ValueKey('test-mcp-endpoint'),
                      readOnly: true,
                      controller:
                          TextEditingController(text: _mcpService.endpointUrl),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(FluentIcons.copy, size: 15.0),
                    onPressed: () => Clipboard.setData(
                        ClipboardData(text: _mcpService.endpointUrl)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'mcp-token-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Row(
                children: [
                  Expanded(
                    child: TextBox(
                      key: const ValueKey('test-mcp-token'),
                      readOnly: true,
                      obscureText: !_mcpTokenVisible,
                      controller:
                          TextEditingController(text: _mcpService.token),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                        _mcpTokenVisible ? FluentIcons.hide3 : FluentIcons.view,
                        size: 15.0),
                    onPressed: () => setState(
                        () => _mcpTokenVisible = !_mcpTokenVisible),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(FluentIcons.copy, size: 15.0),
                    onPressed: () => Clipboard.setData(
                        ClipboardData(text: _mcpService.token)),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey('test-mcp-regenerate-token'),
                    icon: const Icon(FluentIcons.refresh, size: 15.0),
                    onPressed: () =>
                        setState(() => _mcpService.regenerateToken()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoBar(
              title: Text('mcp-tunnel-warning-text'.i18n()),
              severity: InfoBarSeverity.warning,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'mcp-tunnel-toggle-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Row(
                children: [
                  ToggleSwitch(
                    key: const ValueKey('test-mcp-tunnel-toggle'),
                    checked: _tunnelService.isRunning,
                    onChanged: _tunnelStarting
                        ? null
                        : (value) async {
                            setState(() {
                              _tunnelStarting = true;
                              _tunnelError = null;
                            });
                            try {
                              if (value) {
                                await _tunnelService.start(WslMcpService.port);
                              } else {
                                await _tunnelService.stop();
                              }
                            } catch (e) {
                              _tunnelError = e.toString();
                            } finally {
                              if (mounted) {
                                setState(() => _tunnelStarting = false);
                              }
                            }
                          },
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Text('mcp-tunnel-toggle-hint-text'.i18n()),
                  ),
                ],
              ),
            ),
          ),
          if (_tunnelStarting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: _buildInlineTunnelStatus(),
            ),
          if (_tunnelError != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _tunnelError!,
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          if (_tunnelService.isRunning && _tunnelService.publicUrl != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: InfoLabel(
                label: 'mcp-tunnel-url-text'.i18n(),
                labelStyle: const TextStyle(fontWeight: FontWeight.w500),
                child: Row(
                  children: [
                    Expanded(
                      child: TextBox(
                        key: const ValueKey('test-mcp-tunnel-url'),
                        readOnly: true,
                        controller: TextEditingController(
                            text: _tunnelService.publicUrl),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(FluentIcons.copy, size: 15.0),
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: _tunnelService.publicUrl!)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildInlineTunnelStatus() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 12,
          child: ProgressRing(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          'mcp-tunnel-connecting-text'.i18n(),
          style: TextStyle(fontSize: 12, color: secondaryTextColor(context)),
        ),
      ],
    );
  }

  Widget _buildDockerSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'showdockershort-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Row(
              children: [
                Tooltip(
                    message: 'showdockershort-text'.i18n(),
                    child: ToggleSwitch(
                      checked: showDocker,
                      onChanged: (value) {
                        setState(() {
                          showDocker = value;
                          prefs.setBool('showDocker', value);
                        });
                      },
                    )),
                const SizedBox(
                  width: 10.0,
                ),
                Text('showdockerlong-text'.i18n()),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'dockermirror-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'dockermirrorhint-text'.i18n(),
              child: TextBox(
                controller: _dockerMirrorController,
                placeholder: 'https://mirror.gcr.io',
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'dockerrepo-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'dockerrepo-text'.i18n(),
              child: TextBox(
                controller: _dockerrepoController,
                placeholder: 'https://registry-1.docker.io',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'syncipaddress-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'syncipaddress-text'.i18n(),
              child: TextBox(
                controller: _syncIpTextController,
                placeholder: '192.168.1.20',
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'syncpassword-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'syncpasswordhint-text'.i18n(),
              child: TextBox(
                controller: _syncPasswordController,
                placeholder: 'SecretPassword123',
                obscureText: true,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'repofordistro-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'repofordistro-text'.i18n(),
              child: TextBox(
                controller: _repoTextController,
                placeholder: defaultRepoLink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlobalConfigSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Text(
            'globalconfigurationinfo-text'.i18n(),
            style: const TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic),
          ),
        ),
        _wslVersionPanel(context),
        settingsWidget(context,
            title: 'kernel',
            tooltip: 'absolutewindowspath-text'.i18n(),
            placeholder: '',
            suffix: _filePickerSuffix('kernel')),
        settingsWidget(context,
            title: 'kernelModules',
            tooltip: 'kernelmodulesinfo-text'.i18n(),
            placeholder: '',
            suffix: _filePickerSuffix('kernelModules', extensions: ['vhdx'])),
        settingsWidget(context,
            title: 'memory',
            tooltip: 'memoryinfo-text'.i18n(),
            type: SettingsType.size,
            sizePostfix: 'GB',
            sizeMin: 1,
            sizeMax: _hostMemoryGb + 1,
            placeholder: ''),
        settingsWidget(context,
            title: 'processors',
            tooltip: 'processorinfo-text'.i18n(),
            type: SettingsType.number,
            sizeMin: 1,
            sizeMax: SysInfo.cores.length,
            placeholder: ''),
        settingsWidget(context,
            title: 'localhostForwarding',
            tooltip: 'wildcardinfo-text'.i18n(),
            type: SettingsType.bool,
            enabled: _networkingMode() != 'mirrored',
            disabledReason: 'ignoredinmirrored-text'.i18n()),
        settingsWidget(context,
            title: 'kernelCommandLine',
            tooltip: 'kernelcmdinfo-text'.i18n(),
            placeholder: ''),
        settingsWidget(context,
            title: 'safeMode',
            tooltip: 'safemodeinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'swap',
            tooltip: 'swapinfo-text'.i18n(),
            type: SettingsType.size,
            sizePostfix: 'GB',
            sizeMin: 0,
            sizeMax: _hostMemoryGb * 2,
            placeholder: ''),
        settingsWidget(context,
            title: 'swapFile',
            tooltip: 'vhdinfo-text'.i18n(),
            placeholder: '%Temp%\\swap.vhdx',
            suffix: _filePickerSuffix('swapFile', extensions: ['vhdx'])),
        settingsWidget(context,
            title: 'guiApplications',
            tooltip: 'guiinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'debugConsole',
            tooltip: 'consoleinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'nestedVirtualization',
            tooltip: 'nestedvirtinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'vmIdleTimeout',
            tooltip: 'vmidleinfo-text'.i18n(),
            type: SettingsType.number,
            unitLabel: 'milliseconds-text'.i18n(),
            placeholder: '60000'),
        settingsWidget(context,
            title: 'maxCrashDumpCount',
            tooltip: 'maxcrashdumpcountinfo-text'.i18n(),
            type: SettingsType.number,
            placeholder: '10'),
        settingsWidget(context,
            title: 'dnsProxy',
            tooltip: 'dnsproxyinfo-text'.i18n(),
            type: SettingsType.bool,
            enabled: _networkingMode() == 'nat',
            disabledReason:
                'onlyapplieswhen-text'.i18n(['networkingMode = nat'])),
        settingsWidget(context,
            title: 'networkingMode',
            tooltip: 'networkingmodeinfo-text'.i18n(),
            type: SettingsType.enumeration,
            options: const [
              'none',
              'nat',
              'bridged',
              'mirrored',
              'virtioproxy'
            ],
            optionNotes: {'bridged': 'deprecatedvalue-text'.i18n()},
            placeholder: 'nat'),
        settingsWidget(context,
            title: 'firewall',
            tooltip: 'firewallinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'dnsTunneling',
            tooltip: 'dnstunnelinginfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'autoProxy',
            tooltip: 'autoproxyinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'defaultVhdSize',
            tooltip: 'defaultvhdsizeinfo-text'.i18n(),
            type: SettingsType.size,
            sizePostfix: 'GB',
            placeholder: 'unitexample-text'.i18n()),
      ],
    );
  }

  /// Which WSL is installed, what it said while being asked, and the one-click
  /// update (P05-08, P05-23).
  ///
  /// The version is not decoration: everything from `--manage` on is gated on
  /// it, and until now the app could not answer "which WSL do I have" anywhere.
  /// The warnings underneath are the half a version number cannot supply —
  /// wsl.exe refuses a `.wslconfig` key, or an unsupported host CPU, on stderr
  /// **with exit code 0** (runtime R-1, R-4), and the app used to discard every
  /// one of those lines.
  Widget _wslVersionPanel(BuildContext context) {
    final capabilities = _capabilities;
    final label = capabilities == null
        ? '…'
        : (capabilities.version ??
            (capabilities.wslMissing
                ? 'wslnotfound-text'.i18n()
                : 'wslinbox-text'.i18n()));

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: InfoLabel(
        label: 'wslversion-text'.i18n(),
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label),
                const SizedBox(width: 12.0),
                Button(
                  onPressed: _updatingWsl
                      ? null
                      : () => _runWslUpdate(webDownload: false),
                  child: Text('updatewsl-text'.i18n()),
                ),
                const SizedBox(width: 8.0),
                Tooltip(
                  message: 'updatewslwebdownloadinfo-text'.i18n(),
                  child: Button(
                    onPressed: _updatingWsl
                        ? null
                        : () => _runWslUpdate(webDownload: true),
                    child: Text('updatewslwebdownload-text'.i18n()),
                  ),
                ),
              ],
            ),
            if (capabilities != null && capabilities.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '${'wslreported-text'.i18n()}\n'
                  '${capabilities.warnings.join('\n')}',
                  style: TextStyle(
                      color: Colors.warningPrimaryColor, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _updatingWsl = false;

  Future<void> _runWslUpdate({required bool webDownload}) async {
    setState(() => _updatingWsl = true);
    Notify.message('updatingwsl-text'.i18n(), loading: true);
    final result = await WSLApi().updateWsl(webDownload: webDownload);
    // `--update` prints its progress and its "already up to date" answer on
    // stdout, so the text is worth showing either way rather than a bare
    // success/failure.
    Notify.message(result.ok
        ? '${'wslupdated-text'.i18n()} ${result.text}'.trim()
        : 'wslupdatefailed-text'.i18n([result.text]));
    WSLApi().capabilities.reset();
    final capabilities = await WSLApi().capabilities.load();
    if (!mounted) return;
    setState(() {
      _updatingWsl = false;
      _capabilities = capabilities;
    });
  }

  /// Host memory in whole GB, the ceiling the `memory` and `swap` sliders are
  /// scaled against.
  int get _hostMemoryGb =>
      SysInfo.getTotalPhysicalMemory() ~/ 1024 ~/ 1024 ~/ 1024;

  /// A `.wslconfig` boolean read the way WSL reads it: an absent key means the
  /// key's documented default, not `false`. Used for the conditional
  /// dependencies below, so an untouched `dnsTunneling` does not grey out the
  /// two keys it gates (doc/audit/wsl-docs/ CC-6).
  ///
  /// The default comes from [kWslConfigBoolDefaults], the same table
  /// [_tristateToggle] renders from — one place for the twelve documented
  /// defaults rather than a literal at each call site.
  bool _configBool(String name) {
    final value = _settings[name]?.text.trim().toLowerCase() ?? '';
    if (value.isEmpty) return kWslConfigBoolDefaults[name] ?? false;
    return value == 'true';
  }

  /// `networkingMode` as WSL resolves it: unset or unrecognised means NAT.
  String _networkingMode() {
    final value = _settings['networkingMode']?.text.trim().toLowerCase() ?? '';
    const known = ['none', 'nat', 'bridged', 'mirrored', 'virtioproxy'];
    return known.contains(value) ? value : 'nat';
  }

  /// The folder-picker button shared by every `.wslconfig` path key. Restricted
  /// to [extensions] where the documentation names a file type.
  Widget _filePickerSuffix(String name, {List<String>? extensions}) {
    return IconButton(
      icon: const Icon(FluentIcons.open_folder_horizontal, size: 15.0),
      onPressed: () async {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: extensions == null ? FileType.any : FileType.custom,
          allowedExtensions: extensions,
        );
        if (result != null) {
          _settings[name]!.text = result.files.single.path!;
        }
      },
    );
  }

  Widget _buildExperimentalSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsWidget(context,
            title: 'autoMemoryReclaim',
            tooltip: 'automemoryreclaiminfo-text'.i18n(),
            type: SettingsType.enumeration,
            options: const ['disabled', 'gradual', 'dropCache'],
            placeholder: 'dropCache'),
        settingsWidget(context,
            title: 'sparseVhd',
            tooltip: 'sparsevhdinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'bestEffortDnsParsing',
            tooltip: 'besteffortdnsparsinginfo-text'.i18n(),
            type: SettingsType.bool,
            enabled: _configBool('dnsTunneling'),
            disabledReason:
                'onlyapplieswhen-text'.i18n(['dnsTunneling = true'])),
        settingsWidget(context,
            title: 'dnsTunnelingIpAddress',
            tooltip: 'dnstunnelingipaddressinfo-text'.i18n(),
            placeholder: '10.255.255.254',
            enabled: _configBool('dnsTunneling'),
            disabledReason:
                'onlyapplieswhen-text'.i18n(['dnsTunneling = true'])),
        settingsWidget(context,
            title: 'initialAutoProxyTimeout',
            tooltip: 'initialautoproxytimeoutinfo-text'.i18n(),
            type: SettingsType.number,
            unitLabel: 'milliseconds-text'.i18n(),
            placeholder: '1000',
            enabled: _configBool('autoProxy'),
            disabledReason: 'onlyapplieswhen-text'.i18n(['autoProxy = true'])),
        settingsWidget(context,
            title: 'ignoredPorts',
            tooltip: 'ignoredportsinfo-text'.i18n(),
            placeholder: '3000,9000,9090',
            enabled: _networkingMode() == 'mirrored',
            disabledReason:
                'onlyapplieswhen-text'.i18n(['networkingMode = mirrored'])),
        settingsWidget(context,
            title: 'hostAddressLoopback',
            tooltip: 'hostaddressloopbackinfo-text'.i18n(),
            type: SettingsType.bool,
            enabled: _networkingMode() == 'mirrored',
            disabledReason:
                'onlyapplieswhen-text'.i18n(['networkingMode = mirrored'])),
      ],
    );
  }

  Widget settingsWidget(
    BuildContext context, {
    String title = '',
    String name = '',
    String tooltip = '',
    dynamic suffix = 0,
    String placeholder = '',
    SettingsType type = SettingsType.text,
    String sizePostfix = '',
    int sizeMax = 0,
    int sizeMin = 0,
    String unitLabel = '',
    List<String> options = const <String>[],
    Map<String, String> optionNotes = const <String, String>{},
    bool enabled = true,
    String disabledReason = '',
  }) {
    if (name.isEmpty) {
      name = title;
    }
    if (_settings[name] == null) {
      _settings[name] = TextEditingController(text: '');
    }
    // First letter to capital
    title = title.replaceFirst(title[0], title[0].toUpperCase());
    if (unitLabel.isNotEmpty) {
      title = '$title ($unitLabel)';
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: InfoLabel(
        label: title,
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tooltip.isNotEmpty && tooltip != title)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(tooltip,
                    style: TextStyle(
                        color: secondaryTextColor(context), fontSize: 12)),
              ),
            // The documented "Only applicable when…" conditions. The control is
            // disabled rather than hidden, so the key stays discoverable and
            // the reason says why WSL would ignore it right now.
            if (!enabled && disabledReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(disabledReason,
                    style: TextStyle(
                        color: disabledTextColor(context),
                        fontSize: 12,
                        fontStyle: FontStyle.italic)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 0.0),
              child: Builder(
                builder: (context) {
                  switch (type) {
                    case SettingsType.bool:
                      return _tristateToggle(context, name, enabled: enabled);
                    case SettingsType.enumeration:
                      return _enumerationBox(name,
                          options: options,
                          notes: optionNotes,
                          placeholder: placeholder,
                          enabled: enabled);
                    case SettingsType.size:
                    case SettingsType.number:
                      return _numericSetting(context, name,
                          type: type,
                          sizePostfix: sizePostfix,
                          sizeMin: sizeMin,
                          sizeMax: sizeMax,
                          placeholder: placeholder,
                          enabled: enabled);
                    case SettingsType.text:
                      return TextBox(
                        controller: _settings[name],
                        placeholder: placeholder,
                        enabled: enabled,
                        suffix: suffix != 0 ? suffix : Container(),
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A boolean `.wslconfig` key with the third state the format actually has.
  ///
  /// An absent key means the key's **documented default**, and seven of the
  /// twelve booleans on this screen default to `true` — every one of which used
  /// to render off, with an empty label, on the ordinary case of a machine with
  /// no `.wslconfig` at all. A user reading the screen concluded the opposite
  /// of the truth for all seven (audit CC-1).
  ///
  /// The undo button empties the controller, which [_saveWslConfig] turns into
  /// a line *removed* from the file. That third state had nowhere to be written
  /// until P05-02 gave the engine a delete branch (CC-11), which is why this
  /// ships with the engine rather than before it.
  Widget _tristateToggle(BuildContext context, String name,
      {required bool enabled}) {
    final raw = _settings[name]!.text.trim();
    final isSet = raw.isNotEmpty;
    final documented = kWslConfigBoolDefaults[name];
    final checked = isSet ? raw.toLowerCase() == 'true' : (documented ?? false);

    return Row(
      children: [
        ToggleSwitch(
          checked: checked,
          onChanged: enabled
              ? (value) {
                  _settings[name]!.text = value ? 'true' : 'false';
                  setState(() {
                    _settings = _settings;
                  });
                }
              : null,
          content: Text(isSet
              ? raw
              : '${checked ? 'true' : 'false'} '
                  '(${'settingdefault-text'.i18n()})'),
        ),
        if (isSet && enabled)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Tooltip(
              message: 'settingunset-text'.i18n(),
              child: IconButton(
                icon: const Icon(FluentIcons.undo, size: 14.0),
                onPressed: () {
                  _settings[name]!.text = '';
                  setState(() {
                    _settings = _settings;
                  });
                },
              ),
            ),
          ),
        if (!isSet)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text('settingunset-text'.i18n(),
                style: TextStyle(
                    color: secondaryTextColor(context), fontSize: 12)),
          ),
      ],
    );
  }

  /// A closed set of documented values. Anything already in the file that is not
  /// one of them is kept as an extra item rather than dropped, so opening the
  /// screen never rewrites a value the user put there by hand — and never trips
  /// `ComboBox`'s "value must be among the items" assert.
  Widget _enumerationBox(
    String name, {
    required List<String> options,
    required Map<String, String> notes,
    required String placeholder,
    required bool enabled,
  }) {
    final current = _settings[name]!.text.trim();
    final match = options.cast<String?>().firstWhere(
        (option) => option!.toLowerCase() == current.toLowerCase(),
        orElse: () => null);
    final selected = current.isEmpty ? null : (match ?? current);
    final items = <String>[
      ...options,
      if (selected != null && match == null) selected,
    ];

    return ComboBox<String>(
      isExpanded: true,
      placeholder: Text(placeholder),
      value: selected,
      items: items
          .map((option) => ComboBoxItem<String>(
                value: option,
                child: Text(notes.containsKey(option)
                    ? '$option — ${notes[option]}'
                    : option),
              ))
          .toList(),
      onChanged: enabled
          ? (value) {
              if (value == null) return;
              _settings[name]!.text = value;
              setState(() {
                _settings = _settings;
              });
            }
          : null,
    );
  }

  /// The `size` and `number` keys.
  ///
  /// A slider only when the value the file holds actually fits on it: a
  /// documented-legal `memory=8589934592` or a `processors=64` copied from a
  /// bigger machine is out of range, and `Slider` asserts on that in its
  /// constructor (doc/audit/wsl-docs/ CC-9). Those fall back to a text box that
  /// says so, so the value is left exactly as written instead of being silently
  /// clamped or snapped to the minimum.
  Widget _numericSetting(
    BuildContext context,
    String name, {
    required SettingsType type,
    required String sizePostfix,
    required int sizeMin,
    required int sizeMax,
    required String placeholder,
    required bool enabled,
  }) {
    final raw = _settings[name]!.text.trim();
    final double? value = type == SettingsType.size
        ? parseWslSize(raw,
            unit: sizePostfix.isEmpty ? 'B' : sizePostfix,
            bareUnitMax: sizeMax.toDouble())
        : parseWslCount(raw)?.toDouble();
    final hasSlider = sizeMax > sizeMin;
    final fits = wslSliderFits(value, min: sizeMin, max: sizeMax);

    if (!hasSlider || (raw.isNotEmpty && !fits)) {
      String warning = '';
      if (raw.isNotEmpty && value == null) {
        warning = type == SettingsType.size
            ? 'settinginvalidsize-text'.i18n()
            : 'settinginvalidnumber-text'.i18n();
      } else if (hasSlider && raw.isNotEmpty) {
        warning =
            'settingoutofrange-text'.i18n(['$sizeMin – $sizeMax$sizePostfix']);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextBox(
            controller: _settings[name],
            placeholder: placeholder,
            enabled: enabled,
          ),
          if (warning.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                warning,
                style:
                    TextStyle(color: Colors.warningPrimaryColor, fontSize: 12),
              ),
            ),
        ],
      );
    }

    return SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Slider(
            min: sizeMin.toDouble(),
            max: sizeMax.toDouble(),
            value: value ?? sizeMin.toDouble(),
            style: SliderThemeData(
              labelBackgroundColor: AppTheme().color,
            ),
            onChanged: enabled
                ? (value) {
                    setState(() {
                      _settings[name]!.text = type == SettingsType.size
                          ? formatWslSize(value, sizePostfix)
                          : value.round().toString();
                    });
                  }
                : null,
            label: _settings[name]!.text.isEmpty
                ? '$sizeMin$sizePostfix'
                : _settings[name]!.text));
  }
}
