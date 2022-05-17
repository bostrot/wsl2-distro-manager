import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/navbar.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/theme.dart';

class QuickPage extends StatefulWidget {
  const QuickPage({Key? key, required this.themeData}) : super(key: key);

  final ThemeData themeData;

  @override
  _QuickPageState createState() => _QuickPageState();
}

class _QuickPageState extends State<QuickPage> {
  List<Widget> quickSettings = [];
  String lineNumbers = '';
  bool showInput = false;
  ScrollController scrollController = ScrollController();
  TextEditingController nameController = TextEditingController();
  TextEditingController contentController = TextEditingController();
  int lineNum = 18;

  @override
  void initState() {
    super.initState();

    plausible.event(page: 'actions_screen');
    genLineNumbers(0);
    scrollController.addListener(() {
      lineNumbers = '';
      int offset = (scrollController.offset ~/ 10);
      genLineNumbers(offset);
    });
  }

  void genLineNumbers(int offset) {
    for (int i = 1 + offset; i < lineNum + offset + 1; i++) {
      lineNumbers += i.toString();
      if (i < lineNum + offset) {
        lineNumbers += '\n';
      }
    }
    setState(() {
      lineNumbers = lineNumbers;
    });
  }

  Map<int, bool> opened = {};

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      content: Stack(
        children: [
          !showInput
              ? Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: SingleChildScrollView(
                      child: Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: quickSettingsListBuilder(),
                  )),
                )
              : Container(),
          Positioned(
            right: 20.0,
            bottom: 20.0,
            child: Column(
              children: [
                showInput
                    ? SizedBox(
                        width: MediaQuery.of(context).size.width - 40.0,
                        height: 35.0,
                        child: TextBox(
                          controller: nameController,
                          placeholder: 'settingname-text'.i18n(),
                        ),
                      )
                    : Container(),
                showInput
                    ? const SizedBox(
                        height: 10.0,
                      )
                    : Container(),
                showInput
                    ? SizedBox(
                        width: MediaQuery.of(context).size.width - 40.0,
                        child: TextBox(
                          controller: contentController,
                          scrollController: scrollController,
                          prefix: Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              lineNumbers,
                              style: TextStyle(
                                  color:
                                      themeData.activeColor.withOpacity(0.5)),
                            ),
                          ),
                          minLines: lineNum,
                          maxLines: lineNum,
                          placeholder:
                              '#!/bin/bash\n\n# ${'yourcodehere-text'.i18n()}',
                        ),
                      )
                    : Container(),
                //const SizedBox(height: 10.0),
                SizedBox(
                  width: MediaQuery.of(context).size.width - 40.0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: bottomButtonRow(),
                  ),
                ),
              ],
            ),
          ),
          navbar(widget.themeData, back: true, context: context),
        ],
      ),
    );
  }

  Row bottomButtonRow() {
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        showInput
            ? Button(
                style: ButtonStyle(
                    padding: ButtonState.all<EdgeInsets>(const EdgeInsets.only(
                        top: 8.0, bottom: 8.0, left: 20.0, right: 20.0))),
                onPressed: () {
                  setState(() {
                    showInput = false;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.chrome_close),
                    const SizedBox(
                      width: 10.0,
                    ),
                    Text('close-text'.i18n()),
                  ],
                ),
              )
            : Container(),
        Button(
          style: ButtonStyle(
              padding: ButtonState.all<EdgeInsets>(const EdgeInsets.only(
                  top: 8.0, bottom: 8.0, left: 20.0, right: 20.0))),
          onPressed: () {
            if (!showInput) {
              setState(() {
                showInput = true;
              });
            } else if (nameController.text.isNotEmpty &&
                contentController.text.isNotEmpty) {
              plausible.event(page: 'add_action');

              // Load data
              List<String>? titles = prefs.getStringList('quickSettingsTitles');
              titles ??= [];
              List<String>? contents =
                  prefs.getStringList('quickSettingsContents');
              contents ??= [];

              // Override if already exists
              if (titles.contains(nameController.text)) {
                int pos = titles.indexOf(nameController.text);
                titles.removeAt(pos);
                contents.removeAt(pos);
              }

              // Add title to list
              titles.add(nameController.text);
              prefs.setStringList('quickSettingsTitles', titles);

              // Add content to list
              contents.add(contentController.text);
              prefs.setStringList('quickSettingsContents', contents);

              setState(() {
                showInput = false;
              });
            } else {
              // Error
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              showInput
                  ? Text('save-text'.i18n())
                  : Text('addquickaction-text'.i18n()),
              const SizedBox(
                width: 10.0,
              ),
              Icon(
                showInput ? FluentIcons.save : FluentIcons.settings_add,
                size: 15.0,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Builder quickSettingsListBuilder() {
    return Builder(
      builder: (context) {
        List<String>? quickSettingsTitles =
            prefs.getStringList('quickSettingsTitles');
        List<String>? quickSettingsContents =
            prefs.getStringList('quickSettingsContents');
        if (quickSettingsTitles != null && quickSettingsContents != null) {
          quickSettings = [];
          for (int i = 0; i < quickSettingsTitles.length; i++) {
            if (opened[i] == null) {
              opened[i] = false;
            }
            quickSettings.add(Padding(
              padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 8.0),
              child: Column(
                children: [
                  ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: opened[i] == false
                            ? BorderRadius.circular(8.0)
                            : const BorderRadius.only(
                                topLeft: Radius.circular(8.0),
                                topRight: Radius.circular(8.0))),
                    tileColor: themeData.activeColor.withOpacity(0.05),
                    leading: IconButton(
                      icon: opened[i] == false
                          ? const Icon(FluentIcons.chevron_down)
                          : const Icon(FluentIcons.chevron_up),
                      onPressed: () {
                        setState(() {
                          opened[i] = opened[i] == true ? false : true;
                        });
                      },
                    ),
                    title: Text(quickSettingsTitles[i]),
                    // subtitle: Text(quickSettingsContents[i]),
                    trailing: Row(
                      children: [
                        IconButton(
                          icon: const Icon(FluentIcons.edit),
                          onPressed: () {
                            setState(() {
                              showInput = true;
                              nameController.text = quickSettingsTitles[i];
                              contentController.text = quickSettingsContents[i];
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(FluentIcons.delete),
                          onPressed: () {
                            quickSettings.removeAt(i);
                            quickSettingsTitles.removeAt(i);
                            quickSettingsContents.removeAt(i);
                            prefs.setStringList(
                                'quickSettingsTitles', quickSettingsTitles);
                            prefs.setStringList(
                                'quickSettingsContents', quickSettingsContents);
                            setState(() {
                              quickSettings = quickSettings;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  opened[i] == true
                      ? Container(
                          decoration: BoxDecoration(
                              color: themeData.activeColor.withOpacity(0.05),
                              borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(8.0),
                                  bottomRight: Radius.circular(8.0))),
                          width: MediaQuery.of(context).size.width,
                          child: Padding(
                            padding: const EdgeInsets.only(
                                left: 20.0, right: 20.0, bottom: 4.0),
                            child: Text(quickSettingsContents[i],
                                style: TextStyle(
                                    color: themeData.activeColor
                                        .withOpacity(0.4))),
                          ))
                      : Container(),
                ],
              ),
            ));
          }
        }
        if (quickSettings.isNotEmpty) {
          return Column(children: quickSettings);
        } else {
          return Padding(
            padding:
                EdgeInsets.only(top: MediaQuery.of(context).size.height / 2.5),
            child: Center(
              child: Text('addquickactioninfo-text'.i18n()),
            ),
          );
        }
      },
    );
  }
}
