import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:args/args.dart';
import 'package:xml/xml.dart';

/**
    This file creates a local maven repository which provides a custom built
    flutter engine.

    Code below is based on code from :
     flutter/packages/flutter_tools/lib/src/android/gradle.dart
*/

// from: packages/flutter_tools/lib/src/base/common.dart

/// Throw a specialized exception for expected situations
/// where the tool should exit with a clear message to the user
/// and no stack trace unless the --verbose option is specified.
/// For example: network errors.
Never throwToolExit(String? message, { int? exitCode }) {
  throw ToolExit(message, exitCode: exitCode);
}

/// Specialized exception for expected situations
/// where the tool should exit with a clear message to the user
/// and no stack trace unless the --verbose option is specified.
/// For example: network errors.
class ToolExit implements Exception {
  ToolExit(this.message, { this.exitCode });

  final String? message;
  final int? exitCode;

  @override
  String toString() => 'Error: $message';
}

void _createSymlink(String targetPath, String linkPath, FileSystem fileSystem) {
  final File targetFile = fileSystem.file(targetPath);
  if (!targetFile.existsSync()) {
    throwToolExit("The file $targetPath wasn't found in the local engine out directory.");
  }
  final File linkFile = fileSystem.file(linkPath);
  final Link symlink = linkFile.parent.childLink(linkFile.basename);
  try {
    symlink.createSync(targetPath, recursive: true);
  } on FileSystemException catch (exception) {
    throwToolExit(
        'Failed to create the symlink $linkPath->$targetPath: $exception'
    );
  }
}

String _getAbiByLocalEnginePath(String engineOutPath) {
  String result = 'armeabi_v7a';
  if (engineOutPath.contains('x86')) {
    result = 'x86';
  } else if (engineOutPath.contains('x64')) {
    result = 'x86_64';
  } else if (engineOutPath.contains('arm64')) {
    result = 'arm64_v8a';
  }
  return result;
}

String _getLocalArtifactVersion(String pomPath, FileSystem fileSystem) {
  final File pomFile = fileSystem.file(pomPath);
  if (!pomFile.existsSync()) {
    throwToolExit("The file $pomPath wasn't found in the local engine out directory.");
  }
  XmlDocument document;
  try {
    document = XmlDocument.parse(pomFile.readAsStringSync());
  } on XmlException {
    throwToolExit(
        'Error parsing $pomPath. Please ensure that this is a valid XML document.'
    );
  } on FileSystemException {
    throwToolExit(
        'Error reading $pomPath. Please ensure that you have read permission to this '
            'file and try again.');
  }
  final Iterable<XmlElement> project = document.findElements('project');
  assert(project.isNotEmpty);
  for (final XmlElement versionElement in document.findAllElements('version')) {
    if (versionElement.parent == project.first) {
      return versionElement.innerText;
    }
  }
  throwToolExit('Error while parsing the <version> element from $pomPath');
}

Future<Directory> checkAndCreateDirectory(FileSystem fileSystem, String path) async {
  final directory = fileSystem.directory(path);
  if (!(await directory.exists())) {
    try {
      await directory.create(recursive: true);
    } catch (e) {
      print("An error occurred while creating the directory: $e");
      throw e;
    }
  }
  return directory;
}

Future<void> deleteDirectoryContentSafely(FileSystem fileSystem, String path) async {
  final directory = fileSystem.directory(path);

  if (!(await directory.exists())) {
    return;
  }

  await for (final fileSystemEntity in directory.list(recursive: false)) {
    final entityType = await fileSystem.type(fileSystemEntity.path, followLinks: false);
    if (entityType == FileSystemEntityType.link) {
      // If the entity is a symbolic link, delete the link itself.
      await fileSystemEntity.delete();
    } else if (entityType == FileSystemEntityType.directory) {
      // If it's a directory (and not a link), delete its contents recursively.
      await deleteDirectoryContentSafely(fileSystem, fileSystemEntity.path);
      await fileSystemEntity.delete();
    } else if (entityType == FileSystemEntityType.file) {
      // If it's a file, delete it.
      await fileSystemEntity.delete();
    }
  }
}

