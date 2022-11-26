import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/theme.dart';

class QuickPage extends StatefulWidget {
  const QuickPage({Key? key}) : super(key: key);

  @override
  QuickPageState createState() => QuickPageState();
}

class QuickPageState extends State<QuickPage> {
  List<Widget> quickSettings = [];
  String lineNumbers = '';
  bool showInput = false;
  ScrollController scrollController = ScrollController();
  TextEditingController nameController = TextEditingController();
  TextEditingController contentController = TextEditingController();
  int lineNum = 30;

  @override
  void initState() {
    super.initState();

    plausible.event(page: 'actions_screen');
    genLineNumbers(0);
    scrollController.addListener(() {
      lineNumbers = '';
      int offset = (scrollController.offset ~/ 12);
      genLineNumbers(offset);
    });
  }

  /*
  TextSelection selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  List<TextBox> boxes = textPainter.getBoxesForSelection(selection);
  int numberOfLines = boxes.length;
   */

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
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        children: [
          !showInput
              ? SingleChildScrollView(child: quickSettingsListBuilder())
              : Container(),
          Positioned(
            left: 20.0,
            right: 20.0,
            bottom: 10.0,
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
                // TODO: Better line numbers
                showInput
                    ? SizedBox(
                        height: MediaQuery.of(context).size.height * 0.72,
                        width: MediaQuery.of(context).size.width * 0.9,
                        child: TextBox(
                          controller: contentController,
                          scrollController: scrollController,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 12.0,
                          ),
                          prefix: Padding(
                            padding: const EdgeInsets.only(left: 8.0, top: 3.0),
                            child: Text(
                              lineNumbers,
                              style: TextStyle(
                                color: AppTheme().color.normal,
                                fontFamily: 'Consolas',
                                fontSize: 12.0,
                              ),
                            ),
                          ),
                          minLines: lineNum,
                          maxLines: lineNum,
                          placeholder: '# ${'yourcodehere-text'.i18n()}',
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
          //TODO: navbar(widget.themeData, back: true, context: context),
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
            ? Container()
            : Button(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/');
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.chrome_back),
                    const SizedBox(
                      width: 10.0,
                    ),
                    Text('back-text'.i18n()),
                  ],
                ),
              ),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            showInput
                ? Button(
                    style: ButtonStyle(
                        padding: ButtonState.all<EdgeInsets>(
                            const EdgeInsets.only(
                                top: 8.0,
                                bottom: 8.0,
                                left: 20.0,
                                right: 20.0))),
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
            const SizedBox(
              width: 10.0,
            ),
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
                  List<String>? titles =
                      prefs.getStringList('quickSettingsTitles');
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
                  Expander(
                      initiallyExpanded: false,
                      header: Text(quickSettingsTitles[i]),
                      // subtitle: Text(quickSettingsContents[i]),
                      trailing: Row(
                        children: [
                          IconButton(
                            icon: const Icon(FluentIcons.edit),
                            onPressed: () {
                              setState(() {
                                showInput = true;
                                nameController.text = quickSettingsTitles[i];
                                contentController.text =
                                    quickSettingsContents[i];
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
                              prefs.setStringList('quickSettingsContents',
                                  quickSettingsContents);
                              setState(() {
                                quickSettings = quickSettings;
                              });
                            },
                          ),
                        ],
                      ),
                      content: Opacity(
                        opacity: 0.7,
                        child: SizedBox(
                            width: MediaQuery.of(context).size.width,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  left: 20.0, right: 20.0, bottom: 4.0),
                              child: Text(quickSettingsContents[i]),
                            )),
                      )),
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
