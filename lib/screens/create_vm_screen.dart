import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/api/apple/vm_image_catalog.dart';
import 'package:wsl2distromanager/api/recipes/recipe_catalog.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/api/vm/vm_platform.dart';
import 'package:wsl2distromanager/api/wsl.dart' show formatTransferSize;
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/busy_button.dart';
import 'package:wsl2distromanager/components/form_card.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/components/suggest_on_focus.dart';
import 'package:wsl2distromanager/nav/router.dart';

/// Test seam: replaces the backend used by the page.
AppleVmApi Function() appleVmApiBuilder = () {
  final backend = vmBackend();
  return backend is AppleVmApi ? backend : AppleVmApi();
};

/// What a new Linux VM boots from. The two are one exclusive choice on the
/// page: a cloud image (or any raw disk image, e.g. an exported template)
/// seeds the disk and comes up ready to use, an installer ISO is attached
/// and the user clicks through a normal install. They used to be two
/// free-form fields, with the catalog's cloud images listed under the
/// installer box (bostrot/ai-tasks#5).
enum VmBootKind { cloudImage, installerIso }

/// Create-page for native VMs on macOS (Apple Virtualization framework).
///
/// The counterpart of [CreatePage]: instead of downloading a WSL rootfs it
/// provisions a VM — a Linux guest from a cloud image / raw disk image or
/// from an installer ISO, or a macOS guest from a restore image on Apple
/// Silicon.
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
  // Cloud image first: it is the recommended path (no manual install).
  VmBootKind _bootKind = VmBootKind.cloudImage;
  String _recipeId = '';
  bool _creating = false;
  String? _nameError;
  String? _bootSourceError;

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

    // A Linux VM with nothing to boot from boots into nothing: EFI finds no
    // boot option and the guest powers off within seconds. Require a boot
    // source rather than let the user create a VM that can only fail (macOS
    // guests always install from a restore image). Only the chosen kind
    // counts — whatever was typed under the other choice is ignored.
    final isIso = _bootKind == VmBootKind.installerIso;
    final bootSource = (isIso ? _iso : _image).text.trim();
    if (_guestOs == 'linux' && bootSource.isEmpty) {
      setState(() {
        _nameError = null;
        _bootSourceError = 'vmbootsourcerequired-text'.i18n();
      });
      return;
    }

    setState(() {
      _nameError = null;
      _bootSourceError = null;
      _creating = true;
    });

    // A catalog pick downloads (or reuses) the file first; a plain path
    // goes straight through. The catalog entry's own kind decides how the
    // file is used (a cloud image seeds the disk, an ISO is attached), so a
    // catalog name pasted under the wrong choice still boots correctly.
    var isoPath = isIso ? bootSource : '';
    var imagePath = isIso ? '' : bootSource;
    final catalogEntry =
        _guestOs == 'linux' ? VmImageCatalog.entryFor(bootSource) : null;
    if (catalogEntry != null) {
      final token = CancelSignal();
      _cancelSignal = token;
      try {
        final downloadedPath = await vmImageCatalogBuilder().download(
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
        if (catalogEntry.isCloudImage) {
          imagePath = downloadedPath;
          isoPath = '';
        } else {
          isoPath = downloadedPath;
          imagePath = '';
        }
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
          imagePath: imagePath,
          diskSizeGb: _intOf(_diskSize, 32),
          cpus: _intOf(_cpus, 2),
          memoryGb: _intOf(_memory, 4),
          user: _user.text.trim().isEmpty ? 'user' : _user.text.trim(),
        );
      }
      if (_recipeId.isNotEmpty) {
        // A fresh VM is not reachable yet; the recipe installs on the first
        // run once the guest answers (home list applies pending recipes).
        await prefs.setString('PendingRecipe_$name', _recipeId);
      }
      Notify.message(
          _recipeId.isEmpty
              ? 'vmcreated-text'.i18n([name])
              : 'vmcreatedwithservice-text'.i18n(
                  [name, RecipeCatalog.byId(_recipeId)?.name ?? _recipeId]),
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

  /// The boot-source choice for a Linux guest: two radio buttons and one
  /// field that follows them. The field is an autocomplete over the curated
  /// arm64 catalog filtered to the chosen kind — cloud images under "Cloud
  /// image", ISOs under "Installer ISO" — (picked entries are downloaded
  /// and cached, the way the Windows create screen offers its rootfs
  /// catalogue), while a local path or the file picker keeps working
  /// unchanged. The list opens on click, so the catalog is visible before
  /// anything is typed. Each kind keeps its own controller, so switching
  /// back and forth does not lose what was entered.
  /// A "nothing to boot from" complaint was about the other choice's
  /// field; it must not linger under the one just switched to.
  void _chooseBootKind(VmBootKind kind) {
    setState(() {
      _bootKind = kind;
      _bootSourceError = null;
    });
  }

  Widget _bootSourceSection() {
    final isIso = _bootKind == VmBootKind.installerIso;
    final controller = isIso ? _iso : _image;
    final suggestions = [
      for (final entry in VmImageCatalog.entries)
        if (entry.isCloudImage != isIso) suggestionItem(entry.name),
    ];
    return FormCard(
      icon: FluentIcons.pop_expand,
      // The card's heading is the label the two choices used to carry; a
      // second one inside it would say "Boot from" twice.
      title: 'vmbootsource-text'.i18n(),
      children: [
        // A Wrap, not a Row: the two labels do not fit side by side in
        // every locale (or at a narrow window), and must not overflow.
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            RadioButton(
              key: const ValueKey('test-vm-boot-cloud-image'),
              checked: !isIso,
              onChanged: _creating
                  ? null
                  : (_) => _chooseBootKind(VmBootKind.cloudImage),
              content: Text('vmbootcloudimage-text'.i18n()),
            ),
            RadioButton(
              key: const ValueKey('test-vm-boot-installer-iso'),
              checked: isIso,
              onChanged: _creating
                  ? null
                  : (_) => _chooseBootKind(VmBootKind.installerIso),
              content: Text('vmbootinstalleriso-text'.i18n()),
            ),
          ],
        ),
        InfoLabel(
          label: isIso
              ? 'vminstalleriso-text'.i18n()
              : 'vmcloudimage-text'.i18n(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SuggestOnFocus<String>(
                      key: ValueKey(isIso ? 'test-vm-iso' : 'test-vm-image'),
                      builder: (context, boxKey, focusNode) =>
                          AutoSuggestBox<String>(
                        key: boxKey,
                        focusNode: focusNode,
                        controller: controller,
                        enabled: !_creating,
                        placeholder: isIso
                            ? 'vmisoplaceholder-text'.i18n()
                            : 'vmcloudimageplaceholder-text'.i18n(),
                        items: suggestions,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: _creating
                        ? null
                        : () => _pickFile(
                            controller,
                            isIso
                                ? const ['iso']
                                : const ['img', 'raw', 'qcow2']),
                    child: Text('selectfile-text'.i18n()),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                    isIso
                        ? 'vminstallerisohint-text'.i18n()
                        : 'vmcloudimagehint-text'.i18n(),
                    style: TextStyle(
                        fontSize: 12, color: secondaryTextColor(context))),
              ),
              if (_bootSourceError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(_bootSourceError!,
                      key: const ValueKey('test-vm-boot-error'),
                      style: TextStyle(color: destructiveColor(context))),
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
                              fontSize: 12,
                              color: secondaryTextColor(context))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
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
              FormPageHeader(
                icon: FluentIcons.add_to,
                title: 'createnewinstance-text'.i18n(),
                description: 'vmcreateinfo-text'.i18n(),
              ),
              const SizedBox(height: 20),
              FormCard(
                icon: FluentIcons.text_document,
                title: 'createbasics-text'.i18n(),
                children: [
                  InfoLabel(
                    label: 'name-text'.i18n(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextBox(
                          key: const ValueKey('test-vm-name'),
                          controller: _name,
                          enabled: !_creating,
                        ),
                        if (_nameError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(_nameError!,
                                key: const ValueKey('test-vm-name-error'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: destructiveColor(context))),
                          ),
                      ],
                    ),
                  ),
                  InfoLabel(
                    label: 'vmguestos-text'.i18n(),
                    child: ComboBox<String>(
                      key: const ValueKey('test-vm-guest-os'),
                      value: _guestOs,
                      isExpanded: true,
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
                  if (isLinux)
                    InfoLabel(
                      label: 'optionalusername-text'.i18n(),
                      child: TextBox(controller: _user, enabled: !_creating),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (isLinux)
                _bootSourceSection()
              else
                FormCard(
                  icon: FluentIcons.pop_expand,
                  title: 'vmbootsource-text'.i18n(),
                  spacing: 8,
                  children: [
                    _fileField(
                      'vmrestoreimage-text'.i18n(),
                      _restoreImage,
                      const ['ipsw'],
                      hint: 'vmrestoreimagehint-text'.i18n(),
                      key: const ValueKey('test-vm-restore-image'),
                    ),
                    Text('vmmacosrequiresapplesilicon-text'.i18n(),
                        style: TextStyle(
                            fontSize: 12, color: secondaryTextColor(context))),
                  ],
                ),
              const SizedBox(height: 12),
              FormCard(
                icon: FluentIcons.processing,
                title: 'createresources-text'.i18n(),
                children: [
                  // Bottom-aligned: the three labels are short in English and
                  // two lines long in more than one locale, and the boxes have
                  // to line up either way.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
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
                  // Optional: a curated service (MinIO, Postgres, …)
                  // installed into the VM the first time it is running.
                  InfoLabel(
                    label: 'vmservice-text'.i18n(),
                    child: ComboBox<String>(
                      key: const ValueKey('test-vm-recipe'),
                      value: _recipeId,
                      isExpanded: true,
                      placeholder: Text('vmservicenone-text'.i18n()),
                      items: [
                        ComboBoxItem(
                            value: '',
                            child: Text('vmservicenone-text'.i18n())),
                        for (final recipe in RecipeCatalog.recipes)
                          ComboBoxItem(
                            value: recipe.id,
                            child: Text(
                                '${recipe.name} — ${recipe.description}',
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _creating
                          ? null
                          : (value) => setState(() => _recipeId = value ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
