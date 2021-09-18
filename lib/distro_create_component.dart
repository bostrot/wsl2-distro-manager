import 'api.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';

Widget createComponent(WSLApi api, statusMsg(msg)) {
  final autoSuggestBox = TextEditingController();
  final locationController = TextEditingController();
  final nameController = TextEditingController();
  final items = ['Debian', 'Ubuntu'];
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      Expanded(
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
      Expanded(
          child: FutureBuilder<List<String>>(
              future: api.getDownloadable(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  List<String> list = snapshot.data ?? [];
                  return AutoSuggestBox<String>(
                    controller: autoSuggestBox,
                    items: list,
                    onSelected: (text) {
                      print(text);
                    },
                    textBoxBuilder: (context, controller, focusNode, key) {
                      return TextBox(
                        key: key,
                        controller: controller,
                        focusNode: focusNode,
                        suffix: Row(children: [
                          IconButton(
                            icon: const Icon(FluentIcons.close, size: 15.0),
                            onPressed: () {
                              controller.clear();
                              focusNode.unfocus();
                            },
                          ),
                          IconButton(
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
                        ]),
                        placeholder: 'Distro',
                      );
                    },
                  );
                } else if (snapshot.hasError) {
                  return Text('${snapshot.error}');
                }
                // By default, show a loading spinner.
                return const Center(child: ProgressRing());
              })),
      Expanded(
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
      Button(
        onPressed: () async {
          List<String> downloadable = await api.getDownloadable();
          if (downloadable.contains(autoSuggestBox.text)) {
            // Get distro from internet
            // Install distro
            statusMsg(
                'Downloading ${autoSuggestBox.text}. This might take a while...');
            await api.install(autoSuggestBox.text);
            // Copy installed to name
            statusMsg(
                'Creating ${nameController.text}. This might take a while...');
            await api.copy(autoSuggestBox.text, nameController.text,
                location: locationController.text);
            statusMsg('DONE: Created ${nameController.text}.');
          } else {
            // Get distro from local storage
            // Copy local storage to name
            statusMsg(
                'Creating ${nameController.text}. This might take a while...');
            await api.import(
              nameController.text,
              locationController.text,
              autoSuggestBox.text,
            );
            statusMsg('DONE: Created ${nameController.text}.');
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
