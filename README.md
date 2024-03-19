# Custom Flutter Engine Maven Repository for Android

This application facilitates the creation of a local Maven repository, hosting a custom-built Flutter engine. Typically, using a custom Flutter engine requires command-line Flutter commands like `flutter run`. However, if you're embedding Flutter within an Android native application via Gradle, the process usually involves compiling with `gradlew` or from the Android Studio IDE.

## Tutorial: Using a Locally Built Flutter Engine in a Gradle-Built Android Application

This tutorial outlines the process of integrating a locally built Flutter engine into a Gradle-built Android application, directly from Android Studio.

### Modifications to Original Flutter Code

The approach described here is based on the code from `flutter/packages/flutter_tools/lib/src/android/gradle.dart`. Key modifications include:
- Avoiding the use of a temporary directory.
- Not deleting the repository after the script's execution.

All Maven repository artifacts are symbolic links to the actual files in the engine folders, allowing you to run this script once and recompile your engine multiple times without repetition.

### Creating a Local File Maven Repository

To create a local file Maven repository in a designated folder, use the following command:

```shell
$ dart create_local_maven_repo -s /path/to/engine/src -e engine_name -r /path/to/maven/repo -b build_mode
```

- Replace `/path/to/engine/src` with the path to your built Flutter engine source.
- Replace `engine_name` with the name of your engine (e.g., `android_debug_unopt_arm64`).
- Replace `/path/to/maven/repo` with the path where you want to create the Maven repository.
- Replace `build_mode` with your desired build mode (e.g., `debug`).

### Example Command

```shell
$ dart create_local_maven_repo -s /Users/marcin/projects/flutter_projects/engine/src -e android_debug_unopt_arm64 -r /Users/marcin/projects/flutter_projects/maven -b debug
```

### Integrating Maven Repository with Gradle

Once the Maven repository is set up, you can provide it as a Gradle parameter. These parameters are derived from tests found [here](https://github.com/flutter/flutter/blob/6190c5eea1e1ac38e849ca357eb98b9a41b91263/packages/flutter_tools/test/general.shard/android/android_gradle_builder_test.dart#L1194).

To apply these parameters in Android Studio, navigate to:

**Preferences | Build, Execution, Deployment | Gradle-Android Compiler**

And in the command-line options, add the following:

```shell
-Plocal-engine-repo=/path/to/maven
-Plocal-engine-build-mode=debug
-Plocal-engine-out=/path/to/engine/src/out/android_debug_unopt_arm64
-Plocal-engine-host-out=/path/to/engine/src/out/host_debug_unopt
-Ptarget-platform=android-arm64
```

Replace the paths accordingly to match your setup.

This setup was tested only on macos.

### Compiling Custom Engines

1. **Dependencies**: Ensure you have all necessary dependencies (git, python3, depot tools, etc.). A comprehensive list is available [here](https://github.com/flutter/flutter/wiki/Setting-up-the-Engine-development-environment).
2. **Guide**: Follow the guide on [Compiling the Engine](https://github.com/flutter/flutter/wiki/Compiling-the-engine).

Start by forking the [Flutter engine repository](https://github.com/flutter/engine) and setting up your `.gclient` file to point to your fork. The `url` in your `.gclient` should link to your GitHub repo, and the version hash should match the engine version your Flutter tools were built for.

Example .gclient should look as follows:

```shell
 solutions = [
    {
    "managed": False,
    "name": "src/flutter",
    "url": "https://github.com/[YOUR_USERNAME]/engine.git@2e4ba9c6fb499ccd4e81420543783cc7267ae406",
    "custom_deps": {},
    "deps_file": "DEPS",
    "safesync_url": "",
    },
    ]
```
@2e4ba9c6fb499ccd4e81420543783cc7267ae406 checksout the correct version of engine - same as the one for which your flutter tools were created (check flutter/bin/internal/engine.version).

After creating .gclient you can synchronize your folder with flutter - gclient will download any necessary dependencies:

```shell
$ gclient sync
```

Then enter src folder and issue command which will configure your engines:

```shell
$ ./flutter/tools/gn --android --android-cpu arm64 --unoptimized
$ ./flutter/tools/gn --unoptimized
```

After configuring your engines, start all builds, enter /src/out and call:

```shell
$ find . -mindepth 1 -maxdepth 1 -type d | xargs -n 1 sh -c 'ninja -C $0 || exit 255'
```

to build all engines, later on you can modify engine files and issue again above command to compile again, next builds should be very quick.
