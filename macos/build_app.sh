#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Nabira"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
# Universal-сборка кладёт продукт сюда (а не в .build/release)
BUILD_DIR="$PROJECT_DIR/.build/apple/Products/Release"
# version.json живёт в КОРНЕ репозитория (живой фид обновлений) — не переносить!
# NABIRA_VERSION_JSON переопределяет источник версии (для бета-сборок → version-beta.json).
VERSION_JSON="${NABIRA_VERSION_JSON:-$PROJECT_DIR/../version.json}"

# version.json — единый источник правды. Значения в Info.plist в репо
# игнорируются: скрипт штампует CFBundleShortVersionString и CFBundleVersion
# в копию Info.plist внутри собранного бандла.
SHORT_VERSION=$(/usr/bin/python3 -c "import json,sys;print(json.load(open('$VERSION_JSON'))['version'])")
BUILD_VERSION=$(/usr/bin/python3 -c "import json,sys;print(json.load(open('$VERSION_JSON')).get('build','1'))")
DEV_TAG=$(/usr/bin/python3 -c "import json,sys;print(json.load(open('$VERSION_JSON')).get('dev',''))")

if [ -z "$SHORT_VERSION" ]; then
    echo "ERROR: could not read version from $VERSION_JSON"
    exit 1
fi

echo "=== Building $APP_NAME v$SHORT_VERSION (build $BUILD_VERSION) ==="

# Optional local AI uses ONNX Runtime, but the 251 MB language model is deliberately NOT
# bundled and is downloaded only after an explicit click in Settings. The signed runtime and
# a tiny persistent helper are bundled so a connected model works on both Apple Silicon and Intel.
ORT_VERSION="1.23.2"
ORT_SHA256="49ae8e3a66ccb18d98ad3fe7f5906b6d7887df8a5edd40f49eb2b14e20885809"
ORT_ROOT="$PROJECT_DIR/.build/onnxruntime-$ORT_VERSION"
ORT_ARCHIVE="$PROJECT_DIR/.build/onnxruntime-osx-universal2-$ORT_VERSION.tgz"
if [ ! -f "$ORT_ROOT/lib/libonnxruntime.1.23.2.dylib" ]; then
    echo "→ Downloading pinned ONNX Runtime $ORT_VERSION..."
    mkdir -p "$PROJECT_DIR/.build"
    curl -fL --retry 3 -o "$ORT_ARCHIVE.tmp" \
        "https://github.com/microsoft/onnxruntime/releases/download/v$ORT_VERSION/onnxruntime-osx-universal2-$ORT_VERSION.tgz"
    ACTUAL_ORT_SHA=$(shasum -a 256 "$ORT_ARCHIVE.tmp" | awk '{print $1}')
    if [ "$ACTUAL_ORT_SHA" != "$ORT_SHA256" ]; then
        echo "ERROR: ONNX Runtime checksum mismatch." >&2
        exit 1
    fi
    mv "$ORT_ARCHIVE.tmp" "$ORT_ARCHIVE"
    mkdir -p "$ORT_ROOT.extract"
    tar -xzf "$ORT_ARCHIVE" -C "$ORT_ROOT.extract"
    mv "$ORT_ROOT.extract/onnxruntime-osx-universal2-$ORT_VERSION" "$ORT_ROOT"
    rmdir "$ORT_ROOT.extract"
fi

echo "→ Building local AI helper (universal)..."
clang++ -std=c++17 -O3 -arch arm64 -arch x86_64 \
    -I "$ORT_ROOT/include" \
    "$PROJECT_DIR/SageHelper/main.cpp" \
    -L "$ORT_ROOT/lib" -lonnxruntime \
    -Wl,-rpath,@loader_path/../Frameworks \
    -o "$PROJECT_DIR/.build/NabiraSageHelper"

# 1. Собираем release — universal (arm64 + x86_64), чтобы работало и на Intel-маках
echo "→ swift build -c release --arch arm64 --arch x86_64 (universal)..."
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64

# 2. Создаём .app bundle
echo "→ Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Helpers"

# 3. Копируем бинарник
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/.build/NabiraSageHelper" "$APP_BUNDLE/Contents/Helpers/NabiraSageHelper"
cp "$ORT_ROOT/lib/libonnxruntime.1.23.2.dylib" "$APP_BUNDLE/Contents/Frameworks/"
ln -s "libonnxruntime.1.23.2.dylib" "$APP_BUNDLE/Contents/Frameworks/libonnxruntime.dylib"

# SwiftPM кладёт обработанные ресурсы executable target в отдельный bundle.
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    echo "ERROR: resource bundle not found: $RESOURCE_BUNDLE"
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

