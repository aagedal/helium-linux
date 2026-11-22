#!/usr/bin/env bash
set -euo pipefail

_current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
_root_dir="$(cd "$_current_dir/.." && pwd)"
_build_dir="$_root_dir/build"
_release_dir="$_build_dir/release"
_app_dir="$_release_dir/HeliumNeo.AppDir"

_app_name="helium-neo"
_version=$(python3 "$_root_dir/helium-chromium/utils/helium_version.py" \
                   --tree "$_root_dir/helium-chromium" \
                   --platform-tree "$_root_dir" \
                   --print)

_arch=$(cat "$_build_dir/src/out/Default/args.gn" \
                | grep ^target_cpu \
                | tail -1 \
                | sed 's/.*=//' \
                | cut -d'"' -f2)

if [ "$_arch" = "x64" ]; then
    _arch="x86_64"
fi

# Matches the macOS DMG naming used by the Homebrew cask. The archive holds a
# fixed helium-neo/ directory so installed paths stay stable across versions.
_release_name="Helium-Neo-$_version-linux-$_arch"
_tarball_name="$_app_name"
_tarball_dir="$_release_dir/$_tarball_name"

_files="helium
chrome_100_percent.pak
chrome_200_percent.pak
helium_crashpad_handler
chromedriver
hyphen-data
icudtl.dat
libEGL.so
libGLESv2.so
libqt5_shim.so
libqt6_shim.so
libvk_swiftshader.so
libvulkan.so.1
product_logo_256.png
resources.pak
v8_context_snapshot.bin
vk_swiftshader_icd.json
xdg-mime
xdg-settings"

echo "copying release files and creating $_release_name.tar.xz"

rm -rf "$_tarball_dir"
mkdir -p "$_tarball_dir"

for file in $_files; do
    cp -r "$_build_dir/src/out/Default/$file" "$_tarball_dir" &
done

mkdir -p "$_tarball_dir/locales"
cp "$_build_dir/src/out/Default/locales/"*.pak "$_tarball_dir/locales/"

cp "$_root_dir/package/helium-neo.desktop" "$_tarball_dir"
cp "$_root_dir/package/apparmor.cfg" "$_tarball_dir"
cp "$_root_dir/package/helium-wrapper.sh" "$_tarball_dir/helium-wrapper"

wait
(cd "$_tarball_dir" && ln -sf helium chrome && ln -sf helium-wrapper helium-neo)

_syms_zip="$_release_dir/${_release_name}_symbols.zip"
rm -f "$_syms_zip"
find "$_tarball_dir" -type f -exec file {} + \
    | awk -F: '/ELF/ {print $1}' \
    | sed "s|^$_tarball_dir/||" \
    | (cd "$_build_dir/src/out/Default" && zip -q "$_syms_zip" -@)

if command -v eu-strip >/dev/null 2>&1; then
    _strip_cmd=eu-strip
else
    _strip_cmd="strip --strip-unneeded"
fi

find "$_tarball_dir" -type f -exec file {} + \
    | awk -F: '/ELF/ {print $1}' \
    | xargs $_strip_cmd

_size="$(du -sk "$_tarball_dir" | cut -f1)"

pushd "$_release_dir"

TAR_PATH="$_release_dir/$_release_name.tar.xz"
if command -v pv >/dev/null 2>&1; then
    tar vcf - "$_tarball_name" | pv -s"${_size}k" | xz -e9 > "$TAR_PATH" &
else
    tar cf - "$_tarball_name" | xz -T0 -6 > "$TAR_PATH" &
fi

# create AppImage
rm -rf "$_app_dir"
mkdir -p "$_app_dir/opt/helium-neo/" "$_app_dir/usr/share/icons/hicolor/256x256/apps/"
cp -r "$_tarball_dir"/* "$_app_dir/opt/helium-neo/"
cp "$_root_dir/package/helium-neo.desktop" "$_app_dir"

cp "$_root_dir/package/helium-wrapper-appimage.sh" "$_app_dir/AppRun"

for out in "$_app_dir/helium-neo.png" "${_app_dir}/usr/share/icons/hicolor/256x256/apps/helium-neo.png"; do
    cp "${_app_dir}/opt/helium-neo/product_logo_256.png" "$out"
done

export APPIMAGETOOL_APP_NAME="Helium Neo"
export VERSION="$_version"

# check whether CI GPG secrets are available
if [[ -n "${GPG_PRIVATE_KEY:-}" && -n "${GPG_PASSPHRASE:-}" ]]; then
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import --passphrase "$GPG_PASSPHRASE"
    export APPIMAGETOOL_SIGN_PASSPHRASE="$GPG_PASSPHRASE"
fi

if command -v appimagetool >/dev/null 2>&1; then
    appimagetool "$_app_dir" "$_release_name.AppImage" "$@" &
else
    echo "appimagetool not found; skipping AppImage" >&2
fi
popd
wait

if [ "${MAKE_DEB:-0}" = 1 ]; then
    "$_root_dir/package/mkdeb.sh" "$TAR_PATH"
fi

if [ -n "${SIGN_TARBALL:-}" ]; then
    gpg --batch --pinentry-mode loopback \
        --detach-sign --passphrase "$GPG_PASSPHRASE" \
        --output "$TAR_PATH.asc" "$TAR_PATH"
fi

rm -rf "$_tarball_dir" "$_app_dir"
