// A section-aware, comment-preserving model of a distro's `/etc/wsl.conf`.
//
// ## Why this file exists
//
// The old writer (`assets/scripts/settings.bash`, deleted with this file's
// first use) templated a `sed` expression per key and ran it inside the
// distro as root. Three separate defects fell out of that one design, all
// recorded in doc/audit/wsl-docs/wslconf-keys.md:
//
// * **CC-1** — both the `[[ =~ ]]` existence test and the `s///g` searched the
//   whole file, so toggling `[interop] enabled` also rewrote
//   `[automount] enabled`. Two documented sections share the key name.
// * **CC-2** — the value was interpolated into `s/KEY[ ]*=[ ]*.*/KEY = VALUE/g`
//   verbatim, so any `/` closed the substitution early. `[automount] root`'s
//   documented default `/mnt/` is itself a failing value.
// * **CC-7** — the same substitution landed inside `echo -e "…"` in the
//   add-a-section branch, where a `"`, a backtick or a `$(…)` executed as
//   root inside the distro.
//
// Reading the file, mutating a model and writing the whole file back makes
// those one fix rather than three: nothing is templated into a shell, so
// nothing in a value can be interpreted. [WSLApi.writeWSLConf] carries the
// payload base64-encoded for the same reason.
//
// Comments, blank lines, key order and unknown keys survive the round trip —
// `wsl.conf` is a file users hand-edit, and a settings dialog that reformats
// it on every toggle is its own bug report.

/// The documented keys of each `wsl.conf` section, in their canonical
/// spelling, from `microsoftdocs/wsl@8842def` (`wsl-config.md`).
///
/// Used to normalise spelling on read: WSL's own parser is case-insensitive,
/// so a hand-written `mountfstab = true` is a valid spelling of
/// `mountFsTab`, but the dialog reads its preferences under the spelling the
/// widget uses. Without this table that file populates a preference no widget
/// ever reads and the toggle renders off (audit V-7).
const Map<String, List<String>> kWslConfKeys = <String, List<String>>{
  'automount': <String>['enabled', 'mountFsTab', 'root', 'options'],
  'boot': <String>['systemd', 'command', 'protectBinfmt'],
  'gpu': <String>['enabled'],
  'interop': <String>['enabled', 'appendWindowsPath'],
  'network': <String>['generateHosts', 'generateResolvConf', 'hostname'],
  'time': <String>['useWindowsTimezone'],
  'user': <String>['default'],
};

/// [section] in its documented spelling, or as written when it is not a
/// section this app knows.
String canonicalWslConfSection(String section) {
  final lower = section.trim().toLowerCase();
  for (final known in kWslConfKeys.keys) {
    if (known.toLowerCase() == lower) return known;
  }
  return section.trim();
}

/// [key] in its documented spelling within [section], or as written when the
/// section or the key is unknown.
String canonicalWslConfKey(String section, String key) {
  final lower = key.trim().toLowerCase();
  for (final known
      in kWslConfKeys[canonicalWslConfSection(section)] ?? const <String>[]) {
    if (known.toLowerCase() == lower) return known;
  }
  return key.trim();
}

enum _LineKind { raw, section, entry }

class _ConfLine {
  _LineKind kind;

  /// Verbatim source text. Rewritten only for an entry this app changes, so
  /// every untouched line comes back out byte for byte.
  String text;

  /// Canonical name of the section this line sits in. Empty for the preamble.
  String section;

  /// Key spelling *as written in the file*, kept so an update edits the user's
  /// line rather than replacing it with a differently-spelled one.
  String key;

  String value;

  _ConfLine(this.kind, this.text,
      {this.section = '', this.key = '', this.value = ''});
}

/// A parsed `/etc/wsl.conf`.
///
/// Section and key matching is case-insensitive throughout, matching WSL's
/// own parser. Values are held and written verbatim — no quoting, no
/// escaping, no interpretation — because [WSLApi.writeWSLConf] never puts
/// them through a shell.
class WslConfFile {
  final List<_ConfLine> _lines;
  final bool _trailingNewline;

  WslConfFile._(this._lines, this._trailingNewline);

  /// An empty file, which is what a distro without `/etc/wsl.conf` reads as.
  factory WslConfFile.empty() => WslConfFile._(<_ConfLine>[], true);

