import 'package:fluent_ui/fluent_ui.dart';
import 'package:bitsdojo_window_flutter3/bitsdojo_window.dart';
import 'package:wsl2distromanager/components/constants.dart';

Widget navbar(ThemeData themeData, {bool back = false, context}) {
  return Padding(
    padding:
        const EdgeInsets.only(top: 4.0, left: 4.0, right: 4.0, bottom: 15.0),
    child: WindowTitleBarBox(
      child: Row(
        children: [
          Expanded(
            child: MoveWindow(
              child: Padding(
                padding: const EdgeInsets.only(left: 5.0, top: 8.0),
                child: Row(
                  children: [
                    back
                        ? IconButton(
                            style: ButtonStyle(
                                padding: ButtonState.all(const EdgeInsets.only(
                              top: 5.0,
                              bottom: 5.0,
                              left: 15.0,
                              right: 15.0,
                            ))),
                            icon: const Icon(FluentIcons.back),
                            onPressed: () {
                              Navigator.pop(context);
                            },
                          )
                        : Container(),
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Text('WSL Manager ' + currentVersion),
                    ),
                  ],
                ),
              ),
            ),
          ),
          MinimizeWindowButton(
            colors: WindowButtonColors(iconNormal: themeData.activeColor),
          ),
          MaximizeWindowButton(
            colors: WindowButtonColors(iconNormal: themeData.activeColor),
          ),
          CloseWindowButton(
            colors: WindowButtonColors(
                iconNormal: themeData.activeColor,
                mouseOver: Colors.warningPrimaryColor),
          )
        ],
      ),
    ),
  );
}
