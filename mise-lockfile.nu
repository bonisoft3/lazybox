#!/usr/bin/env nu

# Generate cross-platform mise lockfiles with comprehensive platform support
# Can be used standalone or imported by other tools

use mise-platform.nu [get_platform_definitions]
use mise-core.nu []

# Run mise operations in a directory with environment setup
def run_mise_in_directory [dir: string, token: string, operations: closure] {
    let original_dir = (pwd)
    cd $dir

    with-env {GITHUB_TOKEN: $token} {
        try {
            do $operations
        } catch {|e|
            cd $original_dir
            error make {msg: $e.msg}
        }
    }

    cd $original_dir
}

# Trust and install mise tools
def trust_and_install_mise [] {
    ^mise trust -y -a -q
    ^mise uninstall -a
    ^mise install
}

# Get GitHub token with fallback
def get_github_token [] {
    try {
        (^gh auth token | str trim)
    } catch {
        ""
    }
}

# Verify GitHub auth and show warnings
def verify_github_auth [token: string] {
    if ($token | is-empty) {
        print "⚠️  Warning: No GitHub authentication found. May hit API rate limits."
        return false
    }

    try {
        ^gh auth status
        return true
    } catch {
        print "⚠️  Warning: No GitHub authentication. May hit API rate limits."
        return false
    }
}

# Export function to generate lockfile with expanded platforms (for mise-lazybox)
export def generate_expanded_lockfile [mise_toml: string, lockfile_path: string, update_lock: bool, real_lockfile_path: string, --reset] {
    let mise_toml_dir = ($mise_toml | path dirname)
    let github_token = (get_github_token)
    let auth_ok = (verify_github_auth $github_token)

    if not $auth_ok {
        return
    }

    # Handle reset/update logic
    if $reset or $update_lock {
        print "🔄 Generating lockfile with mise install..."

        try {
            run_mise_in_directory $mise_toml_dir $github_token {
                # Create empty lockfile so mise can update it
                touch "mise.lock"
                trust_and_install_mise
            }
        } catch {|e|
            print $"⚠️  Warning: Failed to run mise install: ($e.msg)"
            return
        }
    }

    # Now expand the lockfile with cross-platform data
    expand_lockfile_platforms $lockfile_path $github_token $update_lock $real_lockfile_path $reset

    print $"✅ Generated lockfile: ($lockfile_path)"
}

export def main [
    --mise-toml(-m): string = "./mise.toml"  # Path to mise.toml file
    --output(-o): string = ""  # Output lockfile path (default: mise.lock next to toml)
    --update(-u)  # Write the resulting lock file next to the toml file
    --reset(-r)  # Reset lockfile and reinstall tools before expanding
] {
    # Verify mise.toml exists
    if not ($mise_toml | path exists) {
        print $"❌ Error: mise.toml not found at ($mise_toml)"
        exit 1
    }

    let mise_toml_dir = ($mise_toml | path dirname)
    let mise_toml_stem = ($mise_toml | path parse | get stem)
    let default_lockfile_path = ($mise_toml_dir | path join $"($mise_toml_stem).lock")
    let lockfile_path = if ($output | is-empty) { $default_lockfile_path } else { $output }

    # Use the main lockfile expansion function
    if $reset {
        generate_expanded_lockfile $mise_toml $lockfile_path $update $default_lockfile_path --reset
    } else {
        generate_expanded_lockfile $mise_toml $lockfile_path $update $default_lockfile_path
    }
}

