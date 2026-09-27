#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kaldi_dir="${repo_root}/ext/kaldi"
rocm_path="${ROCM_PATH:-/opt/rocm}"
rocm_targets="${ROCM_TARGETS:-gfx1101}"
jobs="${KALDI_BUILD_JOBS:-2}"

if [[ "${jobs}" -lt 1 ]]; then
  echo "KALDI_BUILD_JOBS must be a positive integer" >&2
  exit 2
fi
if [[ "$(cat "${repo_root}/ext/KALDI_REVISION")" != "e02e35f0254bb033fab73d1df99fc34123e31d56" ]]; then
  echo "Unexpected Kaldi revision; expected e02e35f0254bb033fab73d1df99fc34123e31d56" >&2
  exit 2
fi

patch_file="${repo_root}/ext/kaldi-rocm-7.2.1.patch"
if patch --dry-run --reverse -p1 -d "${kaldi_dir}" < "${patch_file}" >/dev/null 2>&1; then
  echo "ROCm compatibility patch already applied"
else
  patch --dry-run -p1 -d "${kaldi_dir}" < "${patch_file}"
  patch -p1 -d "${kaldi_dir}" < "${patch_file}"
fi

mkdir -p "${kaldi_dir}/tools/python"
openfst_archive="${kaldi_dir}/tools/openfst-1.8.4.tar.gz"
openfst_source="${kaldi_dir}/tools/openfst-1.8.4"
openfst_commit="584122adc2725cce7c75992e1272d98347a3931b"
openfst_sha256="abf2beed0358aedf7025945e37bc7954ca50ba4f1876a102501651b3b07c0021"
curl -fsSL --retry 3 \
  "https://codeload.github.com/google-research/openfst/tar.gz/${openfst_commit}" \
  -o "${openfst_archive}"
echo "${openfst_sha256}  ${openfst_archive}" | sha256sum -c -
mkdir -p "${openfst_source}"
tar -xzf "${openfst_archive}" --strip-components=1 -C "${openfst_source}"
(cd "${openfst_source}" && autoreconf --force --install)
# Kaldi's Makefile checks this directory against the archive prerequisite.
touch "${openfst_source}"
make -C "${kaldi_dir}/tools" -j"${jobs}" openfst
cd "${kaldi_dir}/src"
./configure --static --static-math=yes --static-fst=yes \
  --use-rocm --rocm-dir="${rocm_path}" --rocm-targets="${rocm_targets}" \
  --with-cudadecoder=no --mathlib=ATLAS \
  --atlas-root="${kaldi_dir}/tools/ATLAS_headers"
EXTRA_ROCM_FLAGS="-std=c++17 -D__GFX11__=1" make depend
EXTRA_ROCM_FLAGS="-std=c++17 -D__GFX11__=1" make -j"${jobs}" libs

if [[ "${KALDI_ONLY:-0}" != "1" ]]; then
  make -C "${repo_root}/ext" -j"${jobs}" ROCM=true
fi

echo "Kaldi ROCm build complete: target(s) ${rocm_targets}"
