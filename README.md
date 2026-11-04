<h1 align="center">Restreamer</h1>
<h3 align="center">A really nice and free alternative for handling live streams.</h3>
<p align="center">
<a href="https://github.com/datarhei/restreamer/blob/2.x/LICENSE" target="_blank"><img src="https://img.shields.io/github/license/datarhei/restreamer" alt="License" /></a>
<a href="https://github.com/datarhei/restreamer/releases" target="_blank"><img src="https://img.shields.io/github/v/release/datarhei/restreamer?include_prereleases" alt="License" /></a>
<a href="https://hub.docker.com/r/datarhei/restreamer" target="_blank"><img src="https://img.shields.io/docker/pulls/datarhei/restreamer" alt="Docker pulls" /></a>
<a href="https://docs.datarhei.com/restreamer/getting-started/quick-start" target="_blank"><img src="https://img.shields.io/badge/documentation-get%20started-green" alt="Documentation" /></a>
</p>
<p align="center"><a href="https://demo.datarhei.com/ui" target="_blank">Try live demo</a><br />
<a href="https://demo.datarhei.com/ui" target="_blank"><img src="https://img.shields.io/badge/username-admin-blue" alt="demo username" /></a>
<a href="https://demo.datarhei.com/ui" target="_blank"><img src="https://img.shields.io/badge/password-demo-blue" alt="demo password" /></a>

<p align="center">
  <a href="https://datarhei.com">
    <img src="https://github.com/datarhei/restreamer/blob/2.x/readme-promo.gif" alt="Restreamer Promo Video" />
  </a>
</p>

<p align="center">Self-hosting solution to stream live to your website and publish to many like YouTube-Live, Twitter, Twitch, Vimeo, and other platforms or services. Our Docker-Image is easy to install and runs on Linux environments (MacOS/Windows by Docker Desktop). Moreover, combine the Restreamer with single-board computers like Raspberry Pi or GPU powered systems for Video-Encoding.</p>
<br />
<hr />

## Features

- Simplified User-Interface
- Easy wizard configuration
- Multiple audio/video inputs, outputs, protocols, and codecs
- ReStreaming to platforms such as YouTube-Live, to software such as Wowza Media Server, and others based on protocols such as RTMP, SRT, ...
- Option to mux a separate audio channel to the video
- Build-in VideoJS-Player for your Website
- Configurable publication website for streaming without player embedding
- Content license with Creative Commons
- HTTP/S- (HLS), RTMP/S- & SRT-Streaming Server
- Automatic Let's Encrypt HTTPS certification
- Viewer/Bandwidth Monitoring and limiting
- Raspberry Pi (MMAL/OMX), Nvidia Cuda, Intel VAAPI support
- Support for Hardware- and Virtual-Devices
- FFmpeg Video-Processing (as native as possible)
- REST-API (JSON) and 100% Swagger documented
- Resource Monitoring (optionally by Prom-Metrics)
- Server- and Process-Logging
- GDPR compliant without third-party providers and does not save audience data

## Quick setup

### AMD64/ARMv7/ARM64:
```sh
docker run -d --restart=always --name restreamer \
   -v /opt/restreamer/config:/core/config -v /opt/restreamer/data:/core/data \
   -p 8080:8080 -p 8181:8181 \
   -p 1935:1935 -p 1936:1936 \
   -p 6000:6000/udp \
   datarhei/restreamer:latest
```

*`--privileged` just for local devices like usb cameras.*    
*Try `--security-opt seccomp=unconfined` if no network source can be reached.*

### ARMv7/ARM64 Raspberry Pi:
```sh
docker run -d --restart=always --name restreamer \
   -v /opt/restreamer/config:/core/config -v /opt/restreamer/data:/core/data \
   --privileged \
   -p 8080:8080 -p 8181:8181 \
   -p 1935:1935 -p 1936:1936 \
   -p 6000:6000/udp \
   datarhei/restreamer:rpi-latest
```

*`--privileged` just for local devices like usb cameras.*    
*Try `--security-opt seccomp=unconfined` if no network source can be reached.*

