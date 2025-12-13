import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/mount_service.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

void showMountDialog() {
  final context = GlobalVariable.infobox.currentContext!;
  showDialog(
    context: context,
    builder: (context) => const MountDialog(),
  );
}

class MountDialog extends StatefulWidget {
  const MountDialog({super.key});

  @override
  State<MountDialog> createState() => _MountDialogState();
}

class _MountDialogState extends State<MountDialog> {
  final MountService _mountService = MountService();
  bool _loading = false;
  int _selectedTab = 0; // 0: Physical, 1: VHD, 2: Unmount

  // Physical Disk
  List<PhysicalDisk> _disks = [];
  PhysicalDisk? _selectedDisk;
  final TextEditingController _partitionController = TextEditingController();
  final TextEditingController _typeController = TextEditingController();
  final TextEditingController _optionsController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _bare = false;

  // VHD
  final TextEditingController _vhdPathController = TextEditingController();
  final TextEditingController _vhdPartitionController = TextEditingController();
  final TextEditingController _vhdTypeController = TextEditingController();
  final TextEditingController _vhdOptionsController = TextEditingController();
  final TextEditingController _vhdNameController = TextEditingController();
  bool _vhdBare = false;

  // Unmount
  final TextEditingController _unmountPathController = TextEditingController();
  List<String> _mountedDisks = [];

  @override
  void initState() {
    super.initState();
    _loadDisks();
    _loadMountedDisks();
  }

