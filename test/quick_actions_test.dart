import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/api/quick_actions.dart';

void main() {
  test('QuickActionItem.fromYamlString parses valid yaml', () {
    const yaml = '''
name: Test Action
description: A test action
version: 1.0.0
author: Me
license: MIT
git: https://github.com/test
distro: Ubuntu
''';
    final item = QuickActionItem.fromYamlString(yaml, content: 'echo hello');
    expect(item.name, 'Test Action');
    expect(item.description, 'A test action');
    expect(item.version, '1.0.0');
    expect(item.author, 'Me');
    expect(item.license, 'MIT');
    expect(item.git, 'https://github.com/test');
    expect(item.distro, 'Ubuntu');
    expect(item.content, 'echo hello');
  });

  test('QuickActionItem.fromYamlString throws on invalid yaml', () {
    expect(() => QuickActionItem.fromYamlString('invalid'), throwsException);
    expect(() => QuickActionItem.fromYamlString('name: 123'), throwsException); // name not string
  });
}
