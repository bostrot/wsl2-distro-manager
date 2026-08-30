import 'dart:io';

import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/api/docker_images.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/api/wsl_errors.dart';
import 'package:wsl2distromanager/api/app.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/named_button.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/rating_dialog.dart';
import 'package:wsl2distromanager/components/ai_diagnosis.dart';
import 'package:wsl2distromanager/components/error_view.dart';

enum CreateSourceType { repo, turnkey, local, docker, dockerLocalImage, vhdx }

/// Whether a source type produces a distro we can add a default user to.
///
/// A turnkey appliance, a Docker image and an imported VHDX all bring their own
/// account layout, so the toggle is hidden for them — and must not then be
/// treated as "user requested" by the validation below.
bool supportsDefaultUser(CreateSourceType type) =>
    type != CreateSourceType.turnkey &&
    type != CreateSourceType.docker &&
    type != CreateSourceType.vhdx;

/// Why a create attempt failed.
///
/// [diagnosable] separates something going wrong during the install — worth
/// offering an AI diagnosis for — from a form the user can simply correct.
class CreateFailure {
  const CreateFailure(this.message,
      {this.diagnosable = true, this.details = ''});

  final String message;
  final bool diagnosable;

  /// What the tool actually wrote.
  ///
  /// Kept apart from [message] so the banner can fold it away and the AI
  /// diagnosis can still have all of it (audit CI-22).
  final String details;
}

progressFn(current, total, currentStep, totalStep) =>
    _layerProgress(current, total, currentStep, totalStep, null);

/// Docker layer progress, for the status bar and — when the caller has one —
/// for the create screen's bar as well.
///
/// The layer path always had the richer text; it was only ever pushed to the
/// corner toast, which is what left the page itself with nothing to draw
/// (audit CI-16).
void _layerProgress(int current, int total, int currentStep, int totalStep,
    void Function(CreateProgress)? onProgress) {
  if (currentStep != -1) {
    String progressInMB = (currentStep / 1024 / 1024).toStringAsFixed(2);
    String percentage = (currentStep / totalStep * 100).toStringAsFixed(0);
    final label = '${'downloading-text'.i18n()}'
        ' Layer ${current + 1}/$total: $percentage% ($progressInMB MB)';
    Notify.message(label);
    onProgress?.call(CreateProgress(
      phase: CreatePhase.downloading,
      label: label,
      // Across all layers, not within one: a bar that restarts at zero N
      // times reads as N failed downloads.
      fraction: total > 0 && totalStep > 0
          ? ((current + (currentStep / totalStep)) / total).clamp(0.0, 1.0)
          : null,
    ));
  } else {
    final label = 'extractinglayers-text'.i18n(['$current', '$total']);
    Notify.message(label);
    onProgress?.call(CreateProgress(
      phase: CreatePhase.extracting,
      label: label,
      fraction: total > 0 ? (current / total).clamp(0.0, 1.0) : null,
    ));
  }
}

/// Reports a failed create and always returns false.
///
/// Every exit from [createInstance] has to take the "Creating instance..."
/// spinner down with it. The status bar has no other owner, so a failure that
/// only wrote to the inline banner left the spinner turning for the rest of
/// the session.
bool _failCreate(
  String message,
  ValueNotifier<CreateFailure?>? onError, {
  bool diagnosable = true,
  String details = '',
}) {
  if (onError == null) {
    Notify.message(details.isEmpty ? message : '$message $details'.trim(),
        severity: InfoBarSeverity.error);
  } else {
    // The banner carries the text; the status bar only has to stop spinning.
    Notify.message('');
    onError.value =
        CreateFailure(message, diagnosable: diagnosable, details: details);
  }
  return false;
}

/// Reports a cancelled create and always returns false.
///
/// Not routed through [_failCreate]: a cancel is the user getting what they
/// asked for, so it clears the error banner rather than filling it, and the
/// status bar says so once instead of leaving the spinner turning.
bool _cancelCreate(ValueNotifier<CreateFailure?>? onError) {
  onError?.value = null;
  Notify.message('createcancelled-text'.i18n(),
      severity: InfoBarSeverity.warning);
  return false;
}