  factory WslConfFile.parse(String text) {
    if (text.isEmpty) return WslConfFile.empty();

    final trailingNewline = text.endsWith('\n');
    final source = trailingNewline
        ? text.substring(0, text.length - 1).split('\n')
        : text.split('\n');

    final lines = <_ConfLine>[];
    var currentSection = '';

    for (final rawLine in source) {
      // `cat` inside the distro yields LF, but a file authored on Windows and
      // copied in keeps its CR. Drop it on read and write LF back.
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      final trimmed = line.trim();

      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        currentSection =
            canonicalWslConfSection(trimmed.substring(1, trimmed.length - 1));
        lines.add(_ConfLine(_LineKind.section, line, section: currentSection));
        continue;
      }

      // A comment or a blank line is opaque: never matched, never rewritten,
      // always preserved in place.
      final isComment = trimmed.startsWith('#') || trimmed.startsWith(';');
      // A key outside any section is ignored by WSL, so it is opaque too —
      // treating it as an entry would let the dialog edit a line that has no
      // effect.
      if (isComment || currentSection.isEmpty || !trimmed.contains('=')) {
        lines.add(_ConfLine(_LineKind.raw, line, section: currentSection));
        continue;
      }

      final separator = trimmed.indexOf('=');
      final key = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      if (key.isEmpty) {
        lines.add(_ConfLine(_LineKind.raw, line, section: currentSection));
        continue;
      }

      lines.add(_ConfLine(_LineKind.entry, line,
          section: currentSection, key: key, value: value));
    }

    return WslConfFile._(lines, trailingNewline || source.isEmpty);
  }

  bool _matches(_ConfLine line, String section, String key) =>
      line.kind == _LineKind.entry &&
      line.section.toLowerCase() == section.toLowerCase() &&
      line.key.toLowerCase() == key.toLowerCase();

  /// The value of `[section] key`, or null when the key is not in the file.
  ///
  /// "Absent" and "empty" are different answers: a documented default only
  /// applies to the first.
  String? get(String section, String key) {
    final s = canonicalWslConfSection(section);
    final k = canonicalWslConfKey(s, key);
    for (final line in _lines) {
      if (_matches(line, s, k)) return line.value;
    }
    return null;
  }

  /// True when `[section] key` has a line in the file, whatever its value.
  bool contains(String section, String key) => get(section, key) != null;

  /// Every key in the file, by canonical section and canonical key.
  ///
  /// A section that is present but empty appears with an empty map, which is
  /// what the previous hand-rolled parser did and what the dialog's
  /// preference loader expects.
  Map<String, Map<String, String>> toMap() {
    final config = <String, Map<String, String>>{};
    for (final line in _lines) {
      if (line.kind == _LineKind.section) {
        config.putIfAbsent(line.section, () => <String, String>{});
      } else if (line.kind == _LineKind.entry) {
        config.putIfAbsent(line.section, () => <String, String>{})[
            canonicalWslConfKey(line.section, line.key)] = line.value;
      }
    }
    return config;
  }

  /// Set `[section] key` to [value], creating the section if it is missing.
  ///
  /// An existing key keeps the spelling it has in the file; only its value
  /// changes. A new key is written in its documented spelling, after the last
  /// key of its section rather than at the end of the file.
  void set(String section, String key, String value) {
    final s = canonicalWslConfSection(section);
    final k = canonicalWslConfKey(s, key);

    for (final line in _lines) {
      if (_matches(line, s, k)) {
        line.value = value;
        line.text = '${line.key} = $value';
        return;
      }
    }

    // Append after the section's last meaningful line rather than at the end
    // of the file: a key that lands under the *next* header is a key WSL
    // reads as belonging to another section.
    var header = -1;
    var anchor = -1;
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.section.toLowerCase() != s.toLowerCase()) continue;
      if (line.kind == _LineKind.section) header = i;
      if (line.kind == _LineKind.entry || line.text.trim().isNotEmpty) {
        anchor = i;
      }
    }

    final entry = _ConfLine(_LineKind.entry, '$k = $value',
        section: s, key: k, value: value);

    if (header < 0) {
      if (_lines.isNotEmpty && _lines.last.text.trim().isNotEmpty) {
        _lines.add(_ConfLine(_LineKind.raw, '', section: s));
      }
      _lines.add(_ConfLine(_LineKind.section, '[$s]', section: s));
      _lines.add(entry);
      return;
    }

    _lines.insert((anchor > header ? anchor : header) + 1, entry);
  }

  /// Remove `[section] key` from the file. Returns whether a line went away.
  ///
  /// This is the third state the tri-state toggles need: returning a key to
  /// *unset* has to delete its line, not write the default back, or the
  /// distro's own default can never take over again.
  bool remove(String section, String key) {
    final s = canonicalWslConfSection(section);
    final k = canonicalWslConfKey(s, key);
    final before = _lines.length;
    _lines.removeWhere((line) => _matches(line, s, k));
    return _lines.length != before;
  }

  /// The whole file as it should be written back, with LF endings.
  String serialize() {
    if (_lines.isEmpty) return '';
    final body = _lines.map((line) => line.text).join('\n');
    return _trailingNewline ? '$body\n' : body;
  }
}
