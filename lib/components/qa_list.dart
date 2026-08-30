import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/quick_actions.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/error_view.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/hoverable.dart';
import 'package:wsl2distromanager/theme.dart';

/// What a download attempt did, so the dialog can tell success from failure.
///
/// `download()` used to swallow its own error and return normally, so the
/// dialog popped and ran the success callback on a failed download exactly as
/// it did on a good one (audit CI-36).
class QaDownloadResult {
  const QaDownloadResult({required this.downloaded, this.error});

  /// How many snippets were written to prefs.
  final int downloaded;

  /// The failure, or null when every selected snippet was written.
  final Object? error;

  bool get failed => error != null;
}

/// Community Quick Actions List
class QaList extends StatefulWidget {
  const QaList({Key? key, Dio? dio})
      : _dio = dio,
        super(key: key);

  /// Injected in tests; the app builds its own.
  final Dio? _dio;

  @override
  State<QaList> createState() => QaListState();
}

class QaListState extends State<QaList> {
  String? filter;
  List<QuickActionItem> selectedList = [];
  static List<QuickActionItem> items = [];

  late Dio _dio;

  /// Held in state rather than rebuilt in `build()`: a `FutureBuilder` fed a
  /// fresh future on every keystroke in the search box re-ran the whole fetch
  /// each time the list had failed to load.
  late Future<List<QuickActionItem?>> _future;

  /// What the failed load wrote, shown under "Technical details".
  String _loadError = '';

  @override
  void initState() {
    super.initState();
    _dio = widget._dio ?? Dio();
    _future = _getQuickActionsFromRepo();
  }

  /// Drop the process-lifetime cache and fetch again.
  ///
  /// `items` is static and was never invalidated, so before this the list
  /// could not be reloaded without restarting the app (audit CI-36).
  void retryLoad() {
    items = [];
    setState(() {
      _loadError = '';
      _future = _getQuickActionsFromRepo();
    });
  }

  /// Toggle selected item
  void toggleItem(QuickActionItem item) {
    if (selectedList.contains(item)) {
      selectedList.remove(item);
    } else {
      selectedList.add(item);
    }
    setState(() {});
  }

  /// Download the current selection.
  ///
  /// Reports how far it got through [onProgress] and hands the failure back to
  /// the caller instead of posting a toast and returning as if it had worked.
  Future<QaDownloadResult> download({
    void Function(int done, int total)? onProgress,
  }) async {
    final total = selectedList.length;
    var done = 0;
    onProgress?.call(done, total);

    // Load data from git repo
    try {
      for (var i = 0; i < selectedList.length; i++) {
        String name = selectedList[i].name;
        // Get Script
        Response<dynamic> contentFile =
            await _dio.get("$repoScripts/$name/script.noshell");
        QuickActionItem item = selectedList[i];
        item.content = contentFile.data.toString();
        QuickAction.addToPrefs(item);
        done++;
        onProgress?.call(done, total);
      }
    } catch (err) {
      return QaDownloadResult(downloaded: done, error: err);
    }
    return QaDownloadResult(downloaded: done);
  }

  /// Get the list of scripts from the repo
  Future<List<QuickActionItem?>> _getQuickActionsFromRepo() async {
    // Use cache
    if (items.isNotEmpty) {
      return items;
    }
    // Load data from git repo
    try {
      Response<dynamic> repo = await _dio.get(gitApiScriptsLink);
      List<dynamic> repoData = repo.data;
      for (var i = 0; i < repoData.length; i++) {
        String name = repoData[i]["name"];
        // Get script metadata
        Response<dynamic> infoFileResponse =
            await _dio.get('$repoScripts/$name/info.yml');
        // Save metadata to list
        items.add(
            QuickActionItem.fromYamlString(infoFileResponse.data.toString()));
      }
    } catch (err) {
      // A half-filled cache would be served as the whole catalogue on the
      // next build.
      items = [];
      _loadError = err.toString();
      rethrow;
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
        future: _future,
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
                          ? AppTheme().color.withValues(alpha: 0.5)
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
            // Three words and no way out was the whole failure state before:
            // no reason, no mention that this needs a network, no retry.
            return Center(
              key: const ValueKey('test-qa-load-error'),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'snippetsloadfailed-text'.i18n(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondaryTextColor(context)),
                    ),
                    const SizedBox(height: 10.0),
                    Button(
                      key: const ValueKey('test-qa-retry'),
                      onPressed: retryLoad,
                      child: Text('retry-text'.i18n()),
                    ),
                    if (_loadError.isNotEmpty) ...[
                      const SizedBox(height: 8.0),
                      ErrorDetails(details: _loadError),
                    ],
                  ],
                ),
              ),
            );
          }
        });
  }
}
