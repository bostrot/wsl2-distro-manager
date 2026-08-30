import 'package:dio/dio.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/busy_button.dart';
import 'package:wsl2distromanager/components/error_view.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/components/qa_list.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';

/// Community Dialog
/// @param api: WSLApi
void communityDialog(Function callback, {Dio? dio}) {
  // Get root context by Key
  final context = GlobalVariable.infobox.currentContext!;

  plausible.event(page: 'open_community_dialog');
  showDialog(
    context: context,
    builder: (BuildContext context) =>
        CommunityDialog(callback: callback, dio: dio),
  );
}

/// The community snippet browser.
///
/// Stateful because the download is a multi-request operation the dialog has
/// to survive: it shows how far it has got, and a failure keeps the dialog
/// open with the reason on it instead of closing as if it had worked
/// (audit CI-36).
class CommunityDialog extends StatefulWidget {
  const CommunityDialog({super.key, required this.callback, this.dio});

  final Function callback;

  /// Injected in tests; the list builds its own.
  final Dio? dio;

  @override
  State<CommunityDialog> createState() => _CommunityDialogState();
}

class _CommunityDialogState extends State<CommunityDialog> {
  final GlobalKey<QaListState> _qaKey = GlobalKey<QaListState>();

  bool _downloading = false;
  int _done = 0;
  int _total = 0;

  /// Set when nothing is selected — a primary button may not silently no-op.
  String? _validation;

  /// What the failed download wrote.
  String? _error;

  Future<void> _download() async {
    final list = _qaKey.currentState;
    if (list == null || _downloading) return;

    if (list.selectedList.isEmpty) {
      setState(() {
        _validation = 'snippetsselectone-text'.i18n();
        _error = null;
      });
      return;
    }

    setState(() {
      _validation = null;
      _error = null;
      _downloading = true;
      _done = 0;
      _total = list.selectedList.length;
    });

    final result = await list.download(onProgress: (done, total) {
      if (!mounted) return;
      setState(() {
        _done = done;
        _total = total;
      });
    });

    if (!mounted) return;

    if (result.failed) {
      setState(() {
        _downloading = false;
        _error = result.error.toString();
      });
      return;
    }

    setState(() => _downloading = false);
    // There was no confirmation of any kind before: the dialog closed and the
    // user was left to notice a new row.
    Notify.message('snippetsdownloaded-text'.i18n(),
        severity: InfoBarSeverity.success);
    Navigator.pop(context);
    widget.callback();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      // The dialog used to open as an untitled modal — a search box, a list
      // and two buttons with nothing saying what it is or where the content
      // comes from (audit CI-33).
      title: Text('communitysnippetstitle-text'.i18n()),
      // Sized to its content instead of `MediaQuery...size.height`, which made
      // the modal as tall as the window with ~300px of dead space (CI-37).
      content: SizedBox(
        height: 420.0,
        child: Column(
          children: [
            Expanded(
              child: QaList(
                key: _qaKey,
                dio: widget.dio,
              ),
            ),
            if (_validation != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _validation!,
                  key: const ValueKey('test-qa-validation'),
                  style: TextStyle(color: Colors.red, fontSize: 12.0),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    key: const ValueKey('test-qa-download-error'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'snippetdownloadfailed-text'.i18n(),
                        style: TextStyle(color: Colors.red, fontSize: 12.0),
                      ),
                      ErrorDetails(details: _error!),
                    ],
                  ),
                ),
              ),
            if (_downloading)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const SizedBox.square(
                        dimension: 14, child: ProgressRing(strokeWidth: 2.0)),
                    const SizedBox(width: 8.0),
                    Text(
                      'downloadingsnippets-text'.i18n(
                          ['${_done < _total ? _done + 1 : _total}', '$_total']),
                      key: const ValueKey('test-qa-download-progress'),
                      style: TextStyle(
                          fontSize: 12.0, color: secondaryTextColor(context)),
                    ),
                  ],
                ),
              ),
            ClickableUrl(
              clickEvent: "community_actions_url_clicked",
              url: 'https://github.com/bostrot/wsl-scripts#contribute',
              text: 'shareyourquickaction-text'.i18n(),
            ),
          ],
        ),
      ),
      // Primary first, Cancel last: this was the one dialog in the app with
      // the order reversed, so the slot that means "cancel" everywhere else
      // meant "commit" here (audit CI-32).
      actions: [
        BusyButton(
          key: const ValueKey('test-qa-download'),
          filled: true,
          label: 'download-text'.i18n(),
          busyLabel: 'downloading-text'.i18n(),
          busy: _downloading,
          onPressed: _downloading ? null : _download,
        ),
        Button(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: Text('cancel-text'.i18n()),
        ),
      ],
    );
  }
}
