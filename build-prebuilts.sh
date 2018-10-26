#!/bin/bash -ex

# Copyright 2018 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

export LLVM_BUILD_HOST_TOOLS=true
export LLVM_PREBUILTS_VERSION=clang-r339409b
export LLVM_RELEASE_VERSION=8.0.2

# FIXME: Workaround to build bionic versioner in the aosp/clang-tools branch.
export FORCE_BUILD_LLVM_COMPONENTS=true

if [ -z "${OUT_DIR}" ]; then
    echo "error: Must set OUT_DIR"
    exit 1
fi

TOP=$(pwd)

UNAME="$(uname)"
case "${UNAME}" in
Linux)
    OS='linux'
    ;;
Darwin)
    OS='darwin'
    ;;
*)
    echo "error: Unknown uname: ${UNAME}"
    exit 1
    ;;
esac

# Setup Soong configuration
SOONG_OUT="${OUT_DIR}/soong"
SOONG_HOST_OUT="${OUT_DIR}/soong/host/${OS}-x86"
rm -rf "${SOONG_OUT}"
mkdir -p "${SOONG_OUT}"
cat > "${SOONG_OUT}/soong.variables" << __EOF__
{
    "Allow_missing_dependencies": true,
    "HostArch":"x86_64"
}
__EOF__

# Targets to be built
SOONG_BINARIES=(
    "header-abi-linker"
    "header-abi-dumper"
    "header-abi-diff"
    "merge-abi-diff"
    "versioner"
)

binaries=()
for name in "${SOONG_BINARIES[@]}"; do
    binaries+=("${SOONG_HOST_OUT}/bin/${name}")
done

libs=()
if [ "${OS}" = "darwin" ]; then
    libs+=("${SOONG_HOST_OUT}/lib64/libc++abi_host.dylib")
fi

# Build binaries and shared libs
build/soong/soong_ui.bash --make-mode --skip-make "${binaries[@]}" "${libs[@]}"

# Copy binaries and shared libs
mkdir -p "${SOONG_OUT}/dist/bin"
cp "${binaries[@]}" "${SOONG_OUT}/dist/bin/"
cp -R "${SOONG_HOST_OUT}/lib"* "${SOONG_OUT}/dist/"

# Copy clang headers
cp -R "prebuilts/clang/host/${OS}-x86/${LLVM_PREBUILTS_VERSION}/lib64/clang/${LLVM_RELEASE_VERSION}/include" "${SOONG_OUT}/dist/clang-headers"

# Normalize library file names.  All library file names must match their soname.
function extract_soname () {
    local file="$1"

    case "${OS}" in
    linux)
        readelf -d "${file}" | \
            grep '(SONAME)\s*Library soname: \[.*\]$' -o | \
            sed 's/(SONAME)\s*Library soname: \[\(.*\)\]$/\1/g'
        ;;
    darwin)
        local install_path="$(otool -D "${file}" | sed -n 2p)"
        if [ -n "${install_path}" ]; then
            basename "${install_path}"
        fi
        ;;
    esac
}

for file in "${SOONG_OUT}/dist/lib"*"/"*; do
    soname="$(extract_soname "${file}")"
    if [ -n "${soname}" -a "$(basename "${file}")" != "${soname}" ]; then
        mv "${file}" "$(dirname "${file}")/${soname}"
    fi
done

# Package binaries and shared libs
(
    cd "${SOONG_OUT}/dist"
    zip -qryX build-prebuilts.zip *
)

if [ -n "${DIST_DIR}" ]; then
    mkdir -p "${DIST_DIR}" || true
    cp "${SOONG_OUT}/dist/build-prebuilts.zip" "${DIST_DIR}/"
fi
