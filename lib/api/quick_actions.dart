import 'dart:convert';
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

  /// To yaml string.
  ///
  /// Scalars are JSON-quoted (valid YAML double-quoted scalars) so an empty
  /// field stays a string instead of parsing back as null — an unquoted
  /// `description: ` is YAML null, which [fromYamlString] rejects, dropping
  /// the whole snippet from the list on reload.
  String toYamlString() {
    final distroYaml =
        distro is List ? distro.toString() : jsonEncode(distro?.toString() ?? '');
    return 'name: ${jsonEncode(name)}\n'
        'description: ${jsonEncode(description)}\n'
        'version: ${jsonEncode(version)}\n'
        'author: ${jsonEncode(author)}\n'
        'license: ${jsonEncode(license)}\n'
        'git: ${jsonEncode(git)}\n'
        'distro: $distroYaml\n';
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
