# Sourced, not run: source tools/maxine-probe/env.sh
# Sets LD_LIBRARY_PATH for the SDK's bundled libraries in this shell only.
# The SDK root is $MAXINE_VFX_ROOT, by default the packaged tree.
#
# With the package installed and MAXINE_VFX_ROOT unset (or equal to the
# package's root), the library path is the package's own
# MAXINE_VFX_LIBRARY_PATH from /usr/share/maxine-vfx/maxine-vfx.env
# (MAXINE_VFX_ENV_FILE names another file, for tests). Otherwise it is built
# from the tree: lib, every features/*/lib (sorted), the bundled CUDA and
# TensorRT.
# shellcheck shell=bash

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    echo "${0##*/}: source this file (source ${0}), do not run it" >&2
    exit 2
fi

_maxine_vfx_env() {
    local file=${MAXINE_VFX_ENV_FILE:-/usr/share/maxine-vfx/maxine-vfx.env}
    local root=${MAXINE_VFX_ROOT:-/opt/nvidia/maxine/videofx}
    local key value file_root='' file_path='' path dir
    if [[ -r $file ]]; then
        # Plain KEY=value lines: read, never sourced.
        while IFS='=' read -r key value; do
            case $key in
                MAXINE_VFX_ROOT) file_root=$value ;;
                MAXINE_VFX_LIBRARY_PATH) file_path=$value ;;
            esac
        done <"$file"
    fi
    if [[ -n $file_path && $root == "$file_root" ]]; then
        path=$file_path
    else
        path=$root/lib
        for dir in "$root"/features/*/lib; do
            [[ -d $dir ]] && path+=:$dir
        done
        path+=:$root/external/cuda/lib:$root/external/tensorrt/lib
    fi
    export LD_LIBRARY_PATH=$path
}
_maxine_vfx_env
unset -f _maxine_vfx_env
