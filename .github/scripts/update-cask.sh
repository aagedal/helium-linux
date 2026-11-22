#!/bin/bash
# Fill in the Linux checksums of the helium-neo cask in aagedal/homebrew-tap.
#   update-cask.sh <release tag> <directory with the release tarballs>
set -euo pipefail

_tag="$1"
_assets="$(cd "$2" && pwd)"
_version="${_tag#v}"
_version="${_version%-neo}"
_cask="Casks/helium-neo.rb"
_tap="$(mktemp -d)"

git clone --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/aagedal/homebrew-tap.git" "$_tap"
cd "$_tap"

if ! grep -q "^  version \"$_version\"$" "$_cask"; then
    echo "::notice::Cask is not at version $_version; leaving it unchanged"
    exit 0
fi
if ! grep -q 'arm64_linux:' "$_cask"; then
    echo "::notice::Cask has no Linux checksums; leaving it unchanged"
    exit 0
fi

for arch in arm64 x86_64; do
    sha="$(sha256sum "$_assets/Helium-Neo-$_version-linux-$arch.tar.xz" | cut -d' ' -f1)"
    sed -Ei "s/(${arch}_linux: +\")[0-9a-f]{64}/\1$sha/" "$_cask"
done

if git diff --quiet; then
    echo "Cask checksums already up to date"
    exit 0
fi

git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -am "helium-neo: add Linux checksums for $_version"
git push
