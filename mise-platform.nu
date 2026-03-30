#!/usr/bin/env nu

# Platform detection and preference logic for mise tools
# Handles aqua registry preferences and Alpine/musl detection

export def main [
    tool_spec: string  # Tool specification (e.g., "aqua:casey/just")
    --platform(-p): string = ""  # Platform to check (linux-amd64, darwin-arm64, etc.)
] {
    if ($platform | is-empty) {
        let all_platforms = (get_platform_definitions $tool_spec)
        $all_platforms | table
    } else {
        let preference = (get_platform_preference $tool_spec $platform)
        print $"Platform preference for ($tool_spec) on ($platform): ($preference)"
    }
}

# Get platform definitions with aqua-aware ordering
export def get_platform_definitions [tool: string] {
    # Get platform patterns with aqua-aware ordering for Linux platforms
    let is_aqua_tool = ($tool | str starts-with "aqua:")
    let tool_name = if $is_aqua_tool { ($tool | str replace "aqua:" "") } else { "" }

    # For aqua tools, check preferences and reorder linux patterns accordingly
    let linux_amd64_patterns = if $is_aqua_tool {
        let aqua_preference = (get_aqua_platform_preference $tool_name "linux-amd64")
        if ($aqua_preference == "gnu") {
            ["x86_64-unknown-linux-gnu", "x86_64-unknown-linux-musl", "linux-amd64", "x86_64-linux", "linux_amd64", "Linux-x86_64", "linux.amd64", "linux-x86_64"]
        } else {
            ["x86_64-unknown-linux-musl", "x86_64-unknown-linux-gnu", "linux-amd64", "x86_64-linux", "linux_amd64", "Linux-x86_64", "linux.amd64", "linux-x86_64"]
        }
    } else {
        ["x86_64-unknown-linux-musl", "x86_64-unknown-linux-gnu", "linux-amd64", "x86_64-linux", "linux_amd64", "Linux-x86_64", "linux.amd64", "linux-x86_64"]
    }

    let linux_arm64_patterns = if $is_aqua_tool {
        let aqua_preference = (get_aqua_platform_preference $tool_name "linux-arm64")
        if ($aqua_preference == "gnu") {
            ["aarch64-unknown-linux-gnu", "aarch64-unknown-linux-musl", "linux-arm64", "aarch64-linux", "linux_arm64", "Linux-aarch64", "linux.arm64", "linux-aarch64"]
        } else {
            ["aarch64-unknown-linux-musl", "aarch64-unknown-linux-gnu", "linux-arm64", "aarch64-linux", "linux_arm64", "Linux-aarch64", "linux.arm64", "linux-aarch64"]
        }
    } else {
        ["aarch64-unknown-linux-musl", "aarch64-unknown-linux-gnu", "linux-arm64", "aarch64-linux", "linux_arm64", "Linux-aarch64", "linux.arm64", "linux-aarch64"]
    }

    [
        {name: "linux-amd64", patterns: ($linux_amd64_patterns | append ["Linux_x86_64", "Linux-x86_64"])},
        {name: "linux-arm64", patterns: ($linux_arm64_patterns | append ["Linux_arm64", "Linux-arm64"])},
        {name: "darwin-amd64", patterns: ["x86_64-apple-darwin", "Darwin-x86_64", "darwin-amd64", "darwin_amd64", "Darwin_x86_64"]},
        {name: "darwin-arm64", patterns: ["aarch64-apple-darwin", "darwin-arm64", "macos-arm64", "darwin_arm64", "Darwin-arm64", "darwin-aarch64", "Darwin_arm64"]},
        {name: "windows-amd64", patterns: ["x86_64-pc-windows-msvc", "windows-amd64", "win64", "windows_amd64", "Windows-x86_64", "Windows_x86_64"]}
    ]
}

# Get platform preference (gnu vs musl) for a specific tool and platform
export def get_platform_preference [tool_spec: string, platform: string] {
    if ($tool_spec | str starts-with "aqua:") {
        let tool_name = ($tool_spec | str replace "aqua:" "")
        get_aqua_platform_preference $tool_name $platform
    } else {
        "musl"  # Default preference for non-aqua tools
    }
}

