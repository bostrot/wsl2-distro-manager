import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/api/apple/vm_image_catalog.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/api/vm/vm_platform.dart';
import 'package:wsl2distromanager/api/wsl.dart' show formatTransferSize;
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/busy_button.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/nav/router.dart';

/// Test seam: replaces the backend used by the page.
AppleVmApi Function() appleVmApiBuilder = () {
  final backend = vmBackend();
  return backend is AppleVmApi ? backend : AppleVmApi();
};

/// Test seam: replaces the installer catalog (and its network) in tests.
VmImageCatalog Function() vmImageCatalogBuilder = () => VmImageCatalog();

/// Create-page for native VMs on macOS (Apple Virtualization framework).
///
/// The counterpart of [CreatePage]: instead of downloading a WSL rootfs it
/// provisions a VM — a Linux guest from an installer ISO or an existing raw
/// disk image (cloud image, exported template), or a macOS guest from a
/// restore image on Apple Silicon.
class CreateVmPage extends StatefulWidget {
  const CreateVmPage({super.key});

  @override
  State<CreateVmPage> createState() => _CreateVmPageState();
}

class _CreateVmPageState extends State<CreateVmPage> {
  final _name = TextEditingController();
  final _user = TextEditingController(text: 'user');
  final _iso = TextEditingController();
  final _image = TextEditingController();
  final _restoreImage = TextEditingController();
  final _diskSize = TextEditingController(text: '32');
  final _cpus = TextEditingController(text: '2');
  final _memory = TextEditingController(text: '4');

  String _guestOs = 'linux';
  bool _creating = false;
  String? _nameError;

  /// Live while a catalog ISO is being fetched; the Cancel button stops it.
  CancelSignal? _cancelSignal;
  String? _downloadLabel;
  double? _downloadFraction;