/// Returns true on success, false on any error so the caller can keep the dialog open.
Future<bool> createInstance(
  TextEditingController nameController,
  TextEditingController locationController,
  WSLApi api,
  TextEditingController autoSuggestBox,
  TextEditingController userController, {
  DockerImage? dockerImage,
  bool isDocker = false,
  bool isDockerLocalImage = false,
  bool isVhdx = false,
  bool requireUser = false,
  ValueNotifier<CreateFailure?>? onError,
  ValueNotifier<CreateProgress?>? onProgress,
  CancelSignal? cancelSignal,
}) async {
  plausible.event(name: "wsl_create");
  DockerImage docker = dockerImage ?? DockerImage();
  void report(CreateProgress progress) {
    if (onProgress != null) onProgress.value = progress;
  }

  // The layer download runs inside `package:chunked_downloader`'s read loop,
  // which has no cancel hook of its own; the progress callback is the one
  // place this code gets control back per chunk, so that is where the token
  // is checked. Throwing unwinds `_downloadBlob`, which deletes its own
  // partial `.tmp` on the way out.
  void layerProgress(int current, int total, int currentStep, int totalStep) {
    cancelSignal?.throwIfCancelled();
    _layerProgress(
        current, total, currentStep, totalStep, onProgress == null ? null : report);
  }

  final useRemoteWsl = prefs.getBool('UseRemoteWSL') ?? false;
  String label = nameController.text;
  // Replace all special characters with _
  String name = label.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
  // "Create default user" with an empty name used to import the distro, skip
  // the account silently and still report success.
  if (requireUser && userController.text.trim().isEmpty) {
    return _failCreate('errorenterusername-text'.i18n(), onError,
        diagnosable: false);
  }
  if (name != '') {
    // Check if distro exists
    var instances = await api.list(true);
      if (instances.all
          .any((element) => element.toLowerCase() == name.toLowerCase())) {
        final msg = 'distroexists-text'.i18n();
        return _failCreate(msg, onError, diagnosable: false);
      }

    String distroName = autoSuggestBox.text;

    // Set paths
    Notify.message('creatinginstance-text'.i18n(), loading: true);
    String location = locationController.text;
    if (!useRemoteWsl && location == '') {
      location = prefs.getString("DistroPath") ?? getDefaultStorageRootPath();
    }
    if (location.isNotEmpty) {
      location += '${Platform.pathSeparator}$name';
    }
    final effectiveLocation = useRemoteWsl
        ? api.remoteInstallPath(name)
        : location;

    // Check if docker image (remote registry)
    bool isDockerImage = isDocker;
    if (!isDockerImage && !isVhdx) {
      if (distroName.startsWith('dockerhub:') ||
          distroName.startsWith('docker:')) {
        isDockerImage = true;
      } else if (distroName.contains(':') && !distroName.contains('\\')) {
        isDockerImage = true;
      }
    }

    // Handle remote Docker image download from registry
    if (isDockerImage) {
      // Remove prefix
      if (distroName.startsWith('dockerhub:')) {
        distroName = autoSuggestBox.text.split('dockerhub:')[1];
      } else if (distroName.startsWith('docker:')) {
        distroName = autoSuggestBox.text.split('docker:')[1];
      }
      // Get tag
      if (!distroName.contains(':')) {
        distroName += ':latest';
      }
      String? image = distroName.split(':')[0];
      String? tag = distroName.split(':')[1];

      if (!distroName.contains('/')) {
        image = 'library/$image';
      }

      bool isDownloaded = false;
      // Check if image already downloaded
      if (await docker.isDownloaded(image, tag: tag)) {
        isDownloaded = true;
      }

      // Check if image exists
      if (!isDownloaded && await docker.hasImage(image, tag: tag)) {
        // Download image
        Notify.message('${'downloading-text'.i18n()}...');
        docker.distroName = distroName;
        try {
          await docker.getRootfs(name, image, tag: tag, progress: layerProgress);
        } on CancelledException {
          return _cancelCreate(onError);
        } catch (e) {
          final msg = e.toString().replaceAll('Exception: ', '');
          final err = '${'errordownloading-text'.i18n()}: $msg';
          return _failCreate(err, onError, diagnosable: true);
        }
        Notify.message('downloaded-text'.i18n(),
            severity: InfoBarSeverity.success);
        // Set distropath with distroName
        distroName = docker.filename(image, tag);
      } else if (!isDownloaded) {
        final err = '${'distronotfound-text'.i18n()}: $image:$tag';
        return _failCreate(err, onError, diagnosable: false);
      }

      if (isDownloaded) {
        // Set distropath with distroName
        distroName = docker.filename(image, tag);
      }
    }

    // Handle local Docker image export via docker save
    if (isDockerLocalImage) {
      isDockerImage = true;
      String localImagePath = autoSuggestBox.text.trim();
      if (localImagePath.isEmpty) {
        final err = 'selectdockerimage-text'.i18n();
        return _failCreate(err, onError, diagnosable: false);
      }

      try {
        await docker.getRootfsFromLocalImage(name, localImagePath,
            progress: layerProgress);
        distroName = docker.filename(
            localImagePath.split(':')[0],
            localImagePath.contains(':') ? localImagePath.split(':')[1] : null);
      } on CancelledException {
        return _cancelCreate(onError);
      } catch (e) {
        final failure = WslFailure.from(e);
        return _failCreate(
            '${'dockerexportfailed-text'.i18n()} ${failure.explanation}'.trim(),
            onError,
            diagnosable: true,
            details: failure.details);
      }
    }

    // Navigator.of(context, rootNavigator: true).pop();

    // Create instance
    final ProcessResult result;
    try {
      result = await api.create(
        name, distroName, effectiveLocation, (String msg) => Notify.message(msg),
          image: isDockerImage,
          isVhd: isVhdx,
          onProgress: onProgress == null ? null : report,
          cancelSignal: cancelSignal);
    } on CancelledException {
      return _cancelCreate(onError);
    }

    // Check if instance was created then handle postprocessing
    if (result.exitCode != 0) {
      // Both streams: wsl.exe does not consistently pick one, and the code it
      // stamps on the failure is the only part that is not localized. The
      // banner gets a translated sentence and keeps the raw text behind a
      // disclosure instead of printing it as the error (audit CI-22).
      final stdout = result.stdout is List<int>
          ? WSLApi().utf8Convert(result.stdout as List<int>)
          : result.stdout;
      final failure = WslFailure.fromStreams(stdout, result.stderr);
      return _failCreate(
          '${'createinstancefailed-text'.i18n([label])} ${failure.explanation}'.trim(),
          onError,
          diagnosable: true,
          details: failure.details);
    } else {
      var userCmds = prefs.getStringList('UserCmds_$distroName');
      var groupCmds = prefs.getStringList('GroupCmds_$distroName');
      if (userCmds != null && groupCmds != null) {
        for (int i = 0; i < groupCmds.length; i++) {
          var cmd = groupCmds[i].replaceAll("/bin/sh -c ", "");
          cmd = cmd.replaceAll(RegExp(r'\s+'), ' ');
          await api.exec(name, [cmd]);
        }
        for (int i = 0; i < userCmds.length; i++) {
          var cmd = userCmds[i].replaceAll("/bin/sh -c ", "");
          // Replace multiple spaces with one
          cmd = cmd.replaceAll(RegExp(r'\s+'), ' ');
          await api.exec(name, [cmd]);
        }
      }
      String user = userController.text.trim();
      if (user != '') {
        // One script that detects the distro's package manager and userland
        // instead of five hard-coded apt-get/useradd lines. Those worked on
        // Ubuntu, Debian and Kali and silently created no user at all on the
        // other thirteen catalogue entries — see WSLApi.buildUserSetupScript.
        final setup = await api.createUser(name, user);
        if (setup.exitCode == 0) {
          // Only worth prompting for a password once the account exists. This
          // opens a console window outside the app, so say so first — and the
          // call now waits for that window to close rather than racing past it
          // (audit CI-13).
          report(CreateProgress(
            phase: CreatePhase.importing,
            label: 'passwordwindowopen-text'.i18n([user]),
          ));
          Notify.message('passwordwindowopen-text'.i18n([user]),
              loading: true);
          await api.exec(name, ['passwd $user']);
          // Use setSetting so existing wsl.conf sections (e.g. [boot] systemd=true) are preserved
          await api.setSetting(name, 'user', 'default', user);
          prefs.setString('StartPath_$name', '/home/$user');
          prefs.setString('StartUser_$name', user);

          // Closing that window without typing anything used to leave the
          // account passwordless in silence. Null means the distro could not
          // answer, which is not the same as "no password" and is not warned
          // about.
          if (await api.hasPassword(name, user) == false) {
            Notify.message('createdinstancenopassword-text'.i18n([user]),
                severity: InfoBarSeverity.warning);
          } else {
            Notify.message('createdinstance-text'.i18n(),
                severity: InfoBarSeverity.success);
          }
        } else {
          // Deliberately no `default=<user>` in wsl.conf on this path: naming
          // a user that does not exist stops the distro from starting at all,
          // which is worse than the root-only shell the import already gives.
          Notify.message('createdinstancenouser-text'.i18n(),
              severity: InfoBarSeverity.warning);
        }
      } else {
        // Turnkey images may still need first-start initialization,
        // but we no longer install fake systemd.
        if (distroName.contains('Turnkey')) {
          // Set first start variable
          prefs.setBool('TurnkeyFirstStart_$name', true);
          Notify.message('createdinstance-text'.i18n(),
              severity: InfoBarSeverity.success);
        } else {
          Notify.message('createdinstance-text'.i18n(),
              severity: InfoBarSeverity.success);
        }
      }
      // Save distro label
      prefs.setString('DistroName_$name', label);
      // Save distro path
      prefs.setString('Path_$name', effectiveLocation);
      recordInstanceCreated();
      return true;
    }
    // Download distro check
  } else {
    // One message for one situation — 'entername-text' was a duplicate of
    // this string minus its full stop (audit CI-21).
    final msg = 'errorentername-text'.i18n();
    return _failCreate(msg, onError, diagnosable: false);
  }
}

