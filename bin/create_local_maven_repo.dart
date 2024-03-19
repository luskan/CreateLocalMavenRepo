import 'dart:io' as io;

import 'package:create_local_maven_repo/base/common.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:args/args.dart';
import 'package:xml/xml.dart';

/**
    This file creates a local maven repository which provides a custom built
    flutter engine. Normal custom flutter engine usage requires you to use command line
    flutter commands like run, if you use flutter as embedding in your gradle
    android native application then you usually compile it using gradlew or
    from Android Studio. In this short tutorial I will describe how
    to use locally build flutter engine in gradle built android application from
    within android studio.

  Code below is based on code from :
  flutter/packages/flutter_tools/lib/src/android/gradle.dart

    What I have changed is that I dont use temporary directory and dont delete
    repository after this script ends. All the artifacts in maven repo are
    symbolic links to actual ones in the engine folders, so you can run this
    script once and then recompile your engine many times.

  Example command to create local file maven repository in folder: /Users/marcin/projects/flutter_projects/maven
  It will be based on built flutter engine at /Users/marcin/projects/flutter_projects/engine/src, and
  engine name (at.. ../src/out) is android_debug_unopt_arm64. Build mode is debug:

$ dart create_local_maven_repo
  -s /Users/marcin/projects/flutter_projects/engine/src
  -e android_debug_unopt_arm64
  -r /Users/marcin/projects/flutter_projects/maven
  -b debug

   Once maven repo is available we can provide it as a gradle parameters. Parameters
   are taken from below tests

  https://github.com/flutter/flutter/blob/6190c5eea1e1ac38e849ca357eb98b9a41b91263/packages/flutter_tools/test/general.shard/android/android_gradle_builder_test.dart#L1194

  'gradlew',
  '-q',
  '-Plocal-engine-repo=/.tmp_rand0/flutter_tool_local_engine_repo.rand0',
  '-Plocal-engine-build-mode=release',
  '-Plocal-engine-out=out/android_arm',
  '-Plocal-engine-host-out=out/host_release',
  '-Ptarget-platform=android-arm',
  '-Ptarget=lib/main.dart',
  '-Pbase-application-name=io.flutter.app.FlutterApplication',
  '-Pdart-obfuscation=false',
  '-Ptrack-widget-creation=false',
  '-Ptree-shake-icons=false',
  'assembleRelease',

   To apply this parameters in Android Studio, go to settings: Preferences | Build, Execution, Deployment | Gradle-Android Compiler

    and in command-line options add for example:

  -Plocal-engine-repo=/Users/marcin/projects/flutter_projects/maven
  -Plocal-engine-build-mode=debug
  -Plocal-engine-out=/Users/marcin/projects/flutter_projects/engine/src/out/android_debug_unopt_arm64
  -Plocal-engine-host-out=/Users/marcin/projects/flutter_projects/engine/src/out/host_debug_unopt
  -Ptarget-platform=android-arm64

   For reference I also add a way how I compile my custom engines:
    1. Make sure you have all the required dependencies, like git, python3, depot tools, the list is available here:
    https://github.com/flutter/flutter/wiki/Setting-up-the-Engine-development-environment
    2. Then you can follow guide at: https://github.com/flutter/flutter/wiki/Compiling-the-engine

    I usually start with forking https://github.com/flutter/engine. Then locally create new folder named : engine.
    Inside it I create file .gclient with content as example:

    solutions = [
    {
    "managed": False,
    "name": "src/flutter",
    "url": "https://github.com/luskan/engine.git@2e4ba9c6fb499ccd4e81420543783cc7267ae406",
    "custom_deps": {},
    "deps_file": "DEPS",
    "safesync_url": "",
    },
    ]

    the "url" points to your forked github repo. And what follows after @ is important. This is
    the version of engine for which your flutter tools were build. Flutter tools are the ones you can
    clone from https://github.com/flutter/flutter or download from flutter dev page. This
    2e4ba9c6fb499ccd4e81420543783cc7267ae406 is located in flutter/bin/internal/engine.version.

    After creating .gclient you can synchronize your folder with flutter - gclient will download any
    necessary dependencies:

    $ gclient sync

    Then enter src folder and issue command which will configure your engines:

    $ ./flutter/tools/gn --android --android-cpu arm64 --unoptimized
    $ ./flutter/tools/gn --unoptimized

    After configuring your engines, start all builds, enter /src/out and call:

    $ find . -mindepth 1 -maxdepth 1 -type d | xargs -n 1 sh -c 'ninja -C $0 || exit 255'

    to build all engines, later on you can modify engine files and issue again above command
    to compile again, next builds should be very quick.
*/

// from: packages/flutter_tools/lib/src/base/common.dart
Never throwToolExit(String? message, { int? exitCode }) {
  throw ToolExit(message, exitCode: exitCode);
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
