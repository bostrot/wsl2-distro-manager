import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/quick_actions.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/hoverable.dart';
import 'package:wsl2distromanager/components/theme.dart';

/// Community Quick Actions List
class QaList extends StatefulWidget {
  const QaList({Key? key}) : super(key: key);

  @override
  State<QaList> createState() => QaListState();
}

class QaListState extends State<QaList> {
  String? filter;
  List<QuickActionItem> selectedList = [];
  static List<QuickActionItem> items = [];

  /// Toggle selected item
  void toggleItem(QuickActionItem item) {
    if (selectedList.contains(item)) {
      selectedList.remove(item);
    } else {
      selectedList.add(item);
    }
    setState(() {});
  }

  /// Download the current selection
  Future download() async {
    if (kDebugMode) {
      print("downloading...");
    }

    // Load data from git repo
    try {
      for (var i = 0; i < selectedList.length; i++) {
        String name = selectedList[i].name;
        // Get Script
        Response<dynamic> contentFile =
            await Dio().get('$repoScripts/$name/script.noshell');
        QuickActionItem item = selectedList[i];
        item.content = contentFile.data.toString();
        QuickAction.addToPrefs(item);
      }
    } catch (err) {
      // Do nothing
      if (kDebugMode) {
        print(err);
      }
    }
  }

  /// Get the list of scripts from the repo
  Future<List<QuickActionItem?>> _getQuickActionsFromRepo() async {
    // Use cache
    if (items.isNotEmpty) {
      return items;
    }
    // Load data from git repo
    try {
      Response<dynamic> repo = await Dio().get(gitApiScriptsLink);
      List<dynamic> repoData = repo.data;
      for (var i = 0; i < repoData.length; i++) {
        String name = repoData[i]["name"];
        // Get script metadata
        Response<dynamic> infoFileResponse =
            await Dio().get('$repoScripts/$name/info.yml');
        // Save metadata to list
        items.add(
            QuickActionItem.fromYamlString(infoFileResponse.data.toString()));
      }
    } catch (err) {
      // Do nothing
      throw Exception(err);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextBox(
            placeholder: 'search-text'.i18n(),
            onChanged: (value) {
              setState(() {
                filter = value;
              });
            },
          ),
        ),
        Expanded(child: listView(filter: filter))
      ],
    );
  }

  FutureBuilder<List<QuickActionItem?>> listView({String? filter}) {
    return FutureBuilder(
        future: _getQuickActionsFromRepo(),
        builder: (BuildContext context,
            AsyncSnapshot<List<QuickActionItem?>> snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (BuildContext context, int index) {
                  if (snapshot.data![index] == null ||
                      (filter != null &&
                          filter.isNotEmpty &&
                          (!snapshot.data![index]!.name
                                  .toLowerCase()
                                  .contains(filter.toLowerCase()) &&
                              !snapshot.data![index]!.description
                                  .toLowerCase()
                                  .contains(filter.toLowerCase())))) {
                    return Container();
                  }
                  var data = snapshot.data![index]!;
                  return Hoverable(
                    child: ListTile(
                      tileColor: ButtonState.all(selectedList.contains(data)
                          ? themeData.inactiveBackgroundColor.withOpacity(0.5)
                          : Colors.transparent),
                      title: Text(data.name),
                      subtitle: Text(data.description),
                      onPressed: () => toggleItem(data),
                    ),
                  );
                });
          } else if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: ProgressRing());
          } else {
            return Center(child: Text('errordownloading-text'.i18n()));
          }
        });
  }
}
