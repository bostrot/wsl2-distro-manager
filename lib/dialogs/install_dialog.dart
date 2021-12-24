import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/api.dart';
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
            const Text('WSL is not installed.'),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                  'You can install it with following command in the Terminal:'),
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
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child:
                  Text('Hint: you can click the above command to install it'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text('(Keep '
                  'in mind that you need to restart your system to complete the'
                  ' install.)'),
            ),
          ],
        ),
      ),
    );
  }
}