# Expand lockfile with cross-platform data
export def expand_lockfile_platforms [lockfile_path: string, github_token: string, update_lock: bool, real_lockfile_path: string, reset: bool = false] {
    let lockfile_content = (open $lockfile_path)
    mut new_lockfile = ""
    mut processed_tools = []
    let lines = ($lockfile_content | lines)
    mut current_tool = ""
    mut existing_platforms = {}

    # First pass: identify existing platforms (unless reset is true)
    if not $reset {
        mut in_tool = ""
        for line in $lines {
            if ($line | str starts-with "[[tools.") {
                $in_tool = ($line | str replace "[[tools." "" | str replace "]]" "" | str trim --char '"')
                $existing_platforms = ($existing_platforms | upsert $in_tool [])
            } else if ($line | str starts-with "[tools.") and ($line | str contains ".platforms.") {
                let platform_match = ($line | parse "[tools.\"{tool}\".platforms.{platform}]")
                if ($platform_match | length) > 0 {
                    let platform = $platform_match.0.platform
                    let current_platforms = ($existing_platforms | get $in_tool | default [])
                    $existing_platforms = ($existing_platforms | upsert $in_tool ($current_platforms | append $platform))
                }
            }
        }
    }

    # Second pass: expand platforms for GitHub tools
    for line in $lines {
        # Skip copying existing platform sections when reset is true to avoid duplicates
        let is_platform_section = ($line | str starts-with "[tools.") and ($line | str contains ".platforms.")

        if not ($reset and $is_platform_section) {
            $new_lockfile = ($new_lockfile + $line + "\n")
        }

        if ($line | str starts-with "[[tools.") {
            $current_tool = ($line | str replace "[[tools." "" | str replace "]]" "" | str trim --char '"')
        } else if ($line | str starts-with "url = ") and ($current_tool not-in $processed_tools) {
            $processed_tools = ($processed_tools | append $current_tool)
            let url = ($line | str replace "url = " "" | str trim --char '"')
            let existing_tool_platforms = if $reset {
                []
            } else {
                ($existing_platforms | get $current_tool | default [])
            }

            let tool_name = $current_tool
            let result = if ($url | str contains "github.com") {
                # Handle GitHub releases
                print $"🔍 Processing GitHub tool: ($tool_name)"
                (with-env {GITHUB_TOKEN: $github_token} {
                    generate_platform_variants $url $tool_name $existing_tool_platforms
                })
            } else if ($tool_name | str starts-with "aqua:") {
                # Handle aqua tools with non-GitHub URLs using registry metadata
                print $"🐳 Processing aqua tool: ($tool_name) with URL: ($url)"
                print $"   Existing platforms: ($existing_tool_platforms | str join ', ')"
                (generate_aqua_platform_variants $url $tool_name $existing_tool_platforms $github_token)
            } else {
                print $"❓ Skipping unknown tool type: ($tool_name)"
                {entries: "", platforms: []}
            }
            $new_lockfile = ($new_lockfile + $result.entries)
        }
    }

    # Only write to the real lockfile path if --update-lock is set
    if $update_lock {
        $new_lockfile | save -f $real_lockfile_path
    } else if $lockfile_path == $real_lockfile_path {
        # If we're using the real path but not --update-lock, still write it (existing lockfile case)
        $new_lockfile | save -f $lockfile_path
    }
}

# Generate platform variants for GitHub releases
export def generate_platform_variants [linux_url: string, tool: string, existing_platforms: list] {
    # Only process GitHub URLs for security (checksum verification)
    let github_match = ($linux_url | parse "https://github.com/{owner}/{repo}/releases/download/{version}/{file}")

    if ($github_match | length) == 0 {
        return {entries: "", platforms: []}
    }

    let owner = $github_match.0.owner
    let repo = $github_match.0.repo
    let version = $github_match.0.version

    # Get release assets from GitHub API using gh CLI
    let release_data = try {
        (^gh api $"repos/($owner)/($repo)/releases/tags/($version)" | from json)
    } catch {
        return {entries: "", platforms: []}
    }
    let assets = ($release_data | get assets? | default [])

    if ($assets | length) == 0 {
        return {entries: "", platforms: []}
    }

    mut result = ""
    mut found_platforms = []

    # Import platform detection - will create this next
    let platforms = (get_platform_definitions $tool)

    # Find and add platform variants (skip existing ones)
    for platform in $platforms {
        if ($platform.name in $existing_platforms) {
            continue
        }

        for pattern in $platform.patterns {
            let matches = ($assets | where {|asset| $asset.name | str contains $pattern})

            if ($matches | length) > 0 {
                # Prefer tar.gz, zip, and bare executables over package formats
                let tar_gz_matches = ($matches | where {|asset| $asset.name | str ends-with ".tar.gz"})
                let zip_matches = ($matches | where {|asset| $asset.name | str ends-with ".zip"})
                let exe_matches = ($matches | where {|asset| $asset.name | str ends-with ".exe"})
                let bare_matches = ($matches | where {|asset| ($asset.name | str contains ".") == false})

                let preferred_asset = if ($tar_gz_matches | length) > 0 {
                    $tar_gz_matches.0
                } else if ($zip_matches | length) > 0 {
                    $zip_matches.0
                } else if ($exe_matches | length) > 0 {
                    $exe_matches.0
                } else if ($bare_matches | length) > 0 {
                    $bare_matches.0
                } else {
                    $matches.0
                }

                let checksum_result = (get_checksum $preferred_asset.browser_download_url $assets)

                if ($checksum_result.checksum != "") {
                    $found_platforms = ($found_platforms | append $platform.name)
                    $result = ($result + $"\n[tools.\"($tool)\".platforms.($platform.name)]\n")
                    $result = ($result + $"checksum = \"($checksum_result.checksum)\"\n")
                    $result = ($result + $"size = ($preferred_asset.size)\n")
                    $result = ($result + $"url = \"($preferred_asset.browser_download_url)\"\n")

                    if $checksum_result.downloaded {
                        print $"📥 Downloaded ($repo) ($platform.name) for checksum"
                    }
                }
                break
            }
        }
    }

    {entries: $result, platforms: $found_platforms}
}

