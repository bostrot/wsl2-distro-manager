import 'analytics.dart';
import 'api.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';

Widget createComponent(WSLApi api, Function(String, {bool loading}) statusMsg) {
  final autoSuggestBox = TextEditingController();
  final locationController = TextEditingController();
  final nameController = TextEditingController();

  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
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
    ],
  );
}
