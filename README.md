# Gentle GPU

Gentle forced alignment with the original HTTP/API and `align.py` interfaces,
rebuilt against a pinned Kaldi revision with ROCm/HIP GPU inference. The image
is published to `ghcr.io/ikatun/gentle-gpu` by GitHub Actions on pushes to
`main` and version tags.

## Run the HTTP service

The container entrypoint is the original `serve.py`; its arguments remain
available directly after the image name:

```sh
docker run --rm --device=/dev/dxg \
  -v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro \
  -v /usr/lib/wsl/drivers:/usr/lib/wsl/drivers:ro \
  -p 8765:8765 \
  -e HSA_ENABLE_DXG_DETECTION=1 \
  -e LD_LIBRARY_PATH=/opt/rocm/lib:/usr/lib/wsl/lib:/usr/lib/wsl/drivers \
  ghcr.io/ikatun/gentle-gpu:main --nthreads 4 --port 8765
```

On WSL, the host must already have working ROCm-through-DXG access and expose
`/dev/dxg`, `/usr/lib/wsl/lib`, and `/usr/lib/wsl/drivers` to Docker. The image
contains ROCm 7.2.1 and the matching `rocdxg-roct` bridge; it needs the host's
DXCore/Windows driver libraries at runtime. The RX 7800 XT/GFX1101 build is the
default. For conventional Linux ROCm hosts, pass the standard devices instead:

```sh
docker run --rm --device=/dev/kfd --device=/dev/dri --group-add video --ipc=host \
  -p 8765:8765 ghcr.io/ikatun/gentle-gpu:main --nthreads 4
```

As in original Gentle, submit audio and transcript to
`POST /transcriptions?async=false` with multipart fields named `audio` and
`transcript`. The `conservative` and `disfluency` form flags, async behavior,
web UI, and JSON output are unchanged.

Gentle's original service options include `--host`, `--port`, `--nthreads`,
`--ntranscriptionthreads`, and `--log`. The original CLI is also included; run
it by overriding the service entrypoint:

```sh
docker run --rm --device=/dev/dxg \
  -v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro \
  -v /usr/lib/wsl/drivers:/usr/lib/wsl/drivers:ro \
  -v "$PWD:/work" \
  -e HSA_ENABLE_DXG_DETECTION=1 \
  -e LD_LIBRARY_PATH=/opt/rocm/lib:/usr/lib/wsl/lib:/usr/lib/wsl/drivers \
  --entrypoint python3 ghcr.io/ikatun/gentle-gpu:main \
  /gentle/align.py --nthreads 4 /work/audio.mp3 /work/transcript.txt \
  --output /work/alignment.json
```

Useful optional environment variables:

- `GENTLE_GPU_MEMORY_PROPORTION` limits Kaldi's GPU allocator reservation
  (valid range 0.05 to less than 0.99); unset preserves Kaldi's default.
- `GENTLE_FRAMES_PER_CHUNK` changes the neural inference batch size.
- `GENTLE_CHUNK_LEN` and `GENTLE_CHUNK_OVERLAP` change Gentle's internal
  audio chunking (defaults remain 20 and 2 seconds).

## Build locally

Clone with the pinned Kaldi submodule and build for the target GPU architecture:

```sh
git clone --recurse-submodules git@github.com:ikatun/gentle-gpu.git
cd gentle-gpu
docker build --build-arg ROCM_TARGETS=gfx1101 -t gentle-gpu:local .
```

Set `KALDI_BUILD_JOBS` as a Docker build argument to tune compile parallelism;
the conservative default is 2. Runtime ROCm access is passed through from the
host and is not bundled as a host driver.
