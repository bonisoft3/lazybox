#!/usr/bin/env nu

# Core mise utilities and shared operations
# Centralizes directory discovery, binary mapping, and common mise operations

# Get mise base directories
export def get_mise_directories [] {
    let base_dir = if "MISE_DATA_DIR" in $env and ($env.MISE_DATA_DIR | is-not-empty) {
        $env.MISE_DATA_DIR
    } else if "XDG_DATA_HOME" in $env and ($env.XDG_DATA_HOME | is-not-empty) {
        $"($env.XDG_DATA_HOME)/mise"
    } else {
        $"($env.HOME)/.local/share/mise"
    }

    {
        base: $base_dir,
        shims: ($base_dir | path join "shims"),
        installs: ($base_dir | path join "installs")
    }
}



# Build comprehensive binary mapping from mise installations
export def build_binary_mapping [] {
    let dirs = (get_mise_directories)
    let shims_dir = $dirs.shims
    let installs_dir = $dirs.installs

    if not ($shims_dir | path exists) {
        return {}
    }

    # Build mapping: binary -> tool spec
    let tool_mapping = (build_tool_mapping $installs_dir)

    # Get available shims
    let available_shims = (
        ls $shims_dir
        | where type == symlink
        | get name
        | path basename
        | where {|it| $it in $tool_mapping}
    )

    mut binary_map = {}
    for shim in $available_shims {
        let tool_spec = ($tool_mapping | get $shim)
        $binary_map = ($binary_map | upsert $shim $tool_spec)
    }

    $binary_map
}

# Build tool mapping from installation directories
export def build_tool_mapping [installs_dir: string] {
    if not ($installs_dir | path exists) {
        return {}
    }

    ls $installs_dir | where type == dir | each {|d|
        let dir = $d.name

        let backend = ($dir | path join ".mise.backend")
        if not ($backend | path exists) { return }

        let lines = (open $backend | lines)
        let pkg = ($lines | where ($it | str contains ":") | first | default ($lines | first))

        let latest_link = try {
            ls $dir
            | where type == symlink
            | where ($it.name | str ends-with "latest")
            | first
            | get name
        } catch { return }

        let version_path = ($latest_link | path expand)
        if not ($version_path | path exists) { return }

        let version = ($version_path | path basename)
        let pkg_spec = $"($pkg)@($version)"

        find_executable_files $version_path
        | each {|f| { bin: ($f | path basename), pkg: $pkg_spec } }
    }
    | flatten
    | reduce -f {} {|it, acc| $acc | upsert $it.bin $it.pkg }
}

# Find all executable files in a directory tree
export def find_executable_files [base_path: string] {
    glob $"($base_path)/**/*"
    | where {|f| ($f | path type) == "file" }
    | where {|f| try { ^test -x $f; true } catch { false } }
}

# Find binaries for a tool spec from binary mapping
export def find_tool_binaries [tool_spec: string, binary_map: record] {
    $binary_map
    | items {|k, v| {binary: $k, spec: $v}}
    | where {|item|
        let spec_tool = ($item.spec | split row "@" | first)
        $spec_tool == $tool_spec
    }
    | each {|item| {
        original_name: $item.binary,
        clean_name: (clean_binary_name $item.binary)
    }}
    | uniq
}

# Clean platform suffixes from binary names
export def clean_binary_name [name: string] {
    let patterns = [
        "_linux_amd64", "_linux_arm64", "_darwin_amd64", "_darwin_arm64", "_windows_amd64",
        "_linux-amd64", "_linux-arm64", "_darwin-amd64", "_darwin-arm64", "_windows-amd64",
        "_macos_arm64", "_macos-arm64", "_x86_64", "_amd64", "_arm64"
    ]

    mut clean_name = $name
    for pattern in $patterns {
        if ($clean_name | str ends-with $pattern) {
            $clean_name = ($clean_name | str replace $pattern "")
        }
    }
    $clean_name
}
