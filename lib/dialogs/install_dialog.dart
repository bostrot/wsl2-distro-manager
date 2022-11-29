import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Install Dialog
class InstallDialog extends StatelessWidget {
  const InstallDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('wslnotinstalled-text'.i18n()),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text('wslnotinstalledbody-text'.i18n()),
            ),
            Container(
              color: const Color.fromRGBO(0, 0, 0, 0.2),
              child: Padding(
                  padding: const EdgeInsets.only(left: 4.0, right: 4.0),
                  child: TextButton(
                      onPressed: () {
                        plausible.event(name: "wsl_install");
                        WSLApi().installWSL();
                      },
                      child: const Text("wsl --install"))),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('wslinstallhint-text'.i18n()),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('wslinstallinfo-text'.i18n()),
            ),
          ],
        ),
      ),
    );
  }
}