class CreateWidget extends StatefulWidget {
  const CreateWidget({
    Key? key,
    required this.nameController,
    required this.api,
    required this.autoSuggestBox,
    required this.locationController,
    required this.userController,
    required this.sourceType,
    this.creating,
    this.createError,
    this.createUserEnabled,
  }) : super(key: key);

  final TextEditingController nameController;
  final WSLApi api;
  final TextEditingController autoSuggestBox;
  final TextEditingController locationController;
  final TextEditingController userController;
  final ValueNotifier<CreateSourceType> sourceType;
  final ValueNotifier<bool>? creating;
  final ValueNotifier<CreateFailure?>? createError;

  /// Mirrors the "create default user" toggle so the owning page can require a
  /// username before it starts the install.
  final ValueNotifier<bool>? createUserEnabled;

  @override
  State<CreateWidget> createState() => _CreateWidgetState();
}

class _CreateWidgetState extends State<CreateWidget> {
  bool turnkey = false;
  CreateSourceType sourceType = CreateSourceType.repo;
  FocusNode node = FocusNode();
  final GlobalKey<AutoSuggestBoxState<String>> _autoSuggestBoxKey = GlobalKey();
  List<String> existingDistros = [];
  bool nameExists = false;
  bool customLocation = false;
  bool createUser = false;

