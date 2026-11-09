/// The git tag for the `version:` line of a pubspec, such as `v0.1.0`.
///
/// Throws a [FormatException] when there is no plain `major.minor.patch` version.
String releaseTag(String pubspecText) {
  final line = RegExp(r'^version:(.*?)\r?$', multiLine: true).firstMatch(pubspecText);
  if (line == null) throw const FormatException('pubspec.yaml has no version line');
  var value = (line.group(1) ?? '').split('#').first.trim();
  final quoted = RegExp(r'''^(["'])(.*)\1$''').firstMatch(value);
  if (quoted != null) value = (quoted.group(2) ?? '').trim();
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value)) {
    throw FormatException('version must look like 1.2.3, got "$value"');
  }
  return 'v$value';
}
