import 'package:flutter/foundation.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:yaml/yaml.dart';

/// QuickActions Interface
class QuickActionItem {
  QuickActionItem(
      {required this.name,
      this.description = '',
      this.version = '',
      this.author = '',
      this.license = '',
      this.git = '',
      this.distro = '',
      required this.content});

  String name;
  String description;
  String version;
  String author;
  String license;
  String git;
  dynamic distro; // either a string or a list of strings
  String content;

  /// Load from yaml string
  /// @param {String} yamlString
  /// @return {QuickAction}
  /// @throws {Exception}
  static QuickActionItem fromYamlString(String yamlString,
      {String content = ""}) {
    var yaml = loadYaml(yamlString);
    if (yaml is! Map) {
      throw Exception('Invalid yaml file');
    }
    if (yaml['name'] is! String) {
      throw Exception('Invalid yaml file');
    }
    if (yaml['description'] is! String) {
      throw Exception('Invalid yaml file');
    }
    if (yaml['version'] is! String) {
      throw Exception('Invalid yaml file');
    }
    if (yaml['author'] is! String) {
      throw Exception('Invalid yaml file');
    }
    if (yaml['license'] is! String) {
      throw Exception('Invalid yaml file');
    }
    if (yaml['git'] is! String) {
      throw Exception('Invalid yaml file');
    }
    if (yaml['distro'] is! String && yaml['distro'] is! List) {
      throw Exception('Invalid yaml file');
    }
    return QuickActionItem(
        name: yaml['name'],
        description: yaml['description'],
        version: yaml['version'],
        author: yaml['author'],
        license: yaml['license'],
        git: yaml['git'],
        distro: yaml['distro'],
        content: content);
  }

  /// To yaml string
  /// @return {String}
  String toYamlString() {
    return '''
name: $name
description: $description
version: $version
author: $author
license: $license
git: $git
distro: $distro
''';
  }
}

class QuickAction {
  QuickAction();
  QuickAction.addToPrefs(QuickActionItem item) {
    // Get old lists
    List<String> quickSettingsTitles =
        prefs.getStringList('quickSettingsTitles') ?? [];
    List<String> quickSettingsContents =
        prefs.getStringList('quickSettingsContents') ?? [];

    // Add to list
    if (!quickSettingsTitles.contains(item.name)) {
      quickSettingsTitles.add(item.name);
      quickSettingsContents.add(item.content);
    }
    // Edit if already exists
    else {
      int index = quickSettingsTitles.indexOf(item.name);
      quickSettingsContents[index] = item.content;
    }

    // Set shared prefs
    prefs.setStringList('quickSettingsTitles', quickSettingsTitles);
    prefs.setStringList('quickSettingsContents', quickSettingsContents);
    prefs.setString('quickSettingsMeta_${item.name}', item.toYamlString());
  }

  QuickAction.removeFromPrefs(QuickActionItem item) {
    // Get old lists
    List<String> quickSettingsTitles =
        prefs.getStringList('quickSettingsTitles') ?? [];
    List<String> quickSettingsContents =
        prefs.getStringList('quickSettingsContents') ?? [];

    // Remove from list
    if (quickSettingsTitles.contains(item.name)) {
      int index = quickSettingsTitles.indexOf(item.name);
      quickSettingsTitles.removeAt(index);
      quickSettingsContents.removeAt(index);
    }

    // Set shared prefs
    prefs.setStringList('quickSettingsTitles', quickSettingsTitles);
    prefs.setStringList('quickSettingsContents', quickSettingsContents);
  }

  List<QuickActionItem> getFromPrefs() {
    List<QuickActionItem> quickActions = [];
    // Get lists
    List<String> quickSettingsTitles =
        prefs.getStringList('quickSettingsTitles') ?? [];
    List<String> quickSettingsContents =
        prefs.getStringList('quickSettingsContents') ?? [];

    // Add to list
    for (int i = 0; i < quickSettingsTitles.length; i++) {
      String name = quickSettingsTitles[i];
      String? quickSettingsMetadata =
          prefs.getString('quickSettingsMeta_$name');
      if (quickSettingsMetadata != null) {
        try {
          QuickActionItem item = QuickActionItem.fromYamlString(
              quickSettingsMetadata,
              content: quickSettingsContents[i]);
          // Parse yaml from metadata
          quickActions.add(item);
        } catch (e) {
          if (kDebugMode) {
            print(e);
          }
        }
      } else {
        // For local quick actions
        quickActions.add(
            QuickActionItem(name: name, content: quickSettingsContents[i]));
      }
    }

    return quickActions;
  }
}
