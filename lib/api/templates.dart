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
  final WSLApi wslApi;

  Templates({WSLApi? wslApi}) : wslApi = wslApi ?? WSLApi();

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
    await wslApi.export(name, getTemplatePath().file('$templateName.ext4'));
    templates ??= [];
    templates.add(templateName);
    prefs.setStringList('templates', templates);
    Notify.message('$templateName ${'savedastemplate-text'.i18n()}.',
        duration: const Duration(seconds: 3));
  }

  /// Use a template by [templateName] and create a new instance with [newName].
  Future<void> useTemplate(String templateName, String newName) async {
    Notify.message('creatinginstance-text'.i18n([newName]), loading: true);
    var result = await wslApi.import(newName, getInstancePath(newName).path,
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
    // Remove description
    prefs.remove('template_description_$name');
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
    return getDataPath()..cd('templates');
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

  /// Get template description by [name].
  String getTemplateDescription(String name) {
    return prefs.getString('template_description_$name') ?? '';
  }

  /// Set template description by [name].
  Future<void> setTemplateDescription(String name, String description) async {
    await prefs.setString('template_description_$name', description);
  }

  /// Rename a template from [oldName] to [newName].
  Future<void> renameTemplate(String oldName, String newName) async {
    if (oldName == newName) return;

    // Rename file
    File oldFile = File(getTemplateFilePath(oldName));
    if (await oldFile.exists()) {
      await oldFile.rename(getTemplateFilePath(newName));
    }

    // Update prefs list
    var templates = prefs.getStringList('templates');
    if (templates != null) {
      int index = templates.indexOf(oldName);
      if (index != -1) {
        templates[index] = newName;
        await prefs.setStringList('templates', templates);
      }
    }

    // Move description
    String? description = prefs.getString('template_description_$oldName');
    if (description != null) {
      await prefs.setString('template_description_$newName', description);
      await prefs.remove('template_description_$oldName');
    }
  }
}
