# lazybox

40+ modern CLI tools in a single Docker image. Tools download on first use — just add one line to any Dockerfile.

```dockerfile
COPY --from=bonisoft3/lazybox /lazybox /usr/local
```

That's it. Stubs land in `/usr/local/bin` (already on `PATH`) and bootstrap themselves on any image.

## What you get

**Containers & K8s**: docker, compose, buildx, kubectl, kind, skaffold, helm
**Shell & Scripting**: nu (Nushell), just, task, cue, jq, yq, buf
**Search & Files**: rg (ripgrep), fd, fzf, bat, lsd, dua, zoxide, sd
**Dev Tools**: uv, uvx, micro, hyperfine, xh, sops, recur, tcping, age

## How it works

Each tool is a tiny shell stub that bootstraps itself on first invocation:

1. The **stub** (~10 lines of sh) calls `.lazybox` which delegates to `mise tool-stub <tool>.toml`
2. If mise isn't installed yet, `.lazybox` fetches it using the bundled **static curl** and CA certificates
3. **mise** reads the TOML manifest (version, platform URLs, checksums) and downloads the real binary
4. The binary is cached — subsequent calls run it directly

All paths are resolved explicitly (no `PATH` lookups between components), so there are no shim loops regardless of what else is on your `PATH`.

> **Tip**: Run tools during `docker build` (e.g., `RUN jq --version`) to bake them into the image layer. Otherwise they're fetched at container runtime.

## Portability

Lazybox works on:

- Linux — glibc and musl/Alpine, amd64 and arm64
- macOS — Intel and Apple Silicon
- Windows — native, WSL, and Windows containers, amd64

Each stub carries platform-specific download URLs and checksums, with automatic Alpine/musl detection. When a statically linked build isn't available, the dynamically linked variant is used as fallback.

## Usage

### Overlay onto any image (~8 MB)

```dockerfile
FROM ubuntu
COPY --from=bonisoft3/lazybox /lazybox /usr/local
RUN jq --version  # fetched and cached in this layer
```

Add extra tooling to an existing base image for ad-hoc debugging and inspection. Includes bundled static curl and CA certificates, so tools bootstrap even on images without curl.

### Stubs-only overlay (~350 KB)

```dockerfile
FROM alpine/curl
COPY --from=bonisoft3/lazybox /lazybox/bin /usr/local/bin
```

Keep the image minimal when the host already provides SSL-enabled curl. Only the stubs are copied — tools download on first use.

### Devcontainer

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04
COPY --from=bonisoft3/lazybox:nubox /lazybox /home/vscode/.local
COPY --from=bonisoft3/lazybox:nubox /root/.config/nushell /home/vscode/.config/nushell
ENV PATH=$PATH:/home/vscode/.local/bin
CMD [ "/home/vscode/.local/bin/nu", "-l" ]
```

The FHS layout works under `$HOME/.local` just like `/usr/local` — add `bin` to `PATH` when the home directory is known at build time. The second COPY brings the Nushell config with mise activation. The pre-built `nubox` target eagerly initializes Nushell and mise. If you need even more customization, check the [Dockerfile](./Dockerfile) for more tricks.

### From scratch

```dockerfile
FROM scratch
COPY --from=busybox:1.36.1-musl /bin/busybox /bin/busybox
RUN ["/bin/busybox", "sh", "-c", "busybox --install /bin"]
COPY --from=bonisoft3/lazybox /lazybox /usr/local
RUN jq --version
```

Busybox on steroids. The stubs need a shell to bootstrap, so start with busybox to provide `/bin/sh`, then layer lazybox on top.

### Pinned base with system packages

```dockerfile
FROM opensuse/leap:15.6@sha256:b084d6e29d975ce9123fd52bd201ac020628797f2772e9171ef76f33cc92d591
COPY --from=bonisoft3/lazybox /lazybox /usr/local
RUN zypper install -y git-core
```

Good for stable builder images. Leap provides versioned repositories — packages aren't garbage-collected like in rolling distros. Pin with a multiplatform sha256 for full reproducibility. Use zypper for dependencies not available in mise, and lazybox for everything else.

### Pre-caching tools

```dockerfile
FROM bonisoft3/lazybox
ARG LAZYBOX_TOOLS="jq rg fd bat"
```

The lazybox image includes an `ONBUILD` trigger — set the `LAZYBOX_TOOLS` arg to pre-cache specific tools during build. Each tool's `--help` is invoked automatically, triggering its stub and caching the binary in the image layer. For ad-hoc caching without the arg, just `RUN jq --help` directly.

### Run standalone

```bash
docker run --rm bonisoft3/lazybox rg --version
```

Useful for trying out the tools without installing anything locally.

### Extract to a local directory

For when you want to test tools locally on your machine without Docker.

```bash
docker create --name lb bonisoft3/lazybox
docker cp lb:/lazybox ./lazybox
docker rm lb
export PATH="$PWD/lazybox/bin:$PATH"
```

## Adding tools

1. Add the tool entry to `mise.toml`
2. Run `mise lock` to generate the cross-platform lockfile
3. Run `nu mise-lazybox.nu` to regenerate stubs

The stub generator reads the lockfile and produces a shell wrapper + TOML manifest (with platform URLs and checksums) for each binary, including Alpine/musl variants where needed.

## Building

```bash
docker build --target lazybox -t bonisoft3/lazybox .
```

Available targets:
- **lazybox** — the portable toolbox overlay (default, based on Alpine)
- **nubox** — extends lazybox with Nushell and mise activated (based on wolfi-base for glibc compatibility)
