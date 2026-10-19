#!/usr/bin/env bash
# Build (and optionally install) the launcher APK using the Android SDK tools directly.
# Gradle is deliberately not used: the app has no dependencies, so javac + d8 + aapt2 is
# enough, and it avoids a multi-hundred-MB Gradle/AGP download.
#
# Usage: scripts/build.sh [--install]
#   --install   install on the TV and make it the default home screen
#
# Env: ANDROID_SDK (default: Homebrew android-commandlinetools), JAVA_HOME (default: Homebrew openjdk@17),
#      TV_ADDR (optional when exactly one TV is connected to adb)
set -euo pipefail

ANDROID_SDK="${ANDROID_SDK:-/opt/homebrew/share/android-commandlinetools}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-36.0.0}"
PLATFORM_VERSION="${PLATFORM_VERSION:-android-36}"
MIN_SDK=28           # TV's first_api_level; Android 9
TARGET_SDK=30        # TV runs Android 11
PACKAGE_NAME="com.litelauncher.tv"
HOME_ACTIVITY="$PACKAGE_NAME/.HomeActivity"

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$project_dir/launcher"
build_dir="$project_dir/build"
build_tools="$ANDROID_SDK/build-tools/$BUILD_TOOLS_VERSION"
android_jar="$ANDROID_SDK/platforms/$PLATFORM_VERSION/android.jar"
keystore="${KEYSTORE:-$HOME/.android/debug.keystore}"
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"

for required_path in "$build_tools/aapt2" "$build_tools/d8" "$build_tools/apksigner" "$android_jar" "$JAVA_HOME/bin/javac"; do
  [[ -e "$required_path" ]] || { echo "ERROR: missing $required_path" >&2; exit 1; }
done

rm -rf "$build_dir"
mkdir -p "$build_dir"/{compiled-res,gen,classes,dex}

echo "==> Compiling resources"
"$build_tools/aapt2" compile --dir "$source_dir/res" -o "$build_dir/compiled-res/resources.zip"
"$build_tools/aapt2" link \
  -I "$android_jar" \
  --manifest "$source_dir/AndroidManifest.xml" \
  --min-sdk-version "$MIN_SDK" \
  --target-sdk-version "$TARGET_SDK" \
  --java "$build_dir/gen" \
  -o "$build_dir/unsigned.apk" \
  "$build_dir/compiled-res/resources.zip"

echo "==> Compiling Java"
find "$source_dir/src" "$build_dir/gen" -name '*.java' > "$build_dir/java-sources.txt"
javac --release 11 -Xlint:deprecation -classpath "$android_jar" -d "$build_dir/classes" @"$build_dir/java-sources.txt"

echo "==> Dexing"
find "$build_dir/classes" -name '*.class' > "$build_dir/class-files.txt"
"$build_tools/d8" --release --min-api "$MIN_SDK" --lib "$android_jar" --output "$build_dir/dex" @"$build_dir/class-files.txt"
(cd "$build_dir/dex" && zip -q -j "$build_dir/unsigned.apk" classes.dex)

echo "==> Aligning and signing"
if [[ ! -f "$keystore" ]]; then
  mkdir -p "$(dirname "$keystore")"
  # Standard Android debug keystore (well-known password "android"); not for Play Store releases
  keytool -genkeypair -keystore "$keystore" -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi
"$build_tools/zipalign" -f -p 4 "$build_dir/unsigned.apk" "$build_dir/aligned.apk"
"$build_tools/apksigner" sign --ks "$keystore" --ks-pass pass:android --key-pass pass:android \
  --out "$build_dir/light-tv-launcher.apk" "$build_dir/aligned.apk"
echo "Built $build_dir/light-tv-launcher.apk ($(du -h "$build_dir/light-tv-launcher.apk" | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
  # shellcheck source=lib/tv.sh
  source "$(dirname "$0")/lib/tv.sh"
  resolve_tv_addr
  echo "==> Installing on $TV_ADDR"
  # The TV rejects incremental installs; skip straight to a streamed install
  adb -s "$TV_ADDR" install -r --no-incremental "$build_dir/light-tv-launcher.apk"
  adb -s "$TV_ADDR" shell cmd package set-home-activity "$HOME_ACTIVITY" >/dev/null
  adb -s "$TV_ADDR" shell cmd role add-role-holder android.app.role.HOME "$PACKAGE_NAME" 0
  current_home="$(adb -s "$TV_ADDR" shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1 | tr -d '\r')"
  if [[ "$current_home" == "$HOME_ACTIVITY" ]]; then
    adb -s "$TV_ADDR" shell input keyevent KEYCODE_HOME
    echo "Light TV Launcher is the default home screen"
  else
    # The stock launcher's HOME filter has priority 2, which Android picks over any user
    # preference; third-party apps can't declare >0, so the stock one must be disabled
    echo "Installed, but '$current_home' still outranks it."
    echo "Run scripts/debloat.sh apply to disable the stock launcher so Light TV Launcher takes over."
  fi
fi
