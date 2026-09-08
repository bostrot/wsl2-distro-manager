import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/named_button.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

/// Shows how to sign in to a VM by hand.
///
/// Everything the app itself does — snippets, the terminal button, templating
/// — goes in by SSH key and never asks for any of this. The VM's own screen
/// does ask: it shows a `login:` prompt, and before bostrot/ai-tasks#60 the
/// account behind it had no password at all and nothing named it, so a guest
/// created with a custom user was unreachable from its own window.
Future<void> showVmCredentialsDialog(BuildContext context, AppleVmApi api,
    String instance) async {
  await showDialog<void>(
    context: context,
    builder: (_) => VmCredentialsDialog(api: api, instance: instance),
  );
}

class VmCredentialsDialog extends StatefulWidget {
  final AppleVmApi api;
  final String instance;

  const VmCredentialsDialog(
      {super.key, required this.api, required this.instance});

  @override
  State<VmCredentialsDialog> createState() => _VmCredentialsDialogState();
}

class _VmCredentialsDialogState extends State<VmCredentialsDialog> {
  GuestCredentials? _credentials;
  String? _error;

  /// The password is masked until asked for: this dialog is the kind of thing
  /// that ends up on a screen share.
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    plausible.event(page: 'vm_credentials_dialog');
    _load();
  }

  Future<void> _load() async {
    try {
      final credentials = await widget.api.guestCredentials(widget.instance);
      if (mounted) setState(() => _credentials = credentials);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    Notify.message('copied-text'.i18n(),
        severity: InfoBarSeverity.success,
        duration: const Duration(seconds: 2));
  }

  /// One labelled, selectable value with a copy button beside it.
  Widget _field(String label, String value,
      {required String testKey, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: InfoLabel(
        label: label,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SelectableText(
                obscure ? '•' * value.length : value,
                key: ValueKey(testKey),
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8.0),
            // The name says *what* is being copied: three identical "Copy"
            // buttons in one dialog name nothing to a screen reader.
            NamedIconButton(
              key: ValueKey('$testKey-copy'),
              label: '${'copy-text'.i18n()}: $label',
              icon: FluentIcons.copy,
              iconSize: 14.0,
              onPressed: () => _copy(value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return Text(error,
          key: const ValueKey('test-vm-credentials-error'),
          style: TextStyle(color: destructiveColor(context)));
    }
    final credentials = _credentials;
    if (credentials == null) {
      return Row(children: [
        const SizedBox.square(
            dimension: 16.0, child: ProgressRing(strokeWidth: 2.0)),
        const SizedBox(width: 8.0),
        Text('loading-text'.i18n()),
      ]);
    }
    final password = credentials.password;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('vmlogindetailsbody-text'.i18n()),
        _field('vmloginuser-text'.i18n(), credentials.user,
            testKey: 'test-vm-credentials-user'),
        if (password != null)
          _field('password-text'.i18n(), password,
              testKey: 'test-vm-credentials-password', obscure: !_revealed),
        if (password == null)
          Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Text('vmloginnopassword-text'.i18n(),
                key: const ValueKey('test-vm-credentials-nopassword')),
          ),
        if (credentials.appliedOnNextBoot)
          Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: InfoBar(
              key: const ValueKey('test-vm-credentials-pending'),
              title: Text('vmloginpending-text'.i18n()),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
          ),
        _field('vmloginsshkey-text'.i18n(), credentials.sshKeyPath,
            testKey: 'test-vm-credentials-key'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPassword = _credentials?.password != null;
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 520.0),
      title: Text('vmlogindetails-text'.i18n([distroLabel(widget.instance)])),
      content: _body(),
      actions: [
        if (hasPassword)
          Button(
            key: const ValueKey('test-vm-credentials-reveal'),
            onPressed: () => setState(() => _revealed = !_revealed),
            child: Text(_revealed
                ? 'vmloginhide-text'.i18n()
                : 'vmloginreveal-text'.i18n()),
          ),
        FilledButton(
          key: const ValueKey('test-dialog-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text('close-text'.i18n()),
        ),
      ],
    );
  }
}
