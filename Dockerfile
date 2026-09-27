ARG ROCM_VERSION=7.2.1

# The complete toolchain is isolated in the build stage; the published image
# starts from AMD's substantially smaller ROCm development/runtime base.
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION}-complete AS build

ARG ROCM_VERSION
ARG ROCM_TARGETS=gfx1101
ARG KALDI_BUILD_JOBS=2

ENV DEBIAN_FRONTEND=noninteractive \
    ROCM_PATH=/opt/rocm \
    HSA_ENABLE_DXG_DETECTION=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf automake build-essential ca-certificates curl gfortran git \
      libatlas-base-dev libatlas3-base libtool python3 python3-dev \
      python3-pip python3-setuptools python3-wheel sox subversion unzip wget zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /gentle
COPY . /gentle

# Build only the OpenFST dependency and Kaldi static libraries used by k3/m3;
# no training binaries or Kaldi test executables are shipped in the image.
RUN grep -qx 'e02e35f0254bb033fab73d1df99fc34123e31d56' ext/KALDI_REVISION \
    && KALDI_ONLY=1 ROCM_TARGETS="${ROCM_TARGETS}" KALDI_BUILD_JOBS="${KALDI_BUILD_JOBS}" ./ext/install_kaldi_rocm.sh

RUN make -C /gentle/ext -j"${KALDI_BUILD_JOBS}" ROCM=true \
    && ./install_models.sh \
    && rm -rf /gentle/ext/kaldi /root/.cache/pip /var/lib/apt/lists/*

FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION} AS runtime

ARG ROCM_VERSION

LABEL org.opencontainers.image.source="https://github.com/ikatun/gentle-gpu" \
      org.opencontainers.image.description="Gentle forced aligner with Kaldi ROCm GPU support"

ENV DEBIAN_FRONTEND=noninteractive \
    ROCM_PATH=/opt/rocm \
    HSA_ENABLE_DXG_DETECTION=1 \
    PYTHONUNBUFFERED=1

# Install the runtime libraries linked by Kaldi, Gentle's media/Python runtime,
# and the ROCDXG shim. Its SHA is pinned to the matching ROCm 7.2.1 WSL release.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl ffmpeg libatlas3-base python3 python3-pip \
      hipblas hipsparse hipsolver hiprand hipfft rocblas rocsparse rocsolver rocrand \
    && curl -fsSL "https://github.com/ROCm/librocdxg/releases/download/v1.2.1/rocdxg-roct_1.2.1_amd64.deb" \
      -o /tmp/rocdxg-roct.deb \
    && echo "7889eef45a1132ed2dde88d8ea1356bf791ec9c05802a18940bc81b970e850e0  /tmp/rocdxg-roct.deb" | sha256sum -c - \
    && apt-get install -y --no-install-recommends /tmp/rocdxg-roct.deb \
    && rm -f /tmp/rocdxg-roct.deb \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && ldconfig

WORKDIR /gentle
COPY --from=build /gentle /gentle
RUN python3 -m pip install --break-system-packages --no-cache-dir .

EXPOSE 8765
VOLUME ["/gentle/webdata"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/', timeout=3)" || exit 1

# Original serve.py options are passed directly, e.g. IMAGE --port 9000.
ENTRYPOINT ["python3", "/gentle/serve.py"]
