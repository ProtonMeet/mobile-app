/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'artifacts_provider.dart';
import 'builder.dart';
import 'environment.dart';
import 'options.dart';
import 'target.dart';

final log = Logger('build_cmake');

class BuildCMake {
  final CargokitUserOptions userOptions;

  BuildCMake({required this.userOptions});

  Future<void> build() async {
    final targetPlatform = Environment.targetPlatform;
    final target = Target.forFlutterName(Environment.targetPlatform);
    if (target == null) {
      throw Exception("Unknown target platform: $targetPlatform");
    }

    final environment = BuildEnvironment.fromEnvironment(isAndroid: false);
    final provider =
        ArtifactProvider(environment: environment, userOptions: userOptions);
    final artifacts = await provider.getArtifacts([target]);

    final libs = artifacts[target]!;
    final outputDir = Environment.outputDir;
    Directory(outputDir).createSync(recursive: true);

    final packageName = environment.crateInfo.packageName;
    var copiedSiblings = false;

    for (final lib in libs) {
      if (lib.type != AritifactType.dylib) {
        continue;
      }
      _copyFileIfPresent(
        sourcePath: lib.path,
        destPath: path.join(outputDir, lib.finalFileName),
      );

      // Copy extra shared modules (e.g. libgopenpgp-sys.dll) once from the main
      // cdylib directory. Windows also needs separate copies for .dll.lib / .pdb
      // artifacts above — do not run sibling scan for those entries.
      if (!copiedSiblings && _isMainCdylibArtifact(lib, packageName)) {
        _copySiblingSharedModules(
          artifactPath: lib.path,
          outputDir: outputDir,
          primaryFileName: lib.finalFileName,
        );
        copiedSiblings = true;
      }
    }
  }
}

bool _isMainCdylibArtifact(Artifact lib, String packageName) {
  final name = lib.finalFileName;
  return name == 'lib$packageName.so' || name == '$packageName.dll';
}

void _copyFileIfPresent({required String sourcePath, required String destPath}) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    log.warning('Rust artifact missing: $sourcePath');
    return;
  }
  file.copySync(destPath);
  log.info('Copied $sourcePath to $destPath');
}

/// Same idea as [BuildGradle.build]: ship sibling `.so` / `.dll` modules built
/// next to the FRB cdylib (shared gopenpgp on Windows when applicable).
void _copySiblingSharedModules({
  required String artifactPath,
  required String outputDir,
  required String primaryFileName,
}) {
  final directory = File(artifactPath).parent;
  if (!directory.existsSync()) {
    return;
  }

  for (final entity in directory.listSync()) {
    if (entity is! File) {
      continue;
    }
    final fileName = path.basename(entity.path);
    if (fileName == primaryFileName) {
      continue;
    }
    if (!_isRuntimeSharedModule(fileName)) {
      continue;
    }
    final destinationPath = path.join(outputDir, fileName);
    entity.copySync(destinationPath);
    log.info('Copied ${entity.path} to $destinationPath');
  }
}

bool _isRuntimeSharedModule(String fileName) {
  if (fileName.endsWith('.dll.lib') || fileName.endsWith('.pdb')) {
    return false;
  }
  return fileName.endsWith('.so') ||
      fileName.endsWith('.dll') ||
      fileName.endsWith('.dylib');
}
