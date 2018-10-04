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
)

binaries=()
for name in "${SOONG_BINARIES[@]}"; do
    binaries+=("${SOONG_HOST_OUT}/bin/${name}")
done

# Build binaries and shared libs
build/soong/soong_ui.bash --make-mode --skip-make "${binaries[@]}"

# Copy binaries and shared libs
mkdir -p "${SOONG_OUT}/dist/bin"
cp "${binaries[@]}" "${SOONG_OUT}/dist/bin/"
cp -R "${SOONG_HOST_OUT}/lib"* "${SOONG_OUT}/dist/"

# Copy clang headers
cp -R "external/clang/lib/Headers" "${SOONG_OUT}/dist/clang-headers"

# Package binaries and shared libs
(
    cd "${SOONG_OUT}/dist"
    zip -qryX build-prebuilts.zip *
)

if [ -n "${DIST_DIR}" ]; then
    mkdir -p "${DIST_DIR}" || true
    cp "${SOONG_OUT}/dist/build-prebuilts.zip" "${DIST_DIR}/"
fi
