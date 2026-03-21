# lazybox

All the modern CLI tools you love, in under 1 MB. Tools download on first use — just add one line to any Dockerfile.

```dockerfile
COPY --from=bonisoft3/lazybox /lazybox /lazybox
ENV PATH=$PATH:/lazybox/.local/share/lazybox/shims:/lazybox/.local/share/lazybox/stubs:/lazybox/.local/share/lazybox/bin
```

## What you get

**Containers & K8s**: docker, compose, buildx, kubectl, kind, skaffold
**Shell & Scripting**: nu (Nushell), just, task, cue, jq, yq, buf
**Search & Files**: rg (ripgrep), fd, fzf, bat, lsd, dua, zoxide
**Dev Tools**: uv, uvx, micro, hyperfine, xh, sops, recur, tcping

Each tool is a tiny shell stub that bootstraps itself to fetch the real binary on first invocation. Subsequent calls run the cached binary directly.

## How it works

When you call a tool for the first time, the bootstrapping chain is:

1. The **stub script** (~10 lines of sh) delegates to `mise tool-stub <tool>.toml`
2. If mise isn't installed yet, the **mise shim** fetches it using a **static curl** with bundled CA certificates
3. **mise** reads the TOML manifest (version, platform URLs, checksums) and downloads the real binary
4. The binary is cached — subsequent calls run it directly

**BusyBox** is included as a fallback for minimal/scratch images that lack basic POSIX utilities.

Each tool has a shell stub + a TOML sidecar with per-platform download metadata. The entire stubs directory is under 1 MB.

> **Tip**: Run tools during `docker build` (e.g., `RUN jq --version`) to bake them into the image layer. Otherwise they're fetched at container runtime.

## Portability

Lazybox is a single relocatable directory — no symlinks into system paths, no package manager dependencies, no assumptions about the host. It works on:

- Linux (glibc and musl/Alpine)
- macOS (Intel and Apple Silicon)
- Windows (amd64)

Each stub carries platform-specific download URLs and checksums, with automatic Alpine/musl detection for Linux ARM64 fallback when native musl builds aren't available.

## Usage

### Layer onto any image

```dockerfile
FROM your-company/production-base:latest
COPY --from=bonisoft3/lazybox /lazybox /lazybox
ENV PATH=$PATH:/lazybox/.local/share/lazybox/shims:/lazybox/.local/share/lazybox/stubs:/lazybox/.local/share/lazybox/bin
RUN jq --version  # fetched and cached in this layer
```

### Use as a devcontainer base

```dockerfile
FROM bonisoft3/lazybox:nubox
# Nushell as default shell, mise activated, all tools available
```

### Extract to a local directory

```bash
docker create --name lb bonisoft3/lazybox
docker cp lb:/lazybox ./lazybox
docker rm lb
export PATH="$PWD/lazybox/.local/share/lazybox/shims:$PWD/lazybox/.local/share/lazybox/stubs:$PWD/lazybox/.local/share/lazybox/bin:$PATH"
```

## Adding tools

1. Add the tool entry to `mise.toml`
2. Run `mise lock` to generate the cross-platform lockfile
3. Run `nu mise-lazybox.nu` to regenerate stubs

The stub generator reads the lockfile and produces a shell wrapper + TOML manifest (with platform URLs and checksums) for each binary, including Alpine/musl variants where needed.

## Building

```bash
docker build --target lazybox -t bonisoft3/lazybox .devcontainer/
```

Available targets:
- **lazybox** — the portable toolbox layer (default, based on Wolfi)
- **nubox** — extends lazybox with Nushell as default shell and mise activated