  @override
  void initState() {
    super.initState();
    _fetchDistros();
    widget.nameController.addListener(_checkName);
    widget.sourceType.addListener(_onSourceTypeChanged);
    node.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.nameController.removeListener(_checkName);
    widget.sourceType.removeListener(_onSourceTypeChanged);
    node.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (node.hasFocus) {
      _autoSuggestBoxKey.currentState?.showOverlay();
    }
  }

  void _onSourceTypeChanged() {
    if (mounted) {
      setState(() {
        sourceType = widget.sourceType.value;
      });
    }
  }

  void _fetchDistros() async {
    var instances = await widget.api.list(true);
    if (mounted) {
      setState(() {
        existingDistros = instances.all;
        _checkName();
      });
    }
  }

  void _checkName() {
    String name = widget.nameController.text;
    String sanitizedName = name.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
    bool exists = false;
    if (sanitizedName.isNotEmpty) {
      exists = existingDistros.any(
          (element) => element.toLowerCase() == sanitizedName.toLowerCase());
    }

    if (exists != nameExists) {
      setState(() {
        nameExists = exists;
      });
    }
  }

  /// The chosen source type's short label, for the closed control.
  String _sourceTypeLabel(CreateSourceType type) {
    switch (type) {
      case CreateSourceType.repo:
        return 'downloadfromrepo-text'.i18n();
      case CreateSourceType.turnkey:
        return 'turnkeylinux-text'.i18n();
      case CreateSourceType.local:
        return 'localrootfsfile-text'.i18n();
      case CreateSourceType.docker:
        return 'dockerimage-text'.i18n();
      case CreateSourceType.dockerLocalImage:
        return 'localdockerimage-text'.i18n();
      case CreateSourceType.vhdx:
        return 'importvhdx-text'.i18n();
    }
  }