# Generate platform variants for aqua tools using registry metadata
export def generate_aqua_platform_variants [base_url: string, tool: string, existing_platforms: list, github_token: string] {
    # Extract tool name from aqua specification
    let tool_name = ($tool | str replace "aqua:" "")
    print $"🔧 Starting aqua expansion for ($tool_name)..."

    # Fetch aqua registry YAML for this tool
    let registry_url = $"https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/($tool_name)/registry.yaml"

    let registry_yaml = try {
        (with-env {GITHUB_TOKEN: $github_token} {
            curl -sL $registry_url
        })
    } catch {
        return {entries: "", platforms: []}
    }

    if ($registry_yaml | str trim | is-empty) {
        return {entries: "", platforms: []}
    }

    # Parse YAML to get package configuration
    let registry_data = try {
        ($registry_yaml | from yaml)
    } catch {
        return {entries: "", platforms: []}
    }

    let packages = ($registry_data | get packages? | default [])
    if ($packages | length) == 0 {
        return {entries: "", platforms: []}
    }

    let package = $packages.0  # Use first package

    # Get URL template and other metadata
    let url_template = if ($package | get url? | default "") != "" {
        ($package | get url)
    } else {
        # Handle version_overrides for tools like kubectl
        let version_overrides = ($package | get version_overrides? | default [])
        if ($version_overrides | length) > 0 {
            # Use the last override which typically has version_constraint: "true" (matches all)
            ($version_overrides | last | get url? | default "")
        } else {
            ""
        }
    }
    let format = ($package | get format? | default "tgz")
    let replacements = ($package | get replacements? | default {})
    let supported_envs = ($package | get supported_envs? | default [])

    # Use platform definitions from mise-platform.nu with aqua-aware ordering
    let platforms = (get_platform_definitions $tool)

    # Filter platforms based on supported_envs using aqua semantics
    # Each entry in supported_envs can be: OS only, ARCH only, or OS/ARCH
    let target_platforms = if ($supported_envs | length) == 0 {
        # No supported_envs specified - use common platforms
        $platforms | where {|platform| $platform.name in ["linux-amd64", "linux-arm64", "darwin-amd64", "darwin-arm64", "windows-amd64"]}
    } else {
        $platforms | where {|platform|
            let parts = ($platform.name | split row "-")
            if ($parts | length) == 2 {
                let os = $parts.0
                let arch = $parts.1

                # Check if this platform is supported by any entry in supported_envs
                ($supported_envs | any {|supported_env|
                    let os_arch = $"($os)/($arch)"
                    ($supported_env == $os_arch) or ($supported_env == $os) or ($supported_env == $arch) or ($supported_env == "all")
                })
            } else {
                false
            }
        }
    }

    print $"   Supported envs: ($supported_envs | str join ', ')"
    print $"   Target platforms: ($target_platforms | get name | str join ', ')"

    # Extract version from base URL
    let version = (extract_version_from_url $base_url $tool_name)
    print $"   Version extracted: ($version)"
    if ($version | is-empty) {
        print $"   ❌ Version extraction failed, skipping"
        return {entries: "", platforms: []}
    }

    mut result = ""
    mut found_platforms = []

    # Generate platform variants
    for platform in $target_platforms {
        print $"   Processing platform: ($platform.name)"
        if ($platform.name in $existing_platforms) {
            print $"     ⏭️ Skipping existing platform: ($platform.name)"
            continue
        }

        # Parse platform into OS and architecture
        let parts = ($platform.name | split row "-")
        if ($parts | length) != 2 {
            print $"     ❌ Invalid platform format: ($platform.name)"
            continue
        }
        let os = $parts.0
        let arch = $parts.1

        # Apply replacements from registry
        let mapped_os = ($replacements | get $os -o | default $os)
        let mapped_arch = ($replacements | get $arch -o | default $arch)
        print $"     OS: ($os) -> ($mapped_os), Arch: ($arch) -> ($mapped_arch)"

        # Build platform-specific URL using template variables
        let platform_url = ($url_template
            | str replace "{{.OS}}" $mapped_os
            | str replace "{{.Arch}}" $mapped_arch
            | str replace "{{.Version}}" $version
            | str replace "{{trimV .Version}}" ($version | str replace "v" "")
            | str replace "{{.Format}}" $format)
        print $"     URL: ($platform_url)"

        # Verify URL exists and get size
        print $"     🔍 Testing URL accessibility..."
        let head_result = try {
            (curl -sI -L $platform_url)  # Follow redirects with -L
        } catch {
            print $"     ❌ HTTP request failed"
            continue
        }

        print $"     HTTP response: ($head_result | lines | first)"
        # Look for final 200 response (after any redirects)
        let final_response_lines = ($head_result | lines | reverse)
        let has_200 = ($final_response_lines | any {|line| $line | str contains "200"})

        if $has_200 {
            print $"     ✅ URL accessible"
            let size_result = try {
                # Get content-length from the final response (after redirects)
                let final_headers = ($final_response_lines | take until {|line| $line | str contains "HTTP/"} | reverse)
                ($final_headers | where {|line| $line | str contains "content-length"} | first | parse "content-length: {size}" | get 0.size | into int)
            } catch {
                0
            }

            if $size_result > 0 {
                # Calculate checksum for smaller files
                let checksum_result = if $size_result < 100000000 {
                    try {
                        let content = (curl -sL $platform_url)
                        let checksum = ($content | hash sha256)
                        {checksum: $"sha256:($checksum)", downloaded: true}
                    } catch {
                        {checksum: $"blake3:placeholder-($platform.name)", downloaded: false}
                    }
                } else {
                    {checksum: $"blake3:placeholder-($platform.name)", downloaded: false}
                }

                $found_platforms = ($found_platforms | append $platform.name)
                $result = ($result + $"\n[tools.\"($tool)\".platforms.($platform.name)]\n")
                $result = ($result + $"checksum = \"($checksum_result.checksum)\"\n")
                $result = ($result + $"size = ($size_result)\n")
                $result = ($result + $"url = \"($platform_url)\"\n")

                if $checksum_result.downloaded {
                    print $"📥 Downloaded ($tool_name) ($platform.name) for checksum"
                }
            } else {
                print $"     ❌ Size is 0 or parsing failed"
            }
        } else {
            print "     ❌ URL not accessible (non 200 response)"
        }
    }

    {entries: $result, platforms: $found_platforms}
}

