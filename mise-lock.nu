#!/usr/bin/env nu

# Temporary cross-platform lockfile generator for mise
# This script will be dropped once mise natively supports cross-platform lockfiles
# See: https://github.com/jdx/mise/issues/lockfile-cross-platform
def main [--reset(-r)] {
    # Get GitHub token for mise commands
    let github_token = try {
        (^gh auth token | str trim)
    } catch {
        print "⚠️  Warning: No GitHub authentication found. Script may fail due to API rate limits."
        return
    }
    
    if $reset {
        with-env {GITHUB_TOKEN: $github_token} {
            ^mise uninstall -a
            "" | save -f mise.lock
            try { rm mise.alpine.lock }
            ^mise install
        }
    }
    
    # Verify GitHub authentication is available
    try {
        ^gh auth status
    } catch {
        print "⚠️  Warning: No GitHub authentication found. Script may fail due to API rate limits."
        return
    }
    
    let lockfile_content = (open mise.lock)
    mut new_lockfile = ""
    mut current_tool = ""
    mut total_tools = 0
    mut tools_with_platforms = 0
    mut all_platforms = []
    mut existing_platforms = {}
    
    # First pass: identify existing platforms to avoid duplicates
    mut in_tool = ""
    for line in ($lockfile_content | lines) {
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
    
    # Second pass: add new cross-platform entries
    mut processed_tools = []
    for line in ($lockfile_content | lines) {
        $new_lockfile = ($new_lockfile + $line + "\n")
        
        if ($line | str starts-with "[[tools.") {
            $current_tool = ($line | str replace "[[tools." "" | str replace "]]" "" | str trim --char '"')
            $total_tools = ($total_tools + 1)
        } else if ($line | str starts-with "url = ") and ($line | str contains "github.com") and ($current_tool not-in $processed_tools) {
            # Only process each tool once to avoid duplicates
            $processed_tools = ($processed_tools | append $current_tool)
            let linux_url = ($line | str replace "url = " "" | str trim --char '"')
            let existing_tool_platforms = ($existing_platforms | get $current_tool | default [])
            let result = (generate_platform_variants $linux_url $current_tool $existing_tool_platforms)
            $new_lockfile = ($new_lockfile + $result.entries)
            
            if ($result.platforms | length) > 0 {
                $tools_with_platforms = ($tools_with_platforms + 1)
                $all_platforms = ($all_platforms | append $result.platforms)
            }
        }
    }
    
    $new_lockfile | save -f mise.lock
    
    # Generate Alpine variant
    print "🏔️ Generating Alpine-specific lockfile..."
    let alpine_content = (generate_alpine_variant $new_lockfile)
    $alpine_content | save -f mise.alpine.lock
    
    # Print human-readable summary
    print "\n📊 Cross-platform lockfile generated!"
    print $"   Tools processed: ($total_tools)"
    print $"   Cross-platform support added: ($tools_with_platforms)"
    
    let unique_platforms = ($all_platforms | flatten | uniq | sort)
    if ($unique_platforms | length) > 0 {
        let platforms_str = ($unique_platforms | str join ", ")
        print $"   Platforms available: ($platforms_str)"
    }
}

# Generate platform variants for a given URL
def generate_platform_variants [linux_url: string, tool: string, existing_platforms: list] {
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
    
    let platforms = [
        {name: "linux-amd64", patterns: $linux_amd64_patterns},
        {name: "linux-arm64", patterns: $linux_arm64_patterns},
        {name: "darwin-amd64", patterns: ["x86_64-apple-darwin", "Darwin-x86_64", "darwin-amd64", "darwin_amd64"]},
        {name: "darwin-arm64", patterns: ["aarch64-apple-darwin", "darwin-arm64", "macos-arm64", "darwin_arm64", "Darwin-arm64", "darwin-aarch64"]},
        {name: "windows-amd64", patterns: ["x86_64-pc-windows-msvc", "windows-amd64", "win64", "windows_amd64", "Windows-x86_64"]}
    ]
    
    # Find and add platform variants (skip existing ones)
    for platform in $platforms {
        if ($platform.name in $existing_platforms) {
            continue
        }
        
        for pattern in $platform.patterns {
            let matches = ($assets | where {|asset| $asset.name | str contains $pattern})
            
            if ($matches | length) > 0 {
                # Pattern matching has already handled aqua preferences by ordering
                let filtered_matches = $matches
                
                # Prefer tar.gz, zip, and bare executables over package formats like .deb, .rpm
                let tar_gz_matches = ($filtered_matches | where {|asset| $asset.name | str ends-with ".tar.gz"})
                let zip_matches = ($filtered_matches | where {|asset| $asset.name | str ends-with ".zip"})
                let exe_matches = ($filtered_matches | where {|asset| $asset.name | str ends-with ".exe"})
                let bare_matches = ($filtered_matches | where {|asset| ($asset.name | str contains ".") == false})
                
                let preferred_asset = if ($tar_gz_matches | length) > 0 {
                    $tar_gz_matches.0
                } else if ($zip_matches | length) > 0 {
                    $zip_matches.0
                } else if ($exe_matches | length) > 0 {
                    $exe_matches.0
                } else if ($bare_matches | length) > 0 {
                    $bare_matches.0
                } else {
                    $filtered_matches.0
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

# Get checksum (prioritize published checksums, calculate for small files, skip large ones)
def get_checksum [asset_url: string, assets: list] {
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

# Get platform preference from aqua registry (gnu vs musl)
def get_aqua_platform_preference [tool_name: string, platform: string] {
    print $"DEBUG: Starting get_aqua_platform_preference for ($tool_name) ($platform)"
    
    # Parse platform to get os and arch for aqua registry matching
    let parts = ($platform | split row "-")
    if ($parts | length) != 2 {
        print $"DEBUG: Invalid platform format: ($platform), defaulting to musl"
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
            print $"DEBUG: Unknown OS ($os), defaulting to musl"
            return "musl"
        }
    }
    
    let goarch = match $arch {
        "amd64" => "amd64",
        "arm64" => "arm64",
        _ => {
            print $"DEBUG: Unknown arch ($arch), defaulting to musl"
            return "musl"
        }
    }
    
    # Fetch aqua registry YAML for this tool
    let registry_url = $"https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/($tool_name)/registry.yaml"
    
    let registry_yaml = try {
        ^curl -sL $registry_url
    } catch {
        print $"DEBUG: Failed to fetch aqua registry for ($tool_name), defaulting to musl"
        return "musl"
    }
    
    if ($registry_yaml | str trim | is-empty) {
        print $"DEBUG: Empty registry response for ($tool_name), defaulting to musl"
        return "musl"
    }
    
    # Parse YAML to find overrides
    let registry_data = try {
        ($registry_yaml | from yaml)
    } catch {
        print $"DEBUG: Failed to parse YAML for ($tool_name), defaulting to musl"
        return "musl"
    }
    
    # Look for overrides in the packages
    let packages = ($registry_data | get packages? | default [])
    if ($packages | length) == 0 {
        print $"DEBUG: No packages found in registry for ($tool_name), defaulting to musl"
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
                    print $"DEBUG: Found aqua registry gnu override in asset for ($tool_name) on ($goos)/($goarch)"
                    return "gnu"
                }
                
                # Check replacements in this override
                let override_replacements = ($override | get replacements? | default {})
                for repl_key in ($override_replacements | columns) {
                    let repl_value = ($override_replacements | get $repl_key)
                    if ($repl_value | str contains "gnu") {
                        print $"DEBUG: Found aqua registry gnu override in replacements for ($tool_name) on ($goos)/($goarch): ($repl_key) -> ($repl_value)"
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
                # This tool has a musl->gnu replacement, but we need to check if it applies to our platform
                # For now, assume it means gnu is preferred (more complex logic could check asset patterns)
                print $"DEBUG: Found musl->gnu replacement in registry for ($tool_name), preferring gnu"
                return "gnu"
            }
        }
    }
    
    print $"DEBUG: No gnu overrides found for ($tool_name) on ($platform), defaulting to musl"
    "musl"
}

# Generate Alpine variant with intelligent ARM64 fallback logic
def generate_alpine_variant [lockfile_content: string] {
    let lines = ($lockfile_content | lines)
    mut alpine_content = ""
    mut current_tool = ""
    mut tool_platforms = {}
    mut in_platforms = false
    
    # First pass: collect all platform entries per tool
    for line in $lines {
        if ($line | str starts-with "[[tools.") {
            $current_tool = ($line | str replace "[[tools." "" | str replace "]]" "" | str trim --char '"')
            $tool_platforms = ($tool_platforms | upsert $current_tool {})
            $in_platforms = false
        } else if ($line | str starts-with $"[tools.\"($current_tool)\".platforms.") {
            let platform_match = ($line | parse $"[tools.\"($current_tool)\".platforms.{platform}]")
            if ($platform_match | length) > 0 {
                let platform = $platform_match.0.platform
                $in_platforms = true
                let current_platforms = ($tool_platforms | get $current_tool | default {})
                $tool_platforms = ($tool_platforms | upsert $current_tool ($current_platforms | upsert $platform {}))
            }
        } else if $in_platforms and ($line | str starts-with "checksum = ") {
            let checksum = ($line | str replace 'checksum = "' '' | str replace '"' '')
            let platform_entries = ($tool_platforms | get $current_tool)
            let last_platform = ($platform_entries | items {|k, v| {key: $k, value: $v}} | last)
            if ($last_platform | is-not-empty) {
                let platform_name = $last_platform.key
                let current_platforms = ($tool_platforms | get $current_tool)
                let platform_data = ($current_platforms | get $platform_name | default {})
                $tool_platforms = ($tool_platforms | upsert $current_tool ($current_platforms | upsert $platform_name ($platform_data | upsert checksum $checksum)))
            }
        } else if $in_platforms and ($line | str starts-with "size = ") {
            let size = ($line | str replace 'size = ' '' | into int)
            let platform_entries = ($tool_platforms | get $current_tool)
            let last_platform = ($platform_entries | items {|k, v| {key: $k, value: $v}} | last)
            if ($last_platform | is-not-empty) {
                let platform_name = $last_platform.key
                let current_platforms = ($tool_platforms | get $current_tool)
                let platform_data = ($current_platforms | get $platform_name | default {})
                $tool_platforms = ($tool_platforms | upsert $current_tool ($current_platforms | upsert $platform_name ($platform_data | upsert size $size)))
            }
        } else if $in_platforms and ($line | str starts-with "url = ") {
            let url = ($line | str replace 'url = "' '' | str replace '"' '')
            let platform_entries = ($tool_platforms | get $current_tool)
            let last_platform = ($platform_entries | items {|k, v| {key: $k, value: $v}} | last)
            if ($last_platform | is-not-empty) {
                let platform_name = $last_platform.key
                let current_platforms = ($tool_platforms | get $current_tool)
                let platform_data = ($current_platforms | get $platform_name | default {})
                $tool_platforms = ($tool_platforms | upsert $current_tool ($current_platforms | upsert $platform_name ($platform_data | upsert url $url)))
            }
        }
    }
    
    # Second pass: generate Alpine content with ARM64 fallback logic
    mut current_tool = ""
    mut skip_current_platform = false
    
    for line in $lines {
        if ($line | str starts-with "[[tools.") {
            $current_tool = ($line | str replace "[[tools." "" | str replace "]]" "" | str trim --char '"')
            $skip_current_platform = false
            $alpine_content = ($alpine_content + $line + "\n")
        } else if ($line | str starts-with "version = ") or ($line | str starts-with "backend = ") {
            if not $skip_current_platform {
                $alpine_content = ($alpine_content + $line + "\n")
            }
        } else if ($line | str starts-with $"[tools.\"($current_tool)\".platforms.") {
            # Apply Alpine ARM64 fallback logic
            let platform_match = ($line | parse $"[tools.\"($current_tool)\".platforms.{platform}]")
            if ($platform_match | length) > 0 {
                let platform = $platform_match.0.platform
                let tool_data = ($tool_platforms | get $current_tool | default {})
                
                if ($platform == "linux-arm64") {
                    # Check if we have musl-specific x86_64 and arm64 variants
                    let linux_amd64_data = ($tool_data | get linux-amd64? | default {})
                    let linux_arm64_data = ($tool_data | get linux-arm64? | default {})
                    let linux_amd64_url = ($linux_amd64_data | get url? | default "")
                    let linux_arm64_url = ($linux_arm64_data | get url? | default "")
                    
                    let has_musl_amd64 = ($linux_amd64_url | str contains "musl")
                    let has_musl_arm64 = ($linux_arm64_url | str contains "musl")
                    let has_gnu_arm64 = ($linux_arm64_url | str contains "gnu")
                    
                    # If there's musl x86_64 but no musl arm64 (only gnu arm64), fall back to x86_64 musl
                    if $has_musl_amd64 and (not $has_musl_arm64) and $has_gnu_arm64 {
                        print $"🔄 Alpine ARM64 fallback: ($current_tool) using x86_64 musl instead of arm64 gnu"
                        # Replace this ARM64 platform with x86_64 musl data
                        let amd64_checksum = ($linux_amd64_data | get checksum? | default "")
                        let amd64_size = ($linux_amd64_data | get size? | default 0)
                        $alpine_content = ($alpine_content + $line + "\n")
                        $alpine_content = ($alpine_content + $"checksum = \"($amd64_checksum)\"\n")
                        $alpine_content = ($alpine_content + $"size = ($amd64_size)\n")
                        $alpine_content = ($alpine_content + $"url = \"($linux_amd64_url)\"\n")
                        $alpine_content = ($alpine_content + "\n")
                        # Skip the original ARM64 platform data by setting skip flag
                        $skip_current_platform = true
                        continue
                    }
                }
                
                # Reset skip flag for new platform section
                $skip_current_platform = false
                $alpine_content = ($alpine_content + $line + "\n")
            }
        } else if ($line | str starts-with "[tools.") and ($line | str contains ".platforms.") {
            # This is a new platform section for a different tool - reset skip flag
            $skip_current_platform = false
            $alpine_content = ($alpine_content + $line + "\n")
        } else {
            # Include line only if we're not skipping current platform
            if not $skip_current_platform {
                $alpine_content = ($alpine_content + $line + "\n")
            }
        }
    }
    
    $alpine_content
}