  /// One flyout entry: the label with a one-line description under it, so a
  /// source type is not a bare piece of developer jargon (audit CI-26).
  MenuFlyoutItem _sourceTypeItem(
      CreateSourceType type, String labelKey, String descKey) {
    return MenuFlyoutItem(
      selected: sourceType == type,
      text: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(labelKey.i18n()),
          Text(descKey.i18n(),
              style: TextStyle(
                  fontSize: 12.0, color: secondaryTextColor(context))),
        ],
      ),
      onPressed: () => widget.sourceType.value = type,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.createError != null)
          ValueListenableBuilder<CreateFailure?>(
            valueListenable: widget.createError!,
            builder: (context, failure, _) {
              if (failure == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: InfoBar(
                  title: Text(failure.message),
                  content: failure.details.isEmpty
                      ? null
                      : ErrorDetails(details: failure.details),
                  severity: InfoBarSeverity.error,
                  isLong: true,
                  action: failure.diagnosable
                      ? AiDiagnoseButton(
                          errorMessage: failure.details.isEmpty
                              ? failure.message
                              : failure.details)
                      : null,
                ),
              );
            },
          ),
        Container(
          height: 5.0,
        ),
        MergeSemantics(
          child: Tooltip(
            message: 'namehint-text'.i18n(),
            child: TextBox(
              key: const ValueKey('test-create-name-input'),
              controller: widget.nameController,
              placeholder: 'name-text'.i18n(),
              suffix: IconButton(
                icon: const Icon(FluentIcons.chrome_close, size: 11.0),
                onPressed: () {
                  widget.nameController.clear();
                },
              ),
            ),
          ),
        ),
        if (nameExists)
          Padding(
            padding: const EdgeInsets.only(top: 4.0, left: 4.0),
            // The one inline message in the app that was bold, and the one
            // that hardcoded its red instead of resolving it per theme
            // (audit CI-03).
            child: Text(
              'distroexists-text'.i18n(),
              style:
                  TextStyle(color: destructiveColor(context), fontSize: 12.0),
            ),
          ),
        Container(
          height: 10.0,
        ),
        Container(
          height: 5.0,
        ),
        InfoLabel(
          label: 'sourcetype-text'.i18n(),
          // A DropDownButton's flyout opens *below* the control; the ComboBox
          // it replaces aligned the popup over its selected item, so with a
          // later value chosen it opened upward and covered the title and the
          // name the user had just typed (audit CI-25). The flyout also
          // groups the three sources that download from the three that read a
          // local file, and says what each one needs (CI-26).
          child: DropDownButton(
            key: const ValueKey('test-create-sourcetype'),
            title: Expanded(
              child: Text(_sourceTypeLabel(sourceType),
                  textAlign: TextAlign.start),
            ),
            items: [
              _sourceTypeItem(CreateSourceType.repo, 'downloadfromrepo-text',
                  'downloadfromrepo-desc'),
              _sourceTypeItem(CreateSourceType.turnkey, 'turnkeylinux-text',
                  'turnkeylinux-desc'),
              _sourceTypeItem(CreateSourceType.docker, 'dockerimage-text',
                  'dockerimage-desc'),
              const MenuFlyoutSeparator(),
              _sourceTypeItem(CreateSourceType.local, 'localrootfsfile-text',
                  'localrootfsfile-desc'),
              _sourceTypeItem(CreateSourceType.dockerLocalImage,
                  'localdockerimage-text', 'localdockerimage-desc'),
              _sourceTypeItem(
                  CreateSourceType.vhdx, 'importvhdx-text', 'importvhdx-desc'),
            ],
          ),
        ),
        Container(
          height: 10.0,
        ),
        MergeSemantics(
          child: Tooltip(
            message: 'pathtorootfshint-text'.i18n(),
            child: FutureBuilder<List<String>>(future: () async {
              if (sourceType == CreateSourceType.repo) {
                var map = await App().getDistroLinks();
                return map.keys.toList();
              } else if (sourceType == CreateSourceType.turnkey) {
                var repo = await App().getDistroLinks();
                var all = await widget.api.getDownloadable(
                    (prefs.getString('RepoLink') ?? defaultRepoLink),
                    (e) => Notify.message(e));
                return all.where((x) => !repo.containsKey(x)).toList();
              } else if (sourceType == CreateSourceType.dockerLocalImage) {
                try {
                  return await DockerImage.listLocalImages();
                } catch (_) {
                  return <String>[];
                }
              }
              return <String>[];
            }(), builder: (context, snapshot) {
              List<AutoSuggestBoxItem<String>> list = [];
              if (snapshot.hasData) {
                for (var i = 0; i < snapshot.data!.length; i++) {
                  list.add(AutoSuggestBoxItem<String>(
                    value: snapshot.data![i],
                    label: snapshot.data![i],
                  ));
                }
              } else if (snapshot.hasError) {}
              return AutoSuggestBox(
                key: _autoSuggestBoxKey,
                focusNode: node,
                placeholder: sourceType == CreateSourceType.docker
                    ? 'dockerimageplaceholder-text'.i18n()
                    : sourceType == CreateSourceType.dockerLocalImage
                        ? 'localdockerimageplaceholder-text'.i18n()
                        : sourceType == CreateSourceType.local
                        ? 'pathtorootfsarchive-text'.i18n()
                        : sourceType == CreateSourceType.vhdx
                            ? 'pathtovhdxfile-text'.i18n()
                            : 'distroname-text'.i18n(),
                controller: widget.autoSuggestBox,
                items: list,
                noResultsFoundBuilder: (context) => Builder(builder: (context) {
                  String text = 'noresultsfound-text'.i18n();
                  if (sourceType == CreateSourceType.docker) {
                    text = widget.autoSuggestBox.text;
                    if (text.startsWith('dockerhub:')) {
                      text = text.split('dockerhub:')[1];
                    } else if (text.startsWith('docker:')) {
                      text = text.split('docker:')[1];
                    }
                    String image = text;
                    String tag = 'latest';
                    bool error = false;
                    try {
                      if (text.contains(':')) {
                        image = text.split(':')[0];
                        tag = text.split(':')[1];
                      }
                    } catch (e) {
                      // Keyed: these three were the only hardcoded English
                      // strings in the panel (audit CI-10).
                      text = 'dockerimagecheck-text'.i18n();
                      error = true;
                    }
                    if (!error) {
                      text = 'dockerimagepreview-text'.i18n(['$image:$tag']);
                    }
                  } else if (sourceType == CreateSourceType.dockerLocalImage) {
                    text = widget.autoSuggestBox.text.isEmpty
                        ? 'localdockerimagenotfound-text'.i18n()
                        : 'localdockerpreview-text'
                            .i18n([widget.autoSuggestBox.text]);
                  } else if (sourceType == CreateSourceType.local) {
                    text = 'selectlocalfile-text'.i18n();
                  } else if (sourceType == CreateSourceType.vhdx) {
                    text = 'selectvhdxfile-text'.i18n();
                  } else {
                    text = 'noresultsfound-text'.i18n();
                  }
                  return Container(
                    padding: const EdgeInsets.all(10.0),
                    child: Text(text),
                  );
                }),
                onChanged: (String value, TextChangedReason reason) {
                  if (value.startsWith('dockerhub:') ||
                      value.startsWith('docker:')) {
                    widget.sourceType.value = CreateSourceType.docker;
                  }
                },
                trailingIcon: sourceType == CreateSourceType.local ||
                        sourceType == CreateSourceType.vhdx
                    ? NamedIconButton(
                        label: 'choosefile-text'.i18n(),
                        icon: FluentIcons.open_folder_horizontal,
                        onPressed: () async {
                          FilePickerResult? result =
                              await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: sourceType == CreateSourceType.vhdx
                                ? ['vhdx']
                                : ['*'],
                          );
  
                          if (result != null) {
                            widget.autoSuggestBox.text =
                                result.files.single.path!;
                          } else {
                            // User canceled the picker
                          }
                        },
                      )
                    : null,
              );
            }),
          ),
        ),
        Container(
          height: 10.0,
        ),
        ToggleSwitch(
          checked: customLocation,
          content: Text('savelocationhint-text'.i18n()),
          onChanged: (v) {
            setState(() {
              customLocation = v;
              if (!v) widget.locationController.clear();
            });
          },
        ),
        if (customLocation) ...[
          Container(
            height: 10.0,
          ),
          MergeSemantics(
            child: Tooltip(
              message: 'savelocationhint-text'.i18n(),
              child: TextBox(
                key: const ValueKey('test-create-location-input'),
                controller: widget.locationController,
                placeholder: 'savelocationplaceholder-text'.i18n(),
                suffix: IconButton(
                  icon:
                      const Icon(FluentIcons.open_folder_horizontal, size: 15.0),
                  onPressed: () async {
                    String? path = await FilePicker.platform.getDirectoryPath();
                    if (path != null) {
                      widget.locationController.text = path;
                    } else {
                      // User canceled the picker
                    }
                  },
                ),
              ),
            ),
          ),
        ],
        Container(
          height: 10.0,
        ),
        // An InfoBar with one sentence. The old form was five italic lines
        // naming `fake_systemd` and an `ip a | grep inet` pipeline — a
        // changelog entry, a troubleshooting note and a shell tutorial in one
        // string (audit CI-27).
        sourceType == CreateSourceType.turnkey
            ? InfoBar(
                title: Text('turnkeywarningtitle-text'.i18n()),
                content: Text('turnkeywarning-text'.i18n()),
                severity: InfoBarSeverity.warning,
                isLong: true,
              )
            : Container(),
        supportsDefaultUser(sourceType)
            ? ToggleSwitch(
                checked: createUser,
                content: Text('createuser-text'.i18n()),
                onChanged: (v) {
                  setState(() {
                    createUser = v;
                    if (!v) widget.userController.clear();
                  });
                  widget.createUserEnabled?.value = v;
                },
              )
            : Container(),
        supportsDefaultUser(sourceType) && createUser
            ? Column(
                children: [
                  Container(
                    height: 10.0,
                  ),
                  Tooltip(
                    message: 'optionalusername-text'.i18n(),
                    child: TextBox(
                      controller: widget.userController,
                      placeholder: 'optionaluser-text'.i18n(),
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  // The password step opens a console window outside the app
                  // and nothing said so, which is half of audit CI-13 — the
                  // other half is that the create no longer races past it.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'passwordwindowhint-text'.i18n(),
                      key: const ValueKey('test-create-password-hint'),
                      style: TextStyle(color: secondaryTextColor(context)),
                    ),
                  ),
                ],
              )
            : Container(),
      ],
    );
  }
}
