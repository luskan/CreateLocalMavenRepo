This app creates a local maven repository which provides a custom built flutter engine. Normal custom flutter engine usage requires you to use command line flutter commands like run, if you use flutter as embedding in your gradle android native application then you usually compile it using gradlew or from Android Studio IDE (which also uses gradlew). 

In this short tutorial I will describe how to use locally build flutter engine in gradle built android application from within android studio.

Code below is based on code from : flutter/packages/flutter_tools/lib/src/android/gradle.dart. What I have changed is that I dont use temporary directory and dont delete repository after this script ends. All the artifacts in maven repo are symbolic links to actual ones in the engine folders, so you can run this script once and then recompile your engine many times.

Example command to create local file maven repository in folder: /Users/marcin/projects/flutter_projects/maven. It will be based on built flutter engine at /Users/marcin/projects/flutter_projects/engine/src, and engine name (at.. ../src/out) is android_debug_unopt_arm64. Build mode is debug:

$ dart create_local_maven_repo -s /Users/marcin/projects/flutter_projects/engine/src -e android_debug_unopt_arm64 -r /Users/marcin/projects/flutter_projects/maven -b debug

Once maven repo is available we can provide it as a gradle parameters. Parameters are taken from below tests:

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

and in command-line options add:

  -Plocal-engine-repo=/Users/marcin/projects/flutter_projects/maven
  -Plocal-engine-build-mode=debug
  -Plocal-engine-out=/Users/marcin/projects/flutter_projects/engine/src/out/android_debug_unopt_arm64
  -Plocal-engine-host-out=/Users/marcin/projects/flutter_projects/engine/src/out/host_debug_unopt
  -Ptarget-platform=android-arm64

For reference I also add a way how I compile my custom engines:

  1. Make sure you have all the required dependencies, like git, python3, depot tools, etc. The list is available here: https://github.com/flutter/flutter/wiki/Setting-up-the-Engine-development-environment
  2. Then you can follow guide at: https://github.com/flutter/flutter/wiki/Compiling-the-engine

  I usually start with forking https://github.com/flutter/engine. Then locally create new folder named : engine. Inside it I create file .gclient with content as example:

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

The "url" points to your forked github repo. And what follows after @ is important. This is the version of engine for which your flutter tools were build. Flutter tools are the ones you can clone from https://github.com/flutter/flutter or download from flutter dev page. This 2e4ba9c6fb499ccd4e81420543783cc7267ae406 is located in flutter/bin/internal/engine.version.

After creating .gclient you can synchronize your folder with flutter - gclient will download any necessary dependencies:

  $ gclient sync

  Then enter src folder and issue command which will configure your engines:

  $ ./flutter/tools/gn --android --android-cpu arm64 --unoptimized
  $ ./flutter/tools/gn --unoptimized

After configuring your engines, start all builds, enter /src/out and call:

  $ find . -mindepth 1 -maxdepth 1 -type d | xargs -n 1 sh -c 'ninja -C $0 || exit 255'

to build all engines, later on you can modify engine files and issue again above command.
    to compile again, next builds should be very quick.
