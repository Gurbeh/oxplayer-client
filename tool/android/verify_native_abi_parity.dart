// Verifies Play-safe native ABI layout before uploading an AAB/APK.
//
// Usage (from oxplayer-client/):
//   dart run tool/android/verify_native_abi_parity.dart --aab path/to/app.aab
//   dart run tool/android/verify_native_abi_parity.dart --dir build/app/intermediates/merged_native_libs/...
//
// Fails if:
// - armeabi-v7a and arm64-v8a .so basenames differ (Google Play 64-bit pairing)
// - x86 (32-bit Intel) natives are present (Flutter never ships libflutter/libapp on x86)
// - any .so is not a real ELF binary (e.g. an unresolved Git LFS pointer stub)
import 'dart:io';

import 'package:path/path.dart' as p;

const _arm32 = 'armeabi-v7a';
const _arm64 = 'arm64-v8a';
const _x64 = 'x86_64';
const _allowedAbis = {_arm32, _arm64, _x64};
const _elfMagic = [0x7f, 0x45, 0x4c, 0x46]; // "\x7fELF"

void main(List<String> args) {
  final aab = _flagValue(args, '--aab');
  final dir = _flagValue(args, '--dir');

  if (aab == null && dir == null) {
    stderr.writeln(
      'Usage: dart run tool/android/verify_native_abi_parity.dart '
      '--aab <file.aab> | --dir <merged_native_libs/out>',
    );
    exit(2);
  }

  final Map<String, Set<String>> byAbi;
  if (aab != null) {
    byAbi = _libsFromArchive(aab);
  } else {
    byAbi = _libsFromDirectory(Directory(dir!));
  }

  _verify(byAbi);
  stdout.writeln('[verify_native_abi_parity] OK — ${_summarize(byAbi)}');
}

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

Map<String, Set<String>> _libsFromDirectory(Directory root) {
  final out = <String, Set<String>>{};
  if (!root.existsSync()) {
    _fail('Directory not found: ${root.path}');
  }
  final badMagic = <String>[];
  for (final abi in _allowedAbis) {
    final abiDir = _findAbiDir(root, abi);
    if (abiDir == null) continue;
    out[abi] = _listSo(abiDir);
    for (final f in abiDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.so')) continue;
      if (!_hasElfMagic(f.readAsBytesSync())) badMagic.add(f.path);
    }
  }
  final x86Dir = _findAbiDir(root, 'x86');
  if (x86Dir != null && _listSo(x86Dir).isNotEmpty) {
    _fail(
      'Found x86 (32-bit) natives under ${x86Dir.path}. '
      'Exclude x86 via ndk.abiFilters (armeabi-v7a, arm64-v8a, x86_64 only).',
    );
  }
  if (badMagic.isNotEmpty) {
    _fail(
      'Not real ELF binaries (e.g. unresolved Git LFS pointer stubs): '
      '${badMagic.join(", ")}',
    );
  }
  return out;
}

bool _hasElfMagic(List<int> bytes) {
  if (bytes.length < _elfMagic.length) return false;
  for (var i = 0; i < _elfMagic.length; i++) {
    if (bytes[i] != _elfMagic[i]) return false;
  }
  return true;
}

Directory? _findAbiDir(Directory root, String abi) {
  final direct = Directory(p.join(root.path, abi));
  if (direct.existsSync()) return direct;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is Directory && p.basename(entity.path) == abi) {
      return entity;
    }
  }
  return null;
}

Map<String, Set<String>> _libsFromArchive(String archivePath) {
  final file = File(archivePath);
  if (!file.existsSync()) {
    _fail('Archive not found: $archivePath');
  }
  final result = Process.runSync('jar', ['tf', archivePath]);
  if (result.exitCode != 0) {
    _fail(
      'jar tf failed (set JAVA_HOME): ${result.stderr}\n'
      'Archive: $archivePath',
    );
  }
  final lines = (result.stdout as String).split('\n');
  final out = <String, Set<String>>{};
  final forbiddenX86 = <String>{};
  final soEntries = <String>[];

  for (final raw in lines) {
    final line = raw.trim();
    if (!line.contains('/lib/') || !line.endsWith('.so')) continue;

    final match = RegExp(r'lib/([^/]+)/([^/]+\.so)$').firstMatch(line);
    if (match == null) continue;
    final abi = match.group(1)!;
    final name = match.group(2)!;
    if (abi == 'x86') {
      forbiddenX86.add(name);
      continue;
    }
    if (!_allowedAbis.contains(abi)) continue;
    out.putIfAbsent(abi, () => {}).add(name);
    soEntries.add(line);
  }

  if (forbiddenX86.isNotEmpty) {
    _fail(
      'AAB/APK contains x86 (32-bit) natives (${forbiddenX86.length} file(s)), '
      'e.g. ${forbiddenX86.take(3).join(", ")}. '
      'Use ndk.abiFilters without x86.',
    );
  }

  final badMagic = <String>[];
  for (final entry in soEntries) {
    final extract = Process.runSync(
      'unzip',
      ['-p', archivePath, entry],
      stdoutEncoding: null,
    );
    if (extract.exitCode != 0) {
      _fail('unzip -p failed for $entry in $archivePath: ${extract.stderr}');
    }
    if (!_hasElfMagic(extract.stdout as List<int>)) badMagic.add(entry);
  }
  if (badMagic.isNotEmpty) {
    _fail(
      'Not real ELF binaries (e.g. unresolved Git LFS pointer stubs): '
      '${badMagic.join(", ")}',
    );
  }
  return out;
}

Set<String> _listSo(Directory dir) {
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.so'))
      .map((f) => p.basename(f.path))
      .toSet();
}

void _verify(Map<String, Set<String>> byAbi) {
  final v7 = byAbi[_arm32];
  final v8 = byAbi[_arm64];

  if (v7 == null || v7.isEmpty) {
    _fail('Missing $_arm32 native libraries.');
  }
  if (v8 == null || v8.isEmpty) {
    _fail(
      'Missing $_arm64 native libraries '
      '(required for Snapdragon 680 / Moto G Play class devices).',
    );
  }

  final arm32 = v7!;
  final arm64 = v8!;
  final only32 = arm32.difference(arm64);
  final only64 = arm64.difference(arm32);
  if (only32.isNotEmpty || only64.isNotEmpty) {
    _fail(
      'ARM ABI mismatch (Play 64-bit pairing):\n'
      '  only in $_arm32: ${only32.join(", ")}\n'
      '  only in $_arm64: ${only64.join(", ")}',
    );
  }

  final x64 = byAbi[_x64];
  if (x64 != null && x64.isNotEmpty) {
    final x64Only = x64.difference(arm64);
    if (x64Only.isNotEmpty) {
      stderr.writeln(
        '[verify_native_abi_parity] note: x86_64-only libs (emulator): ${x64Only.join(", ")}',
      );
    }
  }
}

String _summarize(Map<String, Set<String>> byAbi) {
  return byAbi.entries.map((e) => '${e.key}=${e.value.length}').join(', ');
}

void _fail(String message) {
  stderr.writeln('[verify_native_abi_parity] ERROR: $message');
  exit(1);
}
