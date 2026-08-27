import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/nav/router.dart';

/// Full-page version of the create flow.
///
/// The form itself is [CreateWidget], shared with the old dialog. A page
/// rather than a dialog because creating an instance downloads and extracts
/// image layers: that can run for minutes, and a dialog both hides the
/// progress notifications behind it and invites an accidental dismiss.
class CreatePage extends StatefulWidget {
  const CreatePage({super.key});

  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  final WSLApi _api = WSLApi();
  final TextEditingController _autoSuggestBox = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final ValueNotifier<CreateSourceType> _sourceType =
      ValueNotifier<CreateSourceType>(CreateSourceType.repo);
  final ValueNotifier<bool> _creating = ValueNotifier<bool>(false);
  final ValueNotifier<CreateFailure?> _createError =
      ValueNotifier<CreateFailure?>(null);

  @override
  void initState() {
    super.initState();
    plausible.event(page: 'create');
  }

  @override
  void dispose() {
    _autoSuggestBox.dispose();
    _locationController.dispose();
    _nameController.dispose();
    _userController.dispose();
    _sourceType.dispose();
    _creating.dispose();
    _createError.dispose();
    super.dispose();
  }

  void _leave() {
    if (router.canPop()) {
      router.pop();
    } else {
      router.goNamed('home');
    }
  }

  Future<void> _create() async {
    _creating.value = true;
    _createError.value = null;
    final success = await createInstance(
      _nameController,
      _locationController,
      _api,
      _autoSuggestBox,
      _userController,
      isDocker: _sourceType.value == CreateSourceType.docker,
      isDockerLocalImage:
          _sourceType.value == CreateSourceType.dockerLocalImage,
      isVhdx: _sourceType.value == CreateSourceType.vhdx,
      onError: _createError,
    );
    if (!mounted) return;
    if (success) {
      _leave();
    } else {
      // Stay put so the error is readable and the form can be corrected.
      _creating.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _creating,
      builder: (context, isCreating, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'createnewinstance-text'.i18n(),
                style: FluentTheme.of(context).typography.titleLarge,
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: CreateWidget(
                  nameController: _nameController,
                  api: _api,
                  autoSuggestBox: _autoSuggestBox,
                  locationController: _locationController,
                  userController: _userController,
                  sourceType: _sourceType,
                  creating: _creating,
                  createError: _createError,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  FilledButton(
                    key: const ValueKey('test-create-button'),
                    onPressed: isCreating ? null : _create,
                    child: isCreating
                        ? const SizedBox.square(
                            dimension: 16,
                            child: ProgressRing(strokeWidth: 2.0),
                          )
                        : Text('create-text'.i18n()),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    key: const ValueKey('test-cancel-button'),
                    onPressed: isCreating ? null : _leave,
                    child: Text('cancel-text'.i18n()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
