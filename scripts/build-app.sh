#!/bin/bash
# Compila Orbit.app (universal: Apple Silicon + Intel) y crea Orbit.dmg.
# Variables opcionales: VERSION, BUILD, ADAPTER_DIR (carpeta con MediaRemoteAdapter.framework y mediaremote-adapter.pl)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
ADAPTER="${ADAPTER_DIR:-$ROOT/vendor/adapter}"
OUT="$ROOT/build"
APP="$OUT/Orbit.app"

cd "$ROOT"
echo "▸ Compilando Orbit $VERSION ($BUILD)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "▸ Armando Orbit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Orbit" "$APP/Contents/MacOS/Orbit"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

if [ -d "$ADAPTER/MediaRemoteAdapter.framework" ]; then
  echo "▸ Incluyendo el adaptador de música"
  mkdir -p "$APP/Contents/Resources/MediaRemoteAdapter"
  ditto "$ADAPTER/MediaRemoteAdapter.framework" "$APP/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework"
  cp "$ADAPTER/mediaremote-adapter.pl" "$APP/Contents/Resources/MediaRemoteAdapter/"
  [ -f "$ADAPTER/LICENSE" ] && cp "$ADAPTER/LICENSE" "$APP/Contents/Resources/MediaRemoteAdapter/LICENSE"
  codesign --force --sign - "$APP/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework"
else
  echo "⚠︎ No se encontró MediaRemoteAdapter en $ADAPTER: la música no se mostrará."
fi

echo "▸ Firmando (ad hoc)"
codesign --force --sign - --identifier app.orbit.Orbit "$APP"
codesign --verify --verbose=2 "$APP" || true
lipo -info "$APP/Contents/MacOS/Orbit"

echo "▸ Creando Orbit.dmg"
STAGE="$OUT/dmg"
rm -rf "$STAGE" "$OUT/Orbit.dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Orbit.app"
ln -s /Applications "$STAGE/Aplicaciones"
hdiutil create -volname "Orbit" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Orbit.dmg" >/dev/null
rm -rf "$STAGE"
ls -lh "$OUT/Orbit.dmg"
echo "✓ Listo: $OUT/Orbit.dmg"
