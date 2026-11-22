#!/usr/bin/env bash
# Helium Neo local development build steps, run inside the builder container.
#   neo-local.sh prepare   download, patch and configure the source tree
#   neo-local.sh gn        regenerate build files only
#   neo-local.sh build     compile (extra args go to autoninja)
#   neo-local.sh package   create the tarball and AppImage
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"

setup_environment

write_local_gn_args() {
    write_gn_args
    # Local development overrides: no LTO/CFI, no symbols, smaller output.
    sed -i -e '/^is_official_build=/d' -e '/^symbol_level=/d' "${_out_dir}/args.gn"
    cat >> "${_out_dir}/args.gn" <<'EOF'
is_official_build=false
symbol_level=0
v8_symbol_level=0
EOF
}

step="${1:-}"
shift || true

case "$step" in
    prepare)
        fetch_sources false false
        apply_patches
        apply_domsub
        if [ ! -f "${_src_dir}/.namesubs.stamp" ]; then
            helium_substitution
            touch "${_src_dir}/.namesubs.stamp"
        fi
        helium_apply_translations
        helium_version
        helium_resources
        write_local_gn_args
        gn_gen
        ;;
    gn)
        write_local_gn_args
        gn_gen
        ;;
    build)
        build "$@"
        ;;
    package)
        bash "${_root_dir}/scripts/package.sh" "$@"
        ;;
    shell)
        cd "${_src_dir}" 2>/dev/null || cd "${_root_dir}"
        exec bash
        ;;
    *)
        echo "usage: $0 prepare|gn|build|package|shell" >&2
        exit 1
        ;;
esac