# Extract version from URL for different aqua tools
def extract_version_from_url [url: string, tool_name: string] {
    # Handle different URL patterns
    if ($url | str contains "docker-") {
        # Docker CLI pattern: docker-28.5.1.tgz
        let docker_match = ($url | parse --regex '.*/docker-([^/]+)\.(tgz|tar\.gz|zip)$')
        if ($docker_match | length) > 0 {
            return $docker_match.0.capture0
        }
    } else if ($url | str contains "github.com") {
        # GitHub release pattern: /download/v1.2.3/file.tar.gz
        let github_match = ($url | parse --regex '.*/download/([^/]+)/.*')
        if ($github_match | length) > 0 {
            return $github_match.0.capture0
        }
    }

    # Generic pattern: try to extract version from filename with extension
    let version_match = ($url | parse --regex '.*/([^/]+)\.(tgz|tar\.gz|zip)$')
    if ($version_match | length) > 0 {
        let filename = $version_match.0.capture0
        # Try to extract version-like pattern from filename
        let version_pattern = ($filename | parse --regex '.*[v-]?(\d+\.\d+(?:\.\d+)?).*')
        if ($version_pattern | length) > 0 {
            return $version_pattern.0.capture0
        }
    }

    # Catch-all: extract version from any path segment in the URL
    let path_match = ($url | parse --regex 'https?://[^/]+/(.*)')
    if ($path_match | length) > 0 {
        let path_segments = ($path_match.0.capture0 | split row "/")
        for segment in $path_segments {
            let version_matches = ($segment | parse --regex '^(v?)(\d+\.\d+(?:\.\d+)?)')
            if ($version_matches | length) > 0 {
                let v_prefix = $version_matches.0.capture0
                let version_number = $version_matches.0.capture1
                return $"($v_prefix)($version_number)"
            }
        }
    }

    ""
}

# Get checksum with multiple strategies
export def get_checksum [asset_url: string, assets: list] {
    let asset_name = ($asset_url | split row "/" | last)
    let checksum_file = ($asset_name + ".sha256")
    let checksum_assets = ($assets | where {|a| $a.name == $checksum_file})

    # Priority 1: Use published checksum file
    if ($checksum_assets | length) > 0 {
        try {
            let checksum_content = (curl -sL $checksum_assets.0.browser_download_url)
            let checksum = ($checksum_content | split row " " | first | str trim)
            return {checksum: $"sha256:($checksum)", downloaded: false}
        } catch {
            # Fall through to next method
        }
    }

    # Priority 2: Calculate checksum for files < 100MB
    let file_size = ($assets | where {|a| $a.browser_download_url == $asset_url} | get 0.size? | default 999999999)
    if $file_size < 100000000 {
        try {
            let content = (curl -sL $asset_url)
            let checksum = ($content | hash sha256)
            return {checksum: $"sha256:($checksum)", downloaded: true}
        } catch {
            # Fall through to skip
        }
    }

    # Priority 3: Skip entry entirely (no placeholder checksums)
    {checksum: "", downloaded: false}
}