# Get platform preference from aqua registry (gnu vs musl)
export def get_aqua_platform_preference [tool_name: string, platform: string] {
    # Parse platform to get os and arch for aqua registry matching
    let parts = ($platform | split row "-")
    if ($parts | length) != 2 {
        return "musl"
    }
    let os = $parts.0
    let arch = $parts.1

    # Map mise platform names to aqua registry GOOS/GOARCH values
    let goos = match $os {
        "linux" => "linux",
        "darwin" => "darwin",
        "windows" => "windows",
        _ => {
            return "musl"
        }
    }

    let goarch = match $arch {
        "amd64" => "amd64",
        "arm64" => "arm64",
        _ => {
            return "musl"
        }
    }

    # Fetch aqua registry YAML for this tool
    let registry_url = $"https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/($tool_name)/registry.yaml"

    let registry_yaml = try {
        ^curl -sL $registry_url
    } catch {
        return "musl"
    }

    if ($registry_yaml | str trim | is-empty) {
        return "musl"
    }

    # Parse YAML to find overrides
    let registry_data = try {
        ($registry_yaml | from yaml)
    } catch {
        return "musl"
    }

    # Look for overrides in the packages
    let packages = ($registry_data | get packages? | default [])
    if ($packages | length) == 0 {
        return "musl"
    }

    # Check each package for overrides that match our platform
    for package in $packages {
        let overrides = ($package | get overrides? | default [])
        for override in $overrides {
            let override_goos = ($override | get goos? | default "")
            let override_goarch = ($override | get goarch? | default "")

            # Check if this override matches our platform
            let matches = if ($override_goos != "") and ($override_goarch != "") {
                ($override_goos == $goos) and ($override_goarch == $goarch)
            } else if ($override_goos != "") {
                ($override_goos == $goos)
            } else if ($override_goarch != "") {
                ($override_goarch == $goarch)
            } else {
                false
            }

            if $matches {
                # Check if this override has gnu in the asset pattern or replacements
                let asset = ($override | get asset? | default "")
                if ($asset | str contains "gnu") {
                    return "gnu"
                }

                # Check replacements in this override
                let override_replacements = ($override | get replacements? | default {})
                for repl_key in ($override_replacements | columns) {
                    let repl_value = ($override_replacements | get $repl_key)
                    if ($repl_value | str contains "gnu") {
                        return "gnu"
                    }
                }
            }
        }

        # Also check base replacements for musl -> gnu mappings
        let replacements = ($package | get replacements? | default {})
        for replacement_key in ($replacements | columns) {
            let replacement_value = ($replacements | get $replacement_key)
            if ($replacement_key | str contains "musl") and ($replacement_value | str contains "gnu") {
                # This tool has a musl->gnu replacement, preferring gnu
                return "gnu"
            }
        }
    }

    "musl"
}


# Get Alpine-specific platform preference
export def get_alpine_platform_preference [tool_data: record] {
    let platforms = ($tool_data | get platforms? | default {})

    # Check if we have musl variants available
    let linux_amd64_data = ($platforms | get linux-amd64? | default {})
    let linux_arm64_data = ($platforms | get linux-arm64? | default {})
    let linux_amd64_url = ($linux_amd64_data | get url? | default "")
    let linux_arm64_url = ($linux_arm64_data | get url? | default "")

    let has_musl_amd64 = ($linux_amd64_url | str contains "musl")
    let has_musl_arm64 = ($linux_arm64_url | str contains "musl")
    let has_gnu_arm64 = ($linux_arm64_url | str contains "gnu")

    # Alpine ARM64 fallback logic: if there's musl x86_64 but no musl arm64 (only gnu arm64),
    # prefer x86_64 musl for Alpine compatibility
    if $has_musl_amd64 and (not $has_musl_arm64) and $has_gnu_arm64 {
        {
            prefer_platform: "linux-amd64",
            reason: "Alpine ARM64 fallback: using x86_64 musl instead of arm64 gnu"
        }
    } else {
        {
            prefer_platform: "",
            reason: "No Alpine-specific preference needed"
        }
    }
}

# Generate Alpine variant of platform data
export def generate_alpine_platform_data [tool_data: record] {
    let alpine_pref = (get_alpine_platform_preference $tool_data)

    if ($alpine_pref.prefer_platform | is-not-empty) {
        let platforms = ($tool_data | get platforms? | default {})
        let preferred_platform_data = ($platforms | get $alpine_pref.prefer_platform | default {})

        # Replace ARM64 data with AMD64 musl data for Alpine
        mut alpine_platforms = $platforms
        $alpine_platforms = ($alpine_platforms | upsert linux-arm64 $preferred_platform_data)

        $tool_data | upsert platforms $alpine_platforms
    } else {
        $tool_data
    }
}