Future<Directory> getLocalEngineRepo({
  required String engineSrcPath,
  required String engine,
  required String repoRootPath,
  required String buildMode,
  required FileSystem fileSystem,
}) async {
  final String engineOutPath = fileSystem.path.join(engineSrcPath, 'out', engine);
  final String abi = _getAbiByLocalEnginePath(engineOutPath);
  await deleteDirectoryContentSafely(fileSystem, repoRootPath);
  final Directory localEngineRepo = await checkAndCreateDirectory(fileSystem, repoRootPath);

  // Original code used temporary directory
  //final Directory localEngineRepo = Directory. (repoRootPath) //fileSystem.systemTempDirectory
  //    .createTempSync('flutter_tool_local_engine_repo.');

  final String artifactVersion = _getLocalArtifactVersion(
    fileSystem.path.join(
      engineOutPath,
      'flutter_embedding_$buildMode.pom',
    ),
    fileSystem,
  );
  for (final String artifact in const <String>['pom', 'jar']) {
    // The Android embedding artifacts.
    _createSymlink(
      fileSystem.path.join(
        engineOutPath,
        'flutter_embedding_$buildMode.$artifact',
      ),
      fileSystem.path.join(
        localEngineRepo.path,
        'io',
        'flutter',
        'flutter_embedding_$buildMode',
        artifactVersion,
        'flutter_embedding_$buildMode-$artifactVersion.$artifact',
      ),
      fileSystem,
    );
    // The engine artifacts (libflutter.so).
    _createSymlink(
      fileSystem.path.join(
        engineOutPath,
        '${abi}_$buildMode.$artifact',
      ),
      fileSystem.path.join(
        localEngineRepo.path,
        'io',
        'flutter',
        '${abi}_$buildMode',
        artifactVersion,
        '${abi}_$buildMode-$artifactVersion.$artifact',
      ),
      fileSystem,
    );
  }
  for (final String artifact in <String>['flutter_embedding_$buildMode', '${abi}_$buildMode']) {
    _createSymlink(
      fileSystem.path.join(
        engineOutPath,
        '$artifact.maven-metadata.xml',
      ),
      fileSystem.path.join(
        localEngineRepo.path,
        'io',
        'flutter',
        artifact,
        'maven-metadata.xml',
      ),
      fileSystem,
    );
  }
  return localEngineRepo;
}

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('engineSrcPath', abbr: 's', help: 'The path to the engine src directory (ex. /engine/src).')
    ..addOption('engine', abbr: 'e', help: 'The name of the engin (ex. android_debug_unopt_arm64)')
    ..addOption('repoRootPath', abbr: 'r', help: 'The path to the maven repo directory.')
    ..addOption('buildMode', abbr: 'b', help: 'TBuild mode, ex. debug or release.');
  final argResults = parser.parse(arguments);

  final String? engineSrcPath = argResults['engineSrcPath'];
  if (engineSrcPath == null) {
    print('Please specify the engine src path using the -e option.');
    io.exit(1);
  }

  final String? engine = argResults['engine'];
  if (engine == null) {
    print('Please specify the engine name using -e option.');
    io.exit(1);
  }

  final String? repoRootPath = argResults['repoRootPath'];
  if (repoRootPath == null) {
    print('Please specify the path to location where maven repository should be created.');
    io.exit(1);
  }

  final String? buildMode = argResults['buildMode'];
  if (buildMode == null) {
    print('Please specify the build mode using the -b option.');
    io.exit(1);
  }

  try {
    final Directory repo = await getLocalEngineRepo(
        engineSrcPath: engineSrcPath,
        engine: engine,
        repoRootPath: repoRootPath,
        buildMode: buildMode,
        fileSystem: LocalFileSystem());
    print('Local engine Maven repository created at: ${repo.path}');
  } catch (e) {
    print('Error: $e');
    io.exit(1);
  }
}
