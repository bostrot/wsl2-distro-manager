import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Rename Dialog
/// @param context: context
/// @param api: WSLApi
/// @param statusMsg: Function(String, {bool loading})
createDialog(context, Function(String, {bool loading}) statusMsg) {
  WSLApi api = WSLApi();
  final autoSuggestBox = TextEditingController();
  final locationController = TextEditingController();
  final nameController = TextEditingController();
  plausible.event(page: 'create');

  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: const Text('Create a new distro'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10.0,
            ),
            Tooltip(
              message: 'The name of your new WSL instance',
              child: TextBox(
                controller: nameController,
                placeholder: 'Name',
                suffix: IconButton(
                  icon: const Icon(FluentIcons.close, size: 15.0),
                  onPressed: () {
                    nameController.clear();
                  },
                ),
              ),
            ),
            Container(
              height: 10.0,
            ),
            Tooltip(
              message:
                  'Either use one of the pre-defined Distros or a file path to a rootfs',
              child: FutureBuilder<List<String>>(
                  future: api.getDownloadable(),
                  builder: (context, snapshot) {
                    List<String> list = [];
                    if (snapshot.hasData) {
                      list = snapshot.data ?? [];
                    } else if (snapshot.hasError) {}
                    return AutoSuggestBox<String>(
                      controller: autoSuggestBox,
                      items: list,
                      textBoxBuilder: (context, controller, focusNode, key) {
                        return TextBox(
                          key: key,
                          controller: controller,
                          focusNode: focusNode,
                          suffix: IconButton(
                            icon: const Icon(FluentIcons.open_folder_horizontal,
                                size: 15.0),
                            onPressed: () async {
                              FilePickerResult? result =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['*'],
                              );

                              if (result != null) {
                                controller.text = result.files.single.path!;
                              } else {
                                // User canceled the picker
                              }
                            },
                          ),
                          placeholder: 'Distro',
                        );
                      },
                    );
                  }),
            ),
            Container(
              height: 10.0,
            ),
            Tooltip(
              message: '(Optional) Path where to save the new instance',
              child: TextBox(
                controller: locationController,
                placeholder: 'Save location',
                suffix: IconButton(
                  icon: const Icon(FluentIcons.open_folder_horizontal,
                      size: 15.0),
                  onPressed: () async {
                    String? path = await FilePicker.platform.getDirectoryPath();
                    if (path != null) {
                      locationController.text = path;
                    } else {
                      // User canceled the picker
                    }
                  },
                ),
              ),
            ),
            Container(
              height: 10.0,
            ),
            Container(
              height: 10.0,
            ),
          ],
        ),
        actions: [
          Button(
              child: const Text('Cancel'),
              onPressed: () async {
                Navigator.pop(context);
              }),
          Button(
            onPressed: () async {
              plausible.event(name: "wsl_create");
              if (nameController.text != '') {
                statusMsg('Creating instance. This might take a while...',
                    loading: true);
                var result = await api.create(nameController.text,
                    autoSuggestBox.text, locationController.text);
                if (result.exitCode != 0) {
                  statusMsg(result.stdout);
                } else {
                  Navigator.pop(context);
                  statusMsg('DONE: creating instance');
                }
                // Download distro check
              } else {
                statusMsg('Please type in a name.');
              }
            },
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
}