# 3a. Самопроверка: бинарь обязан быть universal (arm64 + x86_64), иначе Intel-маки не запустят
ARCHS=$(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
    echo "ERROR: бинарь не universal (получено: $ARCHS)"; exit 1
fi
echo "→ Universal OK: $ARCHS"
HELPER_ARCHS=$(lipo -archs "$APP_BUNDLE/Contents/Helpers/NabiraSageHelper")
if [[ "$HELPER_ARCHS" != *"arm64"* || "$HELPER_ARCHS" != *"x86_64"* ]]; then
    echo "ERROR: AI helper is not universal (got: $HELPER_ARCHS)"; exit 1
fi

# 4. Копируем Info.plist и штампуем версию из version.json
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$APP_BUNDLE/Contents/Info.plist"
# Dev-метка (буква) для непубликуемых сборок — пусто для релиза. Показывается в About/меню.
/usr/libexec/PlistBuddy -c "Set :NabiraDevTag $DEV_TAG" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :NabiraDevTag string $DEV_TAG" "$APP_BUNDLE/Contents/Info.plist"
echo "→ Stamped Info.plist: CFBundleShortVersionString=$SHORT_VERSION$DEV_TAG CFBundleVersion=$BUILD_VERSION"

# 5. Копируем брендированную иконку Nabira. Имя executable намеренно остаётся Nabira.
cp "$PROJECT_DIR/Nabira.icns" "$APP_BUNDLE/Contents/Resources/Nabira.icns"

# 6. Создаём PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 7. Стабильная подпись. Приоритет:
#    1) явный NABIRA_SIGN_ID (CI может намеренно передать "-" для ad-hoc);
#    2) постоянный локальный сертификат Nabira Local Development.
# Не откатываемся в ad-hoc молча: новый CDHash после каждой сборки сбрасывает TCC.
LOCAL_SIGN_ID="Nabira Local Development"
identity_exists() {
    security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$1\"" >/dev/null
}

if [ -n "${NABIRA_SIGN_ID+x}" ]; then
    SIGN_ID="$NABIRA_SIGN_ID"
elif identity_exists "$LOCAL_SIGN_ID"; then
    SIGN_ID="$LOCAL_SIGN_ID"
else
    echo "ERROR: no stable code-signing identity found." >&2
    echo "Install the local identity 'Nabira Local Development' first." >&2
    echo "For an intentional CI ad-hoc build use: NABIRA_SIGN_ID=- ./build_app.sh" >&2
    exit 1
fi

echo "→ Code signing with: $SIGN_ID"
# Hardened Runtime validates that every loaded library belongs to the same Apple
# development team. Ad-hoc and our self-signed local identity do not have a Team ID,
# so enabling it makes the separately launched SAGE helper reject ONNX Runtime at
# startup. Keep Hardened Runtime for real Apple identities, and use ordinary code
# signing for local development builds.
SIGN_OPTIONS=()
if [ "$SIGN_ID" != "-" ] && [ "$SIGN_ID" != "$LOCAL_SIGN_ID" ]; then
    SIGN_OPTIONS=(--options runtime)
fi
# Sign nested code first, then seal the outer bundle.
codesign --force --sign "$SIGN_ID" "${SIGN_OPTIONS[@]}" "$APP_BUNDLE/Contents/Frameworks/libonnxruntime.1.23.2.dylib"
codesign --force --sign "$SIGN_ID" "${SIGN_OPTIONS[@]}" "$APP_BUNDLE/Contents/Helpers/NabiraSageHelper"
codesign --force --deep --sign "$SIGN_ID" \
    "${SIGN_OPTIONS[@]}" \
    --entitlements "$PROJECT_DIR/Nabira.entitlements" \
    "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"

# No arguments is the helper's documented usage error (64). Any other status here
# means it could not even start, most commonly because its bundled ONNX Runtime was
# rejected by dyld or signed incorrectly.
set +e
"$APP_BUNDLE/Contents/Helpers/NabiraSageHelper" >/dev/null 2>&1
SAGE_SMOKE_STATUS=$?
set -e
if [ "$SAGE_SMOKE_STATUS" -ne 64 ]; then
    echo "ERROR: local AI helper failed its startup smoke test (status $SAGE_SMOKE_STATUS)." >&2
    exit 1
fi
echo "→ Local AI helper startup smoke test passed"

echo ""
echo "=== Done! ==="
echo "App bundle: $APP_BUNDLE"
echo "Signed with: $SIGN_ID"
echo ""
echo "To install:"
echo "  cp -R $APP_BUNDLE /Applications/"
