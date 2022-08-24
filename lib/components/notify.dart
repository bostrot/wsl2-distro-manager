import 'package:fluent_ui/fluent_ui.dart';

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