  Future<void> _loadMountedDisks() async {
    try {
      var disks = await _mountService.getMountedDisks();
      if (mounted) {
        setState(() {
          _mountedDisks = disks;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDisks() async {
    setState(() => _loading = true);
    try {
      _disks = await _mountService.getPhysicalDisks();
      if (_disks.isNotEmpty) {
        _selectedDisk = _disks.first;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _execute() async {
    setState(() => _loading = true);
    try {
      if (_selectedTab == 0) {
        if (_selectedDisk == null) return;
        await _mountService.mountDisk(
          _selectedDisk!.deviceId,
          partition: _partitionController.text,
          type: _typeController.text,
          options: _optionsController.text,
          name: _nameController.text,
          bare: _bare,
        );
        if (mounted) Notify.message('diskmounted-text'.i18n());
      } else if (_selectedTab == 1) {
        if (_vhdPathController.text.isEmpty) return;
        await _mountService.mountVhd(
          _vhdPathController.text,
          partition: _vhdPartitionController.text,
          type: _vhdTypeController.text,
          options: _vhdOptionsController.text,
          name: _vhdNameController.text,
          bare: _vhdBare,
        );
        if (mounted) Notify.message('vhdmounted-text'.i18n());
      } else {
        if (_unmountPathController.text.isEmpty) return;
        await _mountService.unmount(_unmountPathController.text);
        if (mounted) Notify.message('diskunmounted-text'.i18n());
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        bool handled = false;

        // Handle unmount by name failure for auto-generated mounts
        if (_selectedTab == 2 &&
            _mountedDisks.contains(_unmountPathController.text)) {
          // Check if it's likely the specific error (or just assume it is if it failed by name)
          // The error from WSL is usually "The system cannot find the file specified" or "invalid name"
          handled = true;
          await showDialog(
            context: context,
            builder: (dialogContext) => ContentDialog(
              title: Text('unmountfailed-text'.i18n()),
              content: Text('unmountfailed-msg'.i18n()),
              actions: [
                Button(
                  child: Text('cancel-text'.i18n()),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
                FilledButton(
                  child: Text('selectfile-text'.i18n()),
                  onPressed: () async {
                    Navigator.pop(dialogContext); // Close error dialog
                    FilePickerResult? result =
                        await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['vhdx', 'vhd'],
                    );
                    if (result != null) {
                      setState(() => _loading = true);
                      try {
                        await _mountService.unmount(result.files.single.path!);
                        if (mounted) {
                          Notify.message('diskunmounted-text'.i18n());
                          Navigator.pop(context); // Close mount dialog
                        }
                      } catch (e2) {
                        if (mounted) {
                          showDialog(
                            context: context,
                            builder: (context) => ContentDialog(
                              title: Text('error-text'.i18n()),
                              content: SelectableText(e2.toString()),
                              actions: [
                                Button(
                                  child: Text('ok-text'.i18n()),
                                  onPressed: () => Navigator.pop(context),
                                )
                              ],
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    }
                  },
                ),
              ],
            ),
          );
        }

        if (!handled) {
          // Check for "attached but not mounted" error
          // Look for: wsl.exe --unmount <path>
          RegExp unmountRegex = RegExp(r'wsl\.exe --unmount (.*?)["\n]');
          Match? match = unmountRegex.firstMatch(errorMessage);
          if (match != null) {
            String path = match.group(1)?.trim() ?? '';
            if (path.isNotEmpty) {
              handled = true;
              await showDialog(
                context: context,
                builder: (dialogContext) => ContentDialog(
                  title: Text('mountfailed-text'.i18n()),
                  content: Text('mountfailed-msg'.i18n()),
                  actions: [
                    Button(
                      child: Text('cancel-text'.i18n()),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                    FilledButton(
                      child: Text('detach-text'.i18n()),
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        setState(() => _loading = true);
                        try {
                          await _mountService.unmount(path);
                          if (mounted) {
                            Notify.message('diskunmounted-text'.i18n());
                          }
                        } catch (e2) {
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (context) => ContentDialog(
                                title: Text('error-text'.i18n()),
                                content: SelectableText(e2.toString()),
                                actions: [
                                  Button(
                                    child: Text('ok-text'.i18n()),
                                    onPressed: () => Navigator.pop(context),
                                  )
                                ],
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                    ),
                  ],
                ),
              );
            }
          }
        }

        if (!handled) {
          if (errorMessage.contains('process cannot access') ||
              errorMessage.contains('being used by another process')) {
            errorMessage += 'diskofflinehint-text'.i18n();
          }

          showDialog(
            context: context,
            builder: (context) => ContentDialog(
              title: Text('error-text'.i18n()),
              content: SelectableText(errorMessage),
              actions: [
                Button(
                  child: Text('ok-text'.i18n()),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text('mountdisk-text'.i18n()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tabs
            Row(
              children: [
                RadioButton(
                  checked: _selectedTab == 0,
                  content: Text('physicaldisk-text'.i18n()),
                  onChanged: (v) => setState(() => _selectedTab = 0),
                ),
                const SizedBox(width: 20),
                RadioButton(
                  checked: _selectedTab == 1,
                  content: Text('vhdimage-text'.i18n()),
                  onChanged: (v) => setState(() => _selectedTab = 1),
                ),
                const SizedBox(width: 20),
                RadioButton(
                  checked: _selectedTab == 2,
                  content: Text('unmount-text'.i18n()),
                  onChanged: (v) => setState(() => _selectedTab = 2),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_loading)
              const ProgressBar()
            else if (_selectedTab == 0)
              _buildPhysicalDiskForm()
            else if (_selectedTab == 1)
              _buildVhdForm()
            else
              _buildUnmountForm(),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel-text'.i18n()),
        ),
        FilledButton(
          onPressed: _loading ? null : _execute,
          child: Text(
              _selectedTab == 2 ? 'unmount-text'.i18n() : 'mount-text'.i18n()),
        ),
      ],
    );
  }

  Widget _buildPhysicalDiskForm() {
    if (_disks.isEmpty) {
      return Column(
        children: [
          Text('nodisksfound-text'.i18n()),
          const SizedBox(height: 10),
          Button(
            onPressed: _loadDisks,
            child: Text('refresh-text'.i18n()),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: 'selectdisk-text'.i18n(),
          child: ComboBox<PhysicalDisk>(
            isExpanded: true,
            items: _disks
                .map((e) => ComboBoxItem(
                      value: e,
                      child: Text(
                        e.toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            value: _selectedDisk,
            onChanged: (v) => setState(() => _selectedDisk = v),
          ),
        ),
        if (_selectedDisk != null && _selectedDisk!.isUsb)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: InfoBar(
              title: Text('usbdetected-text'.i18n()),
              content: Text('usbdetected-msg'.i18n()),
              severity: InfoBarSeverity.warning,
            ),
          ),
        const SizedBox(height: 10),
        Checkbox(
          checked: _bare,
          onChanged: (v) => setState(() => _bare = v ?? false),
          content: Text('bare-text'.i18n()),
        ),
        if (!_bare) ...[
          const SizedBox(height: 10),
          InfoLabel(
            label: 'customname-text'.i18n(),
            child: TextBox(
              controller: _nameController,
              placeholder: 'customnamehint-text'.i18n(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InfoLabel(
                  label: 'partition-text'.i18n(),
                  child: TextBox(
                    controller: _partitionController,
                    placeholder: 'examplepartition-text'.i18n(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InfoLabel(
                  label: 'filesystemtype-text'.i18n(),
                  child: TextBox(
                    controller: _typeController,
                    placeholder: 'examplefilesystem-text'.i18n(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InfoLabel(
            label: 'mountoptions-text'.i18n(),
            child: TextBox(
              controller: _optionsController,
              placeholder: 'mountoptionshint-text'.i18n(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVhdForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: 'vhdpath-text'.i18n(),
          child: Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _vhdPathController,
                  placeholder: 'examplepath-text'.i18n(),
                ),
              ),
              const SizedBox(width: 10),
              Button(
                child: const Icon(FluentIcons.folder_open),
                onPressed: () async {
                  FilePickerResult? result =
                      await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['vhdx', 'vhd'],
                  );
                  if (result != null) {
                    setState(() {
                      _vhdPathController.text = result.files.single.path!;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Checkbox(
          checked: _vhdBare,
          onChanged: (v) => setState(() => _vhdBare = v ?? false),
          content: const Text('Bare (Attach only, do not mount)'),
        ),
        if (!_vhdBare) ...[
          const SizedBox(height: 10),
          InfoLabel(
            label: 'customname-text'.i18n(),
            child: TextBox(
              controller: _vhdNameController,
              placeholder: 'customnamehint-text'.i18n(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InfoLabel(
                  label: 'partition-text'.i18n(),
                  child: TextBox(
                    controller: _vhdPartitionController,
                    placeholder: 'examplepartition-text'.i18n(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InfoLabel(
                  label: 'filesystemtype-text'.i18n(),
                  child: TextBox(
                    controller: _vhdTypeController,
                    placeholder: 'examplefilesystem-text'.i18n(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InfoLabel(
            label: 'mountoptions-text'.i18n(),
            child: TextBox(
              controller: _vhdOptionsController,
              placeholder: 'mountoptionshint-text'.i18n(),
            ),
          ),
        ],
      ],
    );
  }

  String _formatMountName(String name) {
    if (name.startsWith('PHYSICALDRIVE')) {
      return 'physicaldrive-text'.i18n() + ' ${name.substring(13)}';
    }
    return name;
  }

  Widget _buildUnmountForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_mountedDisks.isNotEmpty) ...[
          InfoLabel(
            label: 'selectmounteddisk-text'.i18n(),
            child: ComboBox<String>(
              isExpanded: true,
              placeholder: Text('selectdiskplaceholder-text'.i18n()),
              items: _mountedDisks
                  .map((e) => ComboBoxItem(
                        value: e,
                        child: Text(_formatMountName(e)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    if (v.startsWith('PHYSICALDRIVE')) {
                      _unmountPathController.text = '\\\\.\\$v';
                    } else {
                      _unmountPathController.text = v;
                    }
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        InfoLabel(
          label: 'diskpathtounmount-text'.i18n(),
          child: TextBox(
            controller: _unmountPathController,
            placeholder: 'exampleunmountpath-text'.i18n(),
          ),
        ),
        const SizedBox(height: 10),
        Text('unmountpathhint-text'.i18n()),
      ],
    );
  }
}
