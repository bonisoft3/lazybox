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
    ^mise trust --quiet
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
    expand_lockfile_platforms $lockfile_path $github_token $update_lock $real_lockfile_path

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
export def expand_lockfile_platforms [lockfile_path: string, github_token: string, update_lock: bool, real_lockfile_path: string] {
    let lockfile_content = (open $lockfile_path)
    mut new_lockfile = ""
    mut processed_tools = []
    let lines = ($lockfile_content | lines)
    mut current_tool = ""
    mut existing_platforms = {}

    # First pass: identify existing platforms
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

    # Second pass: expand platforms for GitHub tools
    for line in $lines {
        $new_lockfile = ($new_lockfile + $line + "\n")

        if ($line | str starts-with "[[tools.") {
            $current_tool = ($line | str replace "[[tools." "" | str replace "]]" "" | str trim --char '"')
        } else if ($line | str starts-with "url = ") and ($line | str contains "github.com") and ($current_tool not-in $processed_tools) {
            $processed_tools = ($processed_tools | append $current_tool)
            let linux_url = ($line | str replace "url = " "" | str trim --char '"')
            let existing_tool_platforms = ($existing_platforms | get $current_tool | default [])

            let tool_name = $current_tool
            let result = (with-env {GITHUB_TOKEN: $github_token} {
                generate_platform_variants $linux_url $tool_name $existing_tool_platforms
            })
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

