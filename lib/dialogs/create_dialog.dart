import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';

/// Rename Dialog
/// @param context: context
/// @param api: WSLApi
/// @param statusMsg: Function(String, {bool loading})
createDialog(context, api, Function(String, {bool loading}) statusMsg) {
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
              List<String> downloadable = await api.getDownloadable();

              if (nameController.text != '') {
                if (downloadable.contains(autoSuggestBox.text)) {
                  // Get distro from internet
                  // Install distro
                  statusMsg(
                      'Downloading ${autoSuggestBox.text}. This might take a while...',
                      loading: true);
                  await api.install(autoSuggestBox.text);
                  // Copy installed to name
                  statusMsg(
                      'Creating ${nameController.text}. This might take a while...',
                      loading: true);
                  await api.copy(autoSuggestBox.text, nameController.text,
                      location: locationController.text);
                  statusMsg('DONE: Created ${nameController.text}.');
                } else {
                  // Get distro from local storage
                  // Copy local storage to name
                  statusMsg(
                      'Creating ${nameController.text}. This might take a while...',
                      loading: true);
                  await api.import(
                    nameController.text,
                    locationController.text,
                    autoSuggestBox.text,
                  );
                  statusMsg('DONE: Created ${nameController.text}.');
                }
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

Widget createComponent(WSLApi api, Function(String, {bool loading}) statusMsg) {
  final autoSuggestBox = TextEditingController();
  final locationController = TextEditingController();
  final nameController = TextEditingController();

  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      Container(
        width: 10.0,
      ),
      Expanded(
          child: Tooltip(
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
      )),
      Container(
        width: 10.0,
      ),
      Expanded(
          child: Tooltip(
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
      )),
      Container(
        width: 10.0,
      ),
      Expanded(
        child: Tooltip(
          message: '(Optional) Path where to save the new instance',
          child: TextBox(
            controller: locationController,
            placeholder: 'Save location',
            suffix: IconButton(
              icon: const Icon(FluentIcons.open_folder_horizontal, size: 15.0),
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
      ),
      Container(
        width: 10.0,
      ),
      Button(
        onPressed: () async {
          plausible.event(name: "wsl_create");
          List<String> downloadable = await api.getDownloadable();

          if (nameController.text != '') {
            if (downloadable.contains(autoSuggestBox.text)) {
              // Get distro from internet
              // Install distro
              statusMsg(
                  'Downloading ${autoSuggestBox.text}. This might take a while...',
                  loading: true);
              await api.install(autoSuggestBox.text);
              // Copy installed to name
              statusMsg(
                  'Creating ${nameController.text}. This might take a while...',
                  loading: true);
              await api.copy(autoSuggestBox.text, nameController.text,
                  location: locationController.text);
              statusMsg('DONE: Created ${nameController.text}.');
            } else {
              // Get distro from local storage
              // Copy local storage to name
              statusMsg(
                  'Creating ${nameController.text}. This might take a while...',
                  loading: true);
              await api.import(
                nameController.text,
                locationController.text,
                autoSuggestBox.text,
              );
              statusMsg('DONE: Created ${nameController.text}.');
            }
          } else {
            statusMsg('Please type in a name.');
          }
        },
        child: const Padding(
          padding: EdgeInsets.all(6.0),
          child: Text('Create'),
        ),
      ),
      Container(
        width: 10.0,
      ),
    ],
  );
}
