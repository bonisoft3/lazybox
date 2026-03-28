# lazybox

40+ modern CLI tools in a single Docker image. Tools download on first use — just add one line to any Dockerfile.

```dockerfile
COPY --from=bonisoft3/lazybox /lazybox /usr/local
```

That's it. Stubs land in `/usr/local/bin` (already on `PATH`), and a bundled static curl + CA certificates handle bootstrapping on any image — even ones without curl.

## What you get

**Containers & K8s**: docker, compose, buildx, kubectl, kind, skaffold
**Shell & Scripting**: nu (Nushell), just, task, cue, jq, yq, buf
**Search & Files**: rg (ripgrep), fd, fzf, bat, lsd, dua, zoxide
**Dev Tools**: uv, uvx, micro, hyperfine, xh, sops, recur, tcping

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

- Linux (glibc and musl/Alpine) — amd64 and arm64
- macOS (Intel and Apple Silicon)
- Windows (amd64)

Each stub carries platform-specific download URLs and checksums, with automatic Alpine/musl detection and ARM64 fallback when native musl builds aren't available.

## Usage

### Layer onto any image

```dockerfile
FROM ubuntu:24.04
COPY --from=bonisoft3/lazybox /lazybox /usr/local
RUN jq --version  # fetched and cached in this layer
```

### Minimal layer (host already has curl)

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache curl ca-certificates
COPY --from=bonisoft3/lazybox /lazybox/bin /usr/local/bin
```

### Use as a devcontainer base

```dockerfile
FROM bonisoft3/lazybox:nubox
# Nushell as default shell, mise activated, all tools available
```

### Run standalone

```bash
docker run --rm bonisoft3/lazybox rg --version
```

### Extract to a local directory

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
- **lazybox** — the portable toolbox layer (default, based on Alpine)
- **nubox** — extends lazybox with Nushell as default shell and mise activated
