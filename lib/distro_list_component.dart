import 'api.dart';
import 'dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';

FutureBuilder<List<String>> distroList(WSLApi api, Function(String) statusMsg) {
  return FutureBuilder<List<String>>(
    future: api.list(),
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        List<Widget> newList = [];
        List list = snapshot.data ?? [];
        for (String item in list) {
          newList.add(Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Container(
              color: const Color.fromRGBO(0, 0, 0, 0.1),
              child: ListTile(
                title: Text(item),
                leading: IconButton(
                  icon: const Icon(FluentIcons.play),
                  onPressed: () {
                    api.start(item);
                  },
                ),
                trailing: Row(
                  children: [
                    IconButton(
                      icon: const Icon(FluentIcons.copy),
                      onPressed: () async {
                        copyDialog(context, item, api, statusMsg);
                      },
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.rename),
                      onPressed: () {
                        renameDialog(context, item, api, statusMsg);
                      },
                    ),
                    IconButton(
                        icon: const Icon(FluentIcons.delete),
                        onPressed: () {
                          deleteDialog(context, item, api, statusMsg);
                        }),
                  ],
                ),
              ),
            ),
          ));
        }
        return Expanded(
          child: ListView.custom(
            childrenDelegate: SliverChildListDelegate(newList),
          ),
        );
      } else if (snapshot.hasError) {
        return Text('${snapshot.error}');
      }

      // By default, show a loading spinner.
      return const Center(child: ProgressRing());
    },
  );
}

deleteDialog(context, item, api, Function(String) statusMsg) {
  dialog(
      context: context,
      item: item,
      api: api,
      statusMsg: statusMsg,
      title: 'Delete $item permanently?',
      body: 'If you delete this Distro you won\'t be able to recover it.'
          ' Do you want to delete it?',
      submitText: 'Delete',
      submitInput: false,
      submitStyle: ButtonStyle(
        backgroundColor: ButtonState.all(Colors.red),
        foregroundColor: ButtonState.all(Colors.white),
      ),
      onSubmit: (inputText) async {
        api.remove(item);
        statusMsg('DONE: Deleted $item.');
      });
}

renameDialog(context, item, api, Function(String) statusMsg) {
  dialog(
      context: context,
      item: item,
      api: api,
      statusMsg: statusMsg,
      title: 'Rename $item',
      body: 'Warning: Renaming will recreate the whole WSL2 instance.',
      submitText: 'Rename',
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) async {
        statusMsg('Renaming $item to $inputText. This might take a while...');
        await api.copy(item, inputText);
        await api.remove(item);
        statusMsg('DONE: Renamed $item to $inputText.');
      });
}

copyDialog(context, item, api, Function(String) statusMsg) {
  dialog(
      context: context,
      item: item,
      api: api,
      statusMsg: statusMsg,
      title: 'Copy \'$item\'',
      body: 'Copy the WSL instance \'$item.\'',
      submitText: 'Copy',
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) async {
        statusMsg('Copying $item. This might take a while...');
        //await api.copy(item, copyController.text);
        statusMsg('DONE: Copied $item to $inputText.');
      });
}