  @override
  void initState() {
    super.initState();
    plausible.event(page: 'create_vm');
  }

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _iso.dispose();
    _image.dispose();
    _restoreImage.dispose();
    _diskSize.dispose();
    _cpus.dispose();
    _memory.dispose();
    super.dispose();
  }

  Future<void> _pickFile(
      TextEditingController target, List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    final path = result?.files.single.path;
    if (path != null && mounted) {
      setState(() => target.text = path);
    }
  }

  int _intOf(TextEditingController controller, int fallback) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  Future<void> _create() async {
    final api = appleVmApiBuilder();
    final name = sanitizeDistroName(_name.text.trim());
    if (name.isEmpty) {
      setState(() => _nameError = 'errorentername-text'.i18n());
      return;
    }
    try {
      final existing = (await api.list(true)).all;
      if (existing.any((e) => e.toLowerCase() == name.toLowerCase())) {
        setState(() => _nameError = 'distroexists-text'.i18n());
        return;
      }
    } catch (_) {
      // The helper may be unavailable; creation below reports that properly.
    }

    setState(() {
      _nameError = null;
      _creating = true;
    });

    // A catalog pick downloads (or reuses) the installer first; a plain
    // path goes straight through.
    var isoPath = _iso.text.trim();
    final catalogEntry =
        _guestOs == 'linux' ? VmImageCatalog.entryFor(isoPath) : null;
    if (catalogEntry != null) {
      final token = CancelSignal();
      _cancelSignal = token;
      try {
        isoPath = await vmImageCatalogBuilder().download(
          catalogEntry,
          cancelSignal: token,
          onProgress: (received, total) {
            if (!mounted) return;
            setState(() {
              _downloadFraction =
                  total > 0 ? (received / total).clamp(0.0, 1.0) : null;
              _downloadLabel = total > 0
                  ? '${'downloading-text'.i18n()} '
                      '${(received / total * 100).toStringAsFixed(0)}% '
                      '(${formatTransferSize(received)} / '
                      '${formatTransferSize(total)})'
                  : '${'downloading-text'.i18n()} '
                      '${formatTransferSize(received)}';
            });
          },
        );
      } on CancelledException {
        Notify.message('');
        if (mounted) setState(() => _creating = false);
        return;
      } catch (error) {
        Notify.message(
            '${'errordownloading-text'.i18n()} ${catalogEntry.name}: $error',
            severity: InfoBarSeverity.error);
        if (mounted) setState(() => _creating = false);
        return;
      } finally {
        _cancelSignal = null;
        if (mounted) {
          setState(() {
            _downloadLabel = null;
            _downloadFraction = null;
          });
        }
      }
    }

    Notify.message('creatinginstance-text'.i18n([name]), loading: true);
    try {
      if (_guestOs == 'macos') {
        await api.createMacosVm(
          name,
          restoreImagePath: _restoreImage.text.trim(),
          diskSizeGb: _intOf(_diskSize, 64),
          cpus: _intOf(_cpus, 4),
          memoryGb: _intOf(_memory, 8),
        );
      } else {
        await api.createLinuxVm(
          name,
          isoPath: isoPath,
          imagePath: _image.text.trim(),
          diskSizeGb: _intOf(_diskSize, 32),
          cpus: _intOf(_cpus, 2),
          memoryGb: _intOf(_memory, 4),
          user: _user.text.trim().isEmpty ? 'user' : _user.text.trim(),
        );
      }
      Notify.message('vmcreated-text'.i18n([name]),
          severity: InfoBarSeverity.success);
      if (mounted) {
        if (router.canPop()) {
          router.pop();
        } else {
          router.goNamed('home');
        }
      }
    } catch (error) {
      Notify.message('${'vmcreatefailed-text'.i18n([name])} $error',
          severity: InfoBarSeverity.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// The installer picker: an autocomplete over the curated arm64 ISO
  /// catalog (picked entries are downloaded and cached, the way the Windows
  /// create screen offers its rootfs catalogue), while a local path or the
  /// file picker keeps working unchanged.
  Widget _isoField() {
    return InfoLabel(
      label: 'vminstalleriso-text'.i18n(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AutoSuggestBox<String>(
                  key: const ValueKey('test-vm-iso'),
                  controller: _iso,
                  enabled: !_creating,
                  placeholder: 'vmisoplaceholder-text'.i18n(),
                  items: [
                    for (final name in VmImageCatalog.names)
                      AutoSuggestBoxItem<String>(value: name, label: name),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed:
                    _creating ? null : () => _pickFile(_iso, const ['iso']),
                child: Text('selectfile-text'.i18n()),
              ),
            ],
          ),
          if (_downloadLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ProgressBar(
                      value: _downloadFraction == null
                          ? null
                          : (_downloadFraction! * 100).clamp(0.0, 100.0),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_downloadLabel!,
                      key: const ValueKey('test-vm-iso-progress'),
                      style: TextStyle(
                          fontSize: 12, color: secondaryTextColor(context))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _fileField(String label, TextEditingController controller,
      List<String> extensions,
      {String? hint, Key? key}) {
    return InfoLabel(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextBox(key: key, controller: controller),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed:
                    _creating ? null : () => _pickFile(controller, extensions),
                child: Text('selectfile-text'.i18n()),
              ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(hint,
                  style: TextStyle(
                      fontSize: 12, color: secondaryTextColor(context))),
            ),
        ],
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller,
      {Key? key}) {
    return Expanded(
      child: InfoLabel(
        label: label,
        child: TextBox(key: key, controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLinux = _guestOs == 'linux';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('createnewinstance-text'.i18n(),
                  style: FluentTheme.of(context).typography.titleLarge),
              const SizedBox(height: 4),
              Text('vmcreateinfo-text'.i18n(),
                  style: TextStyle(color: secondaryTextColor(context))),
              const SizedBox(height: 16),
              InfoLabel(
                label: 'name-text'.i18n(),
                child: TextBox(
                  key: const ValueKey('test-vm-name'),
                  controller: _name,
                  enabled: !_creating,
                ),
              ),
              if (_nameError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(_nameError!,
                      key: const ValueKey('test-vm-name-error'),
                      style: TextStyle(color: destructiveColor(context))),
                ),
              const SizedBox(height: 12),
              InfoLabel(
                label: 'vmguestos-text'.i18n(),
                child: ComboBox<String>(
                  key: const ValueKey('test-vm-guest-os'),
                  value: _guestOs,
                  items: const [
                    ComboBoxItem(value: 'linux', child: Text('Linux')),
                    ComboBoxItem(value: 'macos', child: Text('macOS')),
                  ],
                  onChanged: _creating
                      ? null
                      : (value) =>
                          setState(() => _guestOs = value ?? 'linux'),
                ),
              ),
              const SizedBox(height: 12),
              if (isLinux) ...[
                _isoField(),
                const SizedBox(height: 12),
                _fileField(
                  'vmbaseimage-text'.i18n(),
                  _image,
                  const ['img', 'raw'],
                  hint: 'vmbaseimagehint-text'.i18n(),
                  key: const ValueKey('test-vm-image'),
                ),
                const SizedBox(height: 12),
                InfoLabel(
                  label: 'optionalusername-text'.i18n(),
                  child: TextBox(controller: _user, enabled: !_creating),
                ),
              ] else ...[
                _fileField(
                  'vmrestoreimage-text'.i18n(),
                  _restoreImage,
                  const ['ipsw'],
                  hint: 'vmrestoreimagehint-text'.i18n(),
                  key: const ValueKey('test-vm-restore-image'),
                ),
                const SizedBox(height: 4),
                Text('vmmacosrequiresapplesilicon-text'.i18n(),
                    style: TextStyle(
                        fontSize: 12, color: secondaryTextColor(context))),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _numberField('vmdisksize-text'.i18n(), _diskSize,
                      key: const ValueKey('test-vm-disk-size')),
                  const SizedBox(width: 8),
                  _numberField('vmcpus-text'.i18n(), _cpus,
                      key: const ValueKey('test-vm-cpus')),
                  const SizedBox(width: 8),
                  _numberField('vmmemorygb-text'.i18n(), _memory,
                      key: const ValueKey('test-vm-memory')),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  BusyButton(
                    key: const ValueKey('test-vm-create-button'),
                    filled: true,
                    label: 'create-text'.i18n(),
                    busyLabel: 'creating-text'.i18n(),
                    busy: _creating,
                    onPressed: _creating ? null : _create,
                  ),
                  const SizedBox(width: 8),
                  Button(
                    key: const ValueKey('test-vm-cancel-button'),
                    // While a catalog download runs, Cancel stops it; the
                    // rest of a create is too quick to need one.
                    onPressed: _creating
                        ? (_cancelSignal == null
                            ? null
                            : () => _cancelSignal?.cancel())
                        : () {
                            if (router.canPop()) {
                              router.pop();
                            } else {
                              router.goNamed('home');
                            }
                          },
                    child: Text('cancel-text'.i18n()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
