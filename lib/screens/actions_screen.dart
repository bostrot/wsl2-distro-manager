import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:re_editor/re_editor.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:wsl2distromanager/dialogs/qa_dialog.dart';
import 'package:wsl2distromanager/theme.dart';
import 'package:wsl2distromanager/api/quick_actions.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

class QuickPage extends StatefulWidget {
  const QuickPage({Key? key}) : super(key: key);

  @override
  QuickPageState createState() => QuickPageState();
}

class QuickPageState extends State<QuickPage> {
  List<Widget> quickSettings = [];
  String lineNumbers = '';
  bool showInput = false;
  var scrollController = ScrollController();
  var nameController = TextEditingController();
  var contentController = CodeLineEditingController();
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
          !showInput ? communityActionsBtn() : Container(),
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
                    ? Editor(
                        contentController: contentController,
                        scrollController: scrollController,
                        lineNumbers: lineNumbers,
                        lineNum: lineNum)
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
        ],
      ),
    );
  }

  Padding communityActionsBtn() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        children: [
          !showInput
              ? Button(
                  style: ButtonStyle(
                      padding: ButtonState.all<EdgeInsets>(
                          const EdgeInsets.only(
                              top: 8.0, bottom: 8.0, left: 20.0, right: 20.0))),
                  onPressed: () {
                    // Open qa_dialog
                    communityDialog(() => setState(
                          () {},
                        ));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.cloud_download),
                      const SizedBox(
                        width: 10.0,
                      ),
                      Text('addcommunityactions-text'.i18n()),
                    ],
                  ),
                )
              : Container(),
          Flexible(
              child: SingleChildScrollView(child: quickSettingsListBuilder())),
        ],
      ),
    );
  }

  Row bottomButtonRow() {
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
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
        List<QuickActionItem> quickActions = QuickAction().getFromPrefs();
        quickSettings = [];
        for (int i = 0; i < quickActions.length; i++) {
          if (opened[i] == null) {
            opened[i] = false;
          }
          final version = quickActions[i].version.isNotEmpty
              ? quickActions[i].version
              : '0.0.0';
          final author = quickActions[i].author.isNotEmpty
              ? quickActions[i].author
              : 'you';
          quickSettings.add(Padding(
            padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 8.0),
            child: Column(
              children: [
                Expander(
                    initiallyExpanded: false,
                    header: RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: quickActions[i].name,
                          style: TextStyle(
                            color: AppTheme().textColor,
                          ),
                        ),
                        TextSpan(
                          text: ' [v$version] ',
                          style: TextStyle(
                            color: AppTheme().textColor.withOpacity(0.5),
                          ),
                        ),
                        TextSpan(
                          text: '(by $author)',
                          style: TextStyle(
                            fontSize: 13.0,
                            color: AppTheme().color,
                          ),
                        ),
                      ]),
                    ),
                    trailing: Row(
                      children: [
                        IconButton(
                          icon: const Icon(FluentIcons.edit),
                          onPressed: () {
                            setState(() {
                              showInput = true;
                              nameController.text = quickActions[i].name;
                              contentController.text = quickActions[i].content;
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(FluentIcons.delete),
                          onPressed: () {
                            // Open remove dialog
                            dialog(
                                item: quickActions[i],
                                title: 'deleteinstancequestion-text'
                                    .i18n([quickActions[i].name]),
                                body: 'deleteinstancebody-text'.i18n(),
                                submitText: 'delete-text'.i18n(),
                                submitInput: false,
                                submitStyle: ButtonStyle(
                                  backgroundColor: ButtonState.all(Colors.red),
                                  foregroundColor:
                                      ButtonState.all(Colors.white),
                                ),
                                onSubmit: (inputText) {
                                  QuickAction.removeFromPrefs(quickActions[i]);
                                  setState(() {});
                                });
                          },
                        ),
                      ],
                    ),
                    content: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: SingleChildScrollView(
                        child: Opacity(
                          opacity: 0.7,
                          child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    left: 20.0, right: 20.0, bottom: 4.0),
                                child: SelectableText(quickActions[i].content),
                              )),
                        ),
                      ),
                    )),
              ],
            ),
          ));
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

class Editor extends StatelessWidget {
  const Editor({
    Key? key,
    required this.contentController,
    required this.scrollController,
    required this.lineNumbers,
    required this.lineNum,
  }) : super(key: key);

  final CodeLineEditingController contentController;
  final ScrollController scrollController;
  final String lineNumbers;
  final int lineNum;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: MediaQuery.of(context).size.height * 0.68,
        width: MediaQuery.of(context).size.width * 0.9,
        child: CodeEditor(
            hint: '# ${'yourcodehere-text'.i18n()}',
            indicatorBuilder:
                (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                  DefaultCodeChunkIndicator(
                      width: 20,
                      controller: chunkController,
                      notifier: notifier)
                ],
              );
            },
            style: CodeEditorStyle(
              codeTheme: CodeHighlightTheme(
                  languages: {'bash': CodeHighlightThemeMode(mode: langBash)},
                  theme: atomOneLightTheme),
            ),
            controller: contentController));
  }
}
