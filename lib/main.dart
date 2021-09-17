import 'package:desktop_window/desktop_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
//import 'package:flutter/material.dart';
import 'package:system_theme/system_theme.dart';
import 'package:file_picker/file_picker.dart';

import 'api.dart';
import 'distro_list_component.dart';

void main() {
  runApp(const MyApp());
  DesktopWindow.setWindowSize(const Size(650, 500));
  DesktopWindow.setMinWindowSize(const Size(650, 500));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        accentColor: SystemTheme.accentInstance.accent.toAccentColor(),
        brightness: Brightness.light, // or Brightness.dark
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final autoSuggestBox = TextEditingController();
  final locationController = TextEditingController();
  final items = ['Debian', 'Ubuntu'];
  String status = '';
  String? _extension;

  WSLApi api = new WSLApi();

  void statusMsg(msg) {
    setState(() {
      status = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(left: 12.0),
              child: Text(
                'New WSL2 instance:',
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                SizedBox(
                  width: 150,
                  child: TextBox(
                    placeholder: 'Name',
                    suffix: IconButton(
                      icon: const Icon(FluentIcons.close, size: 15.0),
                      onPressed: () {},
                    ),
                  ),
                ),
                SizedBox(
                    width: 150,
                    child: AutoSuggestBox<String>(
                      controller: autoSuggestBox,
                      items: items,
                      onSelected: (text) {
                        print(text);
                      },
                      textBoxBuilder: (context, controller, focusNode, key) {
                        return TextBox(
                          key: key,
                          controller: controller,
                          focusNode: focusNode,
                          suffix: IconButton(
                            icon: const Icon(FluentIcons.close, size: 15.0),
                            onPressed: () {
                              controller.clear();
                              focusNode.unfocus();
                            },
                          ),
                          placeholder: 'Distro',
                        );
                      },
                    )),
                SizedBox(
                  width: 150,
                  child: TextBox(
                    controller: locationController,
                    placeholder: 'Save location',
                    suffix: IconButton(
                      icon: const SizedBox(
                        child: Icon(FluentIcons.open_folder_horizontal,
                            size: 15.0),
                      ),
                      onPressed: () async {
                        FilePickerResult? result =
                            await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['*'],
                        );

                        if (result != null) {
                          locationController.text = result.files.single.path!;
                        } else {
                          // User canceled the picker
                        }
                      },
                    ),
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Button(
                      onPressed: () {},
                      child: const Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Text('Create'),
                      ),
                    )),
              ],
            ),
            Center(
              child: Builder(
                builder: (ctx) {
                  if (status != '') {
                    return Text(status);
                  } else {
                    return const Text('');
                  }
                },
              ),
            ),
            distroList(api, statusMsg),
          ],
        ),
      ),
    );
  }
}