### AMD64 Nvidia Cuda:
```sh
docker run -d --restart=always --name restreamer \
   -v /opt/restreamer/config:/core/config -v /opt/restreamer/data:/core/data \
   --runtime=nvidia --privileged \
   -p 8080:8080 -p 8181:8181 \
   -p 1935:1935 -p 1936:1936 \
   -p 6000:6000/udp \
   datarhei/restreamer:cuda-latest
```

*`--privileged` just for local devices like usb cameras.*    
*Try `--security-opt seccomp=unconfined` if no network source can be reached.*

### AMD64 Intel VAAPI:
```sh
docker run -d --restart=always --name restreamer \
   -v /opt/restreamer/config:/core/config -v /opt/restreamer/data:/core/data \
   -v /dev/dri:/dev/dri --privileged \
   -p 8080:8080 -p 8181:8181 \
   -p 1935:1935 -p 1936:1936 \
   -p 6000:6000/udp \
   datarhei/restreamer:vaapi-latest
```

*`--privileged` just for local devices like usb cameras.*    
*Try `--security-opt seccomp=unconfined` if no network source can be reached.*

*For external access (http/s, rtmp/s, srt), port forwarding from your Internet-Router to the Restreamer's internal IP address may need to be set up.*

## Documentation

Documentation is available on [docs.datarhei.com/restreamer](https://docs.datarhei.com/restreamer). We give many pieces of information, from setting up a camera, embedding your player upon your website, and streaming to services like, e.g., YouTube-Live, and many more.

- [Quick start](https://docs.datarhei.com/restreamer/getting-started/quick-start)
- [Installation](https://docs.datarhei.com/restreamer/installing/minimum-requirements)
- [Manual](https://docs.datarhei.com/restreamer/knowledge-base/manual)
- [Guides](https://docs.datarhei.com/restreamer/knowledge-base/user-guides)

## Development

### Submodule workspace for this fork

This repository can act as the superproject for the three source repositories that feed the final bundle image:

- `third_party/ffmpeg` -> `https://github.com/SKPloft/ffmpeg-arc`
- `third_party/core` -> `https://github.com/SKPloft/core-arc`
- `third_party/restreamer-ui` -> `https://github.com/SKPloft/restreamer-ui-arc`

Add the submodules once:

```sh
./scripts/add-submodules.sh
```

If you prefer to add them manually:

```sh
git submodule add https://github.com/SKPloft/ffmpeg-arc.git third_party/ffmpeg
git submodule add https://github.com/SKPloft/core-arc.git third_party/core
git submodule add https://github.com/SKPloft/restreamer-ui-arc.git third_party/restreamer-ui
git submodule update --init --recursive
```

Build the full bundle from the submodule sources with a single entrypoint:

```sh
make build
make build FFMPEG_FLAVOR=rpi
make build FFMPEG_FLAVOR=cuda
make build FFMPEG_FLAVOR=vaapi
```

Each flavor maps to one Dockerfile of the pinned ffmpeg branch and to the base image that
ffmpeg-arc uses for it:

| `FFMPEG_FLAVOR` | Dockerfile | Base image | Encoders |
| --- | --- | --- | --- |
| `default` | `Dockerfile.alpine` | `alpine:3.23` | software AV1 |
| `rpi` | `Dockerfile.alpine.rpi` | `alpine:3.23` | software AV1 |
| `vaapi` | `Dockerfile.ubuntu.vaapi` | `ubuntu:24.04` | Intel VA-API and oneVPL, including hardware AV1 |
| `cuda` | `Dockerfile.ubuntu.cuda13` | `nvidia/cuda:13.1.0-devel-ubuntu24.04` | Nvidia CUDA/NVENC |

By default this produces the following local image tags:

- `restreamer-arc-ffmpeg:<flavor>`
- `restreamer-arc-core:local`
- `restreamer-arc-restreamer-ui:local`
- `restreamer-arc:<flavor>`

Those tags are mutable and meant for local iteration. A release build goes through one entrypoint
that proves the sources first:

```sh
make release FFMPEG_FLAVOR=vaapi
```

It refuses to build when any of these holds:

- a submodule `HEAD` is not the gitlink the superproject commits for that path,
- the superproject or a submodule has changes to tracked files,
- a pinned component commit is not on any remote branch of that component,
- a component image that is about to be assembled was built from another revision, i.e. its
  `org.opencontainers.image.revision` label differs from the pin.

Release images are tagged by the commits they were built from, so they never replace the tags a
running deployment falls back to:

| image | release tag |
| --- | --- |
| `restreamer-arc-ffmpeg` | `<flavor>-ff<ffmpeg sha12>` |
| `restreamer-arc-core` | `<flavor>-core<core sha12>` |
| `restreamer-arc-restreamer-ui` | `ui<ui sha12>` |
| `restreamer-arc` | `<flavor>-ui<ui sha12>-core<core sha12>-ff<ffmpeg sha12>-r<root sha12>` |

The core tag carries the flavor because its base image differs per flavor; the UI image is the
same for every flavor. The bundle tag carries the root commit as well: the root `Dockerfile`,
`run.sh` and `ui-root` change the product without changing any component commit, so a tag built
from component SHAs alone would be reused for different contents.

Every image carries `org.opencontainers.image.revision` (the full component commit) and
`org.opencontainers.image.source` (the component fork clone URL); the bundle adds
`io.skploft.restreamer.components` with the three commits. FFmpeg's `--extra-version` records the
pinned commit and its commit date instead of `unknown` and the 1970 epoch.

In a release build the FFmpeg stamp is read from the verified commit and passed on the make
command line, so an exported `FFMPEG_BUILD_COMMIT`/`FFMPEG_BUILD_DATE` cannot label the image with
another source. `make build` keeps the overridable defaults for local iteration.

Docker reads every build context from a temporary directory materialised from the verified
commit: `git archive` for the root repository, ffmpeg and the UI, and a local clone checked out at
the pinned commit for core, whose Makefile stamps `app.Commit` only when `.git` is a directory.
Untracked files, ignored files and a private `.env` in the working copies therefore cannot reach a
release image, and the temporary contexts are removed when the build finishes.

The build writes `releases/restreamer-arc-<flavor>-<root sha12>.json` (a numeric suffix is added
when that file already exists) and prints the path. The manifest holds the root and component
commits, the flavor matrix inputs that were used (ffmpeg Dockerfile, base images, `BUILD_COMMIT`,
`BUILD_DATE`, Go and Node/Caddy images and their local image IDs), each image's platform, local `image_id` and
`registry_digests`, and the bundle labels. `image_id` is the local image config digest;
`registry_digests` stays empty until the image is pushed, and the two are never interchangeable.

The manifest describes the image only. A host can still replace what actually runs: a bind mount
over `/core/ui` and `CORE_FFMPEG_BINARY` in the core config decide the served interface and the
FFmpeg binary independently of the image contents. `GET /api/v3/skills` is the authoritative
answer for that binary: core reports the version it detected, so a different `ffmpeg` on `PATH`
does not mislead the check. Verification on the target therefore records the sha256 of the served
`main.<hash>.js`, the path and sha256 of the binary the core really executes, and the core commit,
next to the manifest. The deployment issue for that host (`SKPLoft/devops#40`) carries those
values.

#### Hardware AV1 on Intel Arc

The `vaapi` flavor builds FFmpeg with `--enable-vaapi` and `--enable-libvpl` and ships the
VA-API driver, the oneVPL dispatcher and the oneVPL GPU runtime. The interface then offers
two Intel hardware AV1 encoders:

- `AV1 (Intel VAAPI)` encodes with `av1_vaapi` and takes the DRM render node as its `Device` setting.
- `AV1 (Intel QSV)` encodes with `av1_qsv` over oneVPL and takes the same setting.

Both settings default to `/dev/dri/renderD128`. On a machine with more than one graphics
device, read the render node of the Intel card from `/dev/dri/by-path`:

```sh
ls -l /dev/dri/by-path
```

Build and start the bundle with the DRM device:

```sh
make build-vaapi
make run FFMPEG_FLAVOR=vaapi
```

`make run` passes `--device /dev/dri:/dev/dri` to the container. The stream wizard and the
stream encoding settings offer H.264 only, so choose the AV1 encoder in the encoding
settings of a publication destination whose service declares AV1 support (RTMP, SRT,
Youtube and the datarhei Core service do).
The interface lists exactly those encoders that the running FFmpeg reports:

```sh
curl -s http://127.0.0.1:8080/api/v3/skills | jq '.codecs.video[] | select(.id == "av1")'
```

#### Upstream-supported combos vs local workspace

This fork now keeps one generated combo catalog at `combinations/catalog.json`. It is generated from `.github/workflows/build_bundle.yaml` and `.github/workflows/build_bundle_dev.yaml`, so it reflects the upstream-derived bundle combinations that this repo publishes or tracks.

Use the catalog to compare those upstream-supported combos with the versions pinned in the current submodule workspace:

```sh
make list-combos
make show-combo COMBO=main/default
make show-combo COMBO=dev/cuda
```

Combo IDs currently available:

- `main/default`
- `main/rpi`
- `main/vaapi`
- `main/cuda`
- `dev/default`
- `dev/rpi`
- `dev/vaapi`
- `dev/cuda`

`make list-combos` prints the upstream combo ID, image tags, platforms, and a drift status. `make show-combo` prints the upstream tags plus the local `FFMPEG_FLAVOR` mapping, pinned UI/core/ffmpeg metadata, and any drift markers.

The catalog compares upstream workflows with the local pins. What this repository ships is a third
set of components:

| source | ffmpeg | core | ui |
| --- | --- | --- | --- |
| upstream `main/*` (`datarhei/restreamer:<flavor>`) | 6.1.1 | core main | UI release |
| upstream `dev/*` (`datarhei/restreamer:<flavor>-dev`) | 8.1.1 | core `dev` | UI `dev` |
| this fork `2.x` (`make release`) | 8.0.1 plus this fork's `contrib/*.patch` | core-arc main | restreamer-ui-arc main |

The `dev` channel ships newer components than the `2.x` pins, so a candidate built here can be a
downgrade on a target that already runs `*-dev`. Establish the baseline on the target before
deploying: the image digest and tag in use, the FFmpeg banner of the binary the core actually
runs, the core and UI versions, and a cold start against the real database. Compare that baseline
with the candidate's manifest and deploy only when no component is older than the baseline.

Drift markers mean the local workspace does not currently match the selected upstream combo. The local ffmpeg submodule is pinned to the `8.0` branch (`FFMPEG_VERSION` `8.0.1` on Alpine `3.23` and Ubuntu `24.04`), while the upstream bundle workflows reference ffmpeg `6.1.1` for `main` and `8.1.1` for `dev`. `manual_review` markers mean the upstream workflow resolves a version dynamically, so the local workspace should be compared manually instead of being treated as equivalent.

To refresh the generated catalog after updating workflow matrices or local pins:

```sh
make generate-combo-catalog
```

To run the locally built bundle:

```sh
make run
```

If you need `buildx`, override `DOCKER_BUILD`, for example:

```sh
make build DOCKER_BUILD='docker buildx build --load'
```

### Bundle release: pinned sources and preview player rollout

The bundle is released from the three gitlinks in `third_party`. The audit behind the current
preview player fix lives in the UI repository at
[`docs/av1-preview-audit.md`](https://forgejo.vtopia.top/SKPloft/restreamer-ui-arc/src/branch/main/docs/av1-preview-audit.md).

`make release` performs these checks itself. To inspect them by hand, confirm that every pinned
commit is reachable from the remotes named in `.gitmodules`:

```sh
git submodule status
git -C third_party/core branch -r --contains HEAD
git -C third_party/restreamer-ui branch -r --contains HEAD
```

`CORE_GOLANG_IMAGE` follows the release matrix in
`third_party/core/.github/workflows/build_base.yaml`. The `ARG GOLANG_IMAGE` default inside
`third_party/core/Dockerfile` is overridden by `make build-core`, so only the workflow matrix
matters when the core pin moves.

After the new UI reaches a running instance:

1. Refresh the UI build in place (`rsync --delete` into the mounted directory) and keep the
   previous build as the rollback baseline.
2. Re-save the **Publication → Player** page of every channel
   (`/#/<channelid>/publication/player`). Save rewrites the channel metadata and the player
   config, re-renders `/<channelid>.html` and re-uploads the assets from `_player/videojs`
   (`hls.min.js`, `videojs-hlsjs.js`); the ingest control block stays as it is, so the running
   encoder is not restarted.
3. Re-save the playersite (`/#/playersite`) so its player assets are regenerated as well.
4. Hard-reload the SPA and one published page, and confirm the served `hls.min.js` and
   `videojs-hlsjs.js` are the new builds.

Do not re-save Source/Edit pages in bulk: that path runs `UpsertIngest` and restarts the live
stream. Rebuild a channel in Source/Edit only when it was previously saved with MPEG-TS
segments for a non-H.264 `copy` source; verify the new composition in an isolated staging
instance with a probe first and schedule a maintenance window. H.264 channels and channels that
already encode AV1 natively need no rebuild.

Rollback does not follow from a successful new core. The order is: establish the compatible
`core` and `ffmigrate` pair as the tested baseline first, both binaries from the same commit and
cold-started against the real database, and release the UI only after that baseline exists.

- UI rollback restores the previous UI assets and keeps the compatible backend running.
- Backend rollback needs a separate compatible image, or an image that carries both a working
  `core` and a working `ffmigrate`, verified to cold-start against the database it will face.
  Reverting this repository to the previous bundle commit restores an `ffmigrate` that rejects
  FFmpeg 8, so it is not a rollback path.
- When no such backend baseline exists, keep the running instance, isolate the candidate, and
  let the deployment issue for that host (`SKPLoft/devops#40`) define the plan. A new core that
  cold-starts says nothing about the previous bundle.

Never delete database records to make a migration pass.

### Manual image assembly (still supported)

#### [Restreamer FFmpeg](https://github.com/SKPloft/ffmpeg-arc):
```
$ git clone https://github.com/SKPloft/ffmpeg-arc
$ cd ffmpeg-arc
$ docker build -f Dockerfile.alpine --build-arg FFMPEG_VERSION=8.0.1 -t myffmpeg .
```

#### [Restreamer backend](https://github.com/SKPloft/core-arc) (Golang):

```
$ git clone https://github.com/SKPloft/core-arc
$ cd core-arc
$ docker build -t mycore .
```

#### [Restreamer interface](https://github.com/SKPloft/restreamer-ui-arc) (React):
```
$ git clone https://github.com/SKPloft/restreamer-ui-arc
$ cd restreamer-ui-arc
$ docker build -t myrsui .
```

#### Restreamer bundle:
```
$ git clone https://github.com/SKPloft/restreamer-arc
$ cd restreamer-arc
$ docker build --build-arg FFMPEG_IMAGE=myffmpeg --build-arg CORE_IMAGE=mycore --build-arg RESTREAMER_UI_IMAGE=myrsui -t myrestreamer .
$ docker run -it --rm -p 8080:8080 myrestreamer
```

All three `--build-arg` values are required. The root Dockerfile has no fallback, so a
`docker build .` without them fails instead of silently assembling the upstream `latest` images.

### To add/fix translations in the [Restreamer interface](https://github.com/datarhei/restreamer-ui):

The Restreamer interface is currently translated in different languages, such as German, French, Italian, Spanish, and more. If you find errors in the translations or have better suggestions for some sentences, you can become a translation contributor on [poeditor.com](https://poeditor.com/join/project/ogATl3F48K).
There you can also start a translation into a language that is not yet available in the Restreamer interface.

Contribute to the translations on: [https://poeditor.com/join/project/ogATl3F48K](https://poeditor.com/join/project/ogATl3F48K)

## Community support

For general help using Restreamer, please refer to the official [documentation](https://docs.datarhei.com/restreamer). For additional support, you can use Github to ask a question (Bug reports, Contributions, Features).

## License
See the [LICENSE](./LICENSE) file for licensing information.

## Business inquiries
**We provide support for commercial requirements with professional support, agile software development, and consulting.** If you have a commercial request, be it a bug or a feature enhancement, please contact us directly at support@datarhei.com.
