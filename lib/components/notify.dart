import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/theme.dart';

/// Notification bar at the bottom of the screen
class Notify {
  static late Function(
    String msg, {
    bool loading,
    bool useWidget,
    bool leadingIcon,
    Widget widget,
  }) message;
  static late Notify instance;

  Notify() {
    instance = this;
  }
}

/// Widget
Widget statusBuilder(status, statusWidget, loading, onClose) {
  return Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: AnimatedOpacity(
        opacity: status != '' ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 100),
        child: InfoBar(
          style: InfoBarThemeData(
            decoration: (severity) {
              Color color;
              switch (severity) {
                case InfoBarSeverity.info:
                  color = AppTheme().backgroundColor.light;
                  break;
                case InfoBarSeverity.warning:
                  color = AppTheme().backgroundColor.light;
                  break;
                case InfoBarSeverity.success:
                  color = AppTheme().backgroundColor.light;
                  break;
                case InfoBarSeverity.error:
                  color = AppTheme().backgroundColor.light;
                  break;
              }
              return BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4.0),
                border: Border.all(
                  color: AppTheme().backgroundColor.darker,
                ),
              );
            },
          ),
          title: status == 'WIDGET'
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: statusWidget)
              : Text(
                  status,
                  maxLines: 1,
                ),
          action: loading
              ? const SizedBox(width: 20.0, height: 20.0, child: ProgressRing())
              : const Text(''),
          severity: InfoBarSeverity.info,
          onClose: () => onClose(),
        ),
      ),
    ),
  );
}
