import 'dart:io';

import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/safe_paths.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

/// This class handles all template related functions.
/// Templates are distros that are saved as ext4 files with additional metadata
/// saved in the SharedPreferences.
class Templates {
  /// Save a distro as a template by [name]
  Future<void> saveTemplate(String name) async {
    String templateName = name;
    // Check if template already exists
    var templates = prefs.getStringList('templates');
    var i = 2;
    while (templates != null && templates.contains(templateName)) {
      if (i > 2) {
        templateName =
            '${templateName.substring(0, templateName.length - 2)}-$i';
      } else {
        templateName = '$templateName-2';
      }
      i++;
    }

    plausible.event(name: "wsl_saveastemplate");
    Notify.message('$templateName ${'savingastemplate-text'.i18n()}.',
        loading: true);
    await WSLApi().export(name, getTemplatePath().file('$templateName.ext4'));
    templates ??= [];
    templates.add(templateName);
    prefs.setStringList('templates', templates);
    Notify.message('$templateName ${'savedastemplate-text'.i18n()}.',
        duration: const Duration(seconds: 3));
  }

  /// Use a template by [templateName] and create a new instance with [newName].
  Future<void> useTemplate(String templateName, String newName) async {
    Notify.message('creatinginstance-text'.i18n([newName]), loading: true);
    var result = await WSLApi().import(newName, getInstancePath(newName).path,
        getTemplateFilePath(templateName));
    Notify.message(result);
  }

  /// Delete a template by [name] and update the SharedPreferences.
  /// [Warning] This will also delete the template file.
  Future<void> deleteTemplate(String name) async {
    // Remove from prefs StringList
    var templates = prefs.getStringList('templates');
    if (templates == null) return;
    templates.remove(name);
    prefs.setStringList('templates', templates);
    // Delete template file
    await File(getTemplateFilePath(name)).delete();
    Notify.message('deletedinstance-text'.i18n([name]));
  }

  /// Get a list of all templates.
  List<String> getTemplates() {
    var templates = prefs.getStringList('templates');
    if (templates == null) return [];
    return templates;
  }

  /// Return the general template path. Templates are saved here by default.
  /// It will be created if it does not exist. Relative to DistroPath.
  ///
  /// e.g. C:\WSL2-Distros\templates
  SafePath getTemplatePath() {
    return getDistroPath()
      ..cdUp()
      ..cd('templates');
  }

  /// Return the path to a template by [name].
  /// e.g. C:\WSL2-Distros\templates\ubuntu.ext4
  String getTemplateFilePath(String name) {
    return getTemplatePath().file('$name.ext4');
  }

  /// Get template size by [name].
  /// Returns a string with the size in GB fixed to 2 decimal places.
  /// e.g. 1.23 GB
  String getTemplateSize(String name) {
    var path = getTemplateFilePath(name);
    if (File(path).existsSync() == false) return '0 GB';
    var size = File(path).lengthSync();
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
