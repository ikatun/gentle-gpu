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
