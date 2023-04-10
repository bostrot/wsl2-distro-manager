import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:url_launcher/link.dart';

class LinkPaneItemAction extends PaneItem {
  LinkPaneItemAction({
    required super.icon,
    required this.link,
    required super.body,
    super.title,
  }) : super();

  final String link;

  @override
  Widget build(
    BuildContext context,
    bool selected,
    VoidCallback? onPressed, {
    PaneDisplayMode? displayMode,
    bool showTextOnTop = true,
    bool? autofocus,
    int? itemIndex,
  }) {
    return Link(
      uri: Uri.parse(link),
      builder: (context, followLink) => super.build(
        context,
        selected,
        followLink,
        displayMode: displayMode,
        showTextOnTop: showTextOnTop,
        itemIndex: itemIndex,
        autofocus: autofocus,
      ),
    );
  }
}
