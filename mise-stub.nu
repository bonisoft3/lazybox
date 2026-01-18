#!/usr/bin/env nu

# Generate a single mise tool stub with cross-platform support
# Creates tool, tool.toml, and optionally tool.musl.toml for Alpine

use mise-platform.nu *
use mise-core.nu [build_binary_mapping, find_tool_binaries, clean_binary_name]

# Export high-level functions for use by mise-lazybox.nu
export def create_tool_stubs [tools_data: list, output_dir: string, force: bool, alpine: bool] {
    let created_stubs = (
        $tools_data
        | each {|tool| generate_single_stub_from_data $tool $output_dir $force $alpine}
        | where {|result| $result.created}
    )
    $created_stubs
}

export def get_binary_mapping_for_tools [] {
    build_binary_mapping
}

export def generate_single_stub_from_data [tool_data: record, output_dir: string, force: bool, alpine: bool] {
    # Convert tool_data format from mise-lazybox to the format expected by generate_single_stub
    let binary_info = {
        clean_name: $tool_data.name,
        original_name: $tool_data.original_name
    }

    let converted_tool_data = {
        tool_spec: $tool_data.tool_spec,
        version: $tool_data.version,
        platforms: $tool_data.platforms
    }

    generate_single_stub $binary_info $converted_tool_data $output_dir $force $alpine
}

export def parse_lockfile_and_map_binaries [lockfile: string] {
    let binary_map = (build_binary_mapping)
    let tools_data = (parse_lockfile_for_tools $lockfile $binary_map)
    $tools_data
}

export def main [
    tool_spec: string  # Tool specification (e.g., "aqua:casey/just@1.42.4" or from lockfile)
    --output-dir(-o): string = ""  # Output directory for stub (default: ~/.local/share/mise/stubs)
    --lockfile(-l): string = "./mise.lock"  # Lockfile to read tool data from
    --force(-f)  # Overwrite existing stub
    --alpine(-a)  # Generate Alpine-specific .musl.toml variant
] {
    let default_output_dir = ($env.HOME | path join ".local/share/mise/stubs")
    let stubs_dir = if ($output_dir | is-empty) { $default_output_dir } else { $output_dir }

    # Parse tool spec
    let tool_parts = ($tool_spec | split row "@")
    let tool_name = $tool_parts.0
    let tool_version = if ($tool_parts | length) > 1 { $tool_parts.1 } else { "" }

    print $"🔧 Generating stub for ($tool_spec)..."

    # Find tool data from lockfile
    let tool_data = (find_tool_in_lockfile $tool_name $lockfile)
    if ($tool_data | is-empty) {
        print $"❌ Error: Tool ($tool_name) not found in lockfile ($lockfile)"
        exit 1
    }

    # Get binary mapping for this tool
    let binary_map = (build_binary_mapping)
    let tool_binaries = (find_tool_binaries $tool_name $binary_map)

    if ($tool_binaries | is-empty) {
        print $"❌ Error: No binaries found for tool ($tool_name). Run 'mise install' first."
        exit 1
    }

    ^mkdir -p $stubs_dir

    mut created_stubs = []

    # Generate stubs for each binary
    for binary_info in $tool_binaries {
        let stub_result = (generate_single_stub $binary_info $tool_data $stubs_dir $force $alpine)
        if $stub_result.created {
            $created_stubs = ($created_stubs | append $stub_result)
        }
    }

    if ($created_stubs | length) > 0 {
        print $"\n📦 Created ($created_stubs | length) stub(s) in ($stubs_dir)"
        let stub_names = ($created_stubs | get name | str join ", ")
        print $"   Tools: ($stub_names)"
        print $"\n💡 Add to PATH: export PATH=\"($stubs_dir):$PATH\""
    } else {
        print "⚠️  No new stubs created (use --force to overwrite existing)"
    }
}

# Find tool data in lockfile
def find_tool_in_lockfile [tool_name: string, lockfile: string] {
    if not ($lockfile | path exists) {
        return {}
    }

    let lockfile_content = (open $lockfile)
    let lines = ($lockfile_content | lines)
    mut current_tool = ""
    mut current_platforms = {}
    mut tool_version = ""

    for line in $lines {
        if ($line | str starts-with "[[tools.") {
            let line_tool = ($line | str replace "[[tools." "" | str replace "]]" "" | str trim --char '"')
            if $line_tool == $tool_name {
                $current_tool = $line_tool
                $current_platforms = {}
                $tool_version = ""
            } else {
                $current_tool = ""
            }
        } else if ($current_tool == $tool_name) {
            if ($line | str starts-with "version = ") {
                $tool_version = ($line | str replace 'version = "' '' | str replace '"' '')
            } else if ($line | str starts-with $"[tools.\"($tool_name)\".platforms.") {
                let platform_match = ($line | parse $"[tools.\"($tool_name)\".platforms.{platform}]")
                if ($platform_match | length) > 0 {
                    let platform = $platform_match.0.platform
                    $current_platforms = ($current_platforms | upsert $platform {})
                }
            } else if ($line | str starts-with "url = ") {
                let url = ($line | str replace 'url = "' '' | str replace '"' '')
                let last_platform = ($current_platforms | items {|k, v| {key: $k, value: $v}} | last)
                if ($last_platform | is-not-empty) {
                    let platform_name = $last_platform.key
                    let platform_data = ($current_platforms | get $platform_name | default {})
                    $current_platforms = ($current_platforms | upsert $platform_name ($platform_data | upsert url $url))
                }
            } else if ($line | str starts-with "checksum = ") {
                let checksum = ($line | str replace 'checksum = "' '' | str replace '"' '')
                let last_platform = ($current_platforms | items {|k, v| {key: $k, value: $v}} | last)
                if ($last_platform | is-not-empty) {
                    let platform_name = $last_platform.key
                    let platform_data = ($current_platforms | get $platform_name | default {})
                    $current_platforms = ($current_platforms | upsert $platform_name ($platform_data | upsert checksum $checksum))
                }
            } else if ($line | str starts-with "size = ") {
                let size = ($line | str replace 'size = ' '' | into int)
                let last_platform = ($current_platforms | items {|k, v| {key: $k, value: $v}} | last)
                if ($last_platform | is-not-empty) {
                    let platform_name = $last_platform.key
                    let platform_data = ($current_platforms | get $platform_name | default {})
                    $current_platforms = ($current_platforms | upsert $platform_name ($platform_data | upsert size $size))
                }
            }
        }
    }

    if ($current_tool == $tool_name) and (($current_platforms | items {|k, v| {key: $k, value: $v}} | length) > 0) {
        {
            tool_spec: $tool_name,
            version: $tool_version,
            platforms: $current_platforms
        }
    } else {
        {}
    }
}

# Generate a single stub (binary + TOML files + Alpine variant)
def generate_single_stub [binary_info: record, tool_data: record, output_dir: string, force: bool, alpine: bool] {
    let tool_name = $binary_info.clean_name
    let stub_path = ($output_dir | path join $tool_name)
    let toml_path = ($output_dir | path join $"($tool_name).toml")
    let musl_toml_path = ($output_dir | path join $"($tool_name).musl.toml")

    if ($stub_path | path exists) and (not $force) {
        return {name: $tool_name, created: false}
    }

    # Generate the main TOML configuration file
    let toml_content = (build_toml_content $binary_info $tool_data false)
    $toml_content | save -f $toml_path

    # Generate Alpine-specific TOML if requested or if Alpine variants exist
    let alpine_tool_data = (generate_alpine_platform_data $tool_data)
    let needs_alpine_variant = $alpine or (($alpine_tool_data | get platforms) != ($tool_data | get platforms))

    if $needs_alpine_variant {
        let musl_toml_content = (build_toml_content $binary_info $alpine_tool_data true)
        $musl_toml_content | save -f $musl_toml_path
    }

    # Generate the shell script wrapper with Alpine detection
    let wrapper_content = (build_wrapper_content $tool_name $needs_alpine_variant)
    $wrapper_content | save -f $stub_path
    ^chmod +x $stub_path

    return {name: $tool_name, created: true}
}

# Build wrapper script content with Alpine detection
def build_wrapper_content [tool_name: string, has_alpine_variant: bool] {
    mut content = "#!/bin/sh\n"
    $content = ($content + "# Get the directory where this script lives\n")
    $content = ($content + "DIR=\"\$(dirname \"\$(readlink -f \"\$0\")\")\" \n")
    $content = ($content + "\n")

    if $has_alpine_variant {
        $content = ($content + "# Check for Alpine and prefer musl variant if available\n")
        $content = ($content + "if [ -f /etc/alpine-release ] && [ -f \"\$DIR/($tool_name).musl.toml\" ]; then\n")
        $content = ($content + "    mise trust -y -a -q .\n")
        $content = ($content + $"    exec mise tool-stub \"\$DIR/($tool_name).musl.toml\" \"\$@\"\n")
        $content = ($content + "else\n")
        $content = ($content + "    mise trust -y -a -q .\n")
        $content = ($content + $"    exec mise tool-stub \"\$DIR/($tool_name).toml\" \"\$@\"\n")
        $content = ($content + "fi\n")
    } else {
        $content = ($content + "# Run mise tool-stub with trusted config\n")
        $content = ($content + "mise trust -y -a -q .\n")
        $content = ($content + $"exec mise tool-stub \"\$DIR/($tool_name).toml\" \"\$@\"\n")
    }

    $content
}

# Build TOML configuration content
def build_toml_content [binary_info: record, tool_data: record, is_musl_variant: bool] {
    mut content = if $is_musl_variant {
        "# Auto-generated Alpine/musl stub for ($binary_info.clean_name)\n\n"
    } else {
        "# Auto-generated stub for ($binary_info.clean_name)\n\n"
    }

    $content = ($content + $"version = \"($tool_data.version)\"\n")
    $content = ($content + $"bin = \"($binary_info.original_name)\"\n")

    let platforms = ($tool_data | get platforms? | default {})
    if ($platforms | items {|k, v| {key: $k, value: $v}} | length) > 0 {
        $content = ($content + "\n# Platform configurations\n")

        for platform in ($platforms | items {|k, v| {key: $k, value: $v}}) {
            let platform_name = $platform.key
            let platform_data = $platform.value

            $content = ($content + $"[platforms.($platform_name)]\n")

            if ($platform_data | get url? | is-not-empty) {
                $content = ($content + $"url = \"($platform_data.url)\"\n")
            }

            if ($platform_data | get checksum? | is-not-empty) {
                $content = ($content + $"checksum = \"($platform_data.checksum)\"\n")
            }

            if ($platform_data | get size? | is-not-empty) {
                $content = ($content + $"size = ($platform_data.size)\n")
            }

            # Handle Windows .exe extension
            if ($platform_name | str contains "windows") and (not ($binary_info.clean_name | str ends-with ".exe")) {
                $content = ($content + $"bin = \"($binary_info.clean_name).exe\"\n")
            }

            $content = ($content + "\n")
        }
    }

    $content
}





# Parse lockfile and combine with binary mapping (used by mise-lazybox)
def parse_lockfile_for_tools [lockfile: string, binary_map: record] {
    let lockfile_content = (open $lockfile)
    let lines = ($lockfile_content | lines)
    mut tools = []
    mut current_tool = {tool_spec: "", version: ""}
    mut current_platforms = {}

    for line in $lines {
        if ($line | str starts-with "[[tools.") {
            # Save previous tool if it has platforms and binaries
            if ($current_tool.tool_spec != "") and (($current_platforms | items {|k, v| {key: $k, value: $v}} | length) > 0) {
                let tool_binaries = (find_tool_binaries $current_tool.tool_spec $binary_map)
                for binary_info in $tool_binaries {
                    $tools = ($tools | append {
                        name: $binary_info.clean_name,
                        original_name: $binary_info.original_name,
                        tool_spec: $current_tool.tool_spec,
                        version: $current_tool.version,
                        platforms: $current_platforms
                    })
                }
            }

            # Start new tool
            let tool_spec = ($line | str replace "[[tools." "" | str replace "]]" "" | str trim --char '"')
            $current_tool = {
                tool_spec: $tool_spec,
                version: ""
            }
            $current_platforms = {}

        } else if ($current_tool.tool_spec != "") and ($line | str starts-with "version = ") {
            let version = ($line | str replace 'version = "' '' | str replace '"' '')
            $current_tool = ($current_tool | upsert version $version)

        } else if ($current_tool.tool_spec != "") and ($line | str starts-with $"[tools.\"($current_tool.tool_spec)\".platforms.") {
            let platform_match = ($line | parse $"[tools.\"($current_tool.tool_spec)\".platforms.{platform}]")
            if ($platform_match | length) > 0 {
                let platform = $platform_match.0.platform
                $current_platforms = ($current_platforms | upsert $platform {})
            }

        } else if ($current_tool.tool_spec != "") and ($line | str starts-with "url = ") {
            let url = ($line | str replace 'url = "' '' | str replace '"' '')
            let last_platform = ($current_platforms | items {|k, v| {key: $k, value: $v}} | last)
            if ($last_platform | is-not-empty) {
                let platform_name = $last_platform.key
                let platform_data = ($current_platforms | get $platform_name | default {})
                $current_platforms = ($current_platforms | upsert $platform_name ($platform_data | upsert url $url))
            }

        } else if ($current_tool.tool_spec != "") and ($line | str starts-with "checksum = ") {
            let checksum = ($line | str replace 'checksum = "' '' | str replace '"' '')
            let last_platform = ($current_platforms | items {|k, v| {key: $k, value: $v}} | last)
            if ($last_platform | is-not-empty) {
                let platform_name = $last_platform.key
                let platform_data = ($current_platforms | get $platform_name | default {})
                $current_platforms = ($current_platforms | upsert $platform_name ($platform_data | upsert checksum $checksum))
            }

        } else if ($current_tool.tool_spec != "") and ($line | str starts-with "size = ") {
            let size = ($line | str replace 'size = ' '' | into int)
            let last_platform = ($current_platforms | items {|k, v| {key: $k, value: $v}} | last)
            if ($last_platform | is-not-empty) {
                let platform_name = $last_platform.key
                let platform_data = ($current_platforms | get $platform_name | default {})
                $current_platforms = ($current_platforms | upsert $platform_name ($platform_data | upsert size $size))
            }
        }
    }

    # Don't forget the last tool
    if ($current_tool.tool_spec != "") and (($current_platforms | items {|k, v| {key: $k, value: $v}} | length) > 0) {
        let tool_binaries = (find_tool_binaries $current_tool.tool_spec $binary_map)
        for binary_info in $tool_binaries {
            $tools = ($tools | append {
                name: $binary_info.clean_name,
                original_name: $binary_info.original_name,
                tool_spec: $current_tool.tool_spec,
                version: $current_tool.version,
                platforms: $current_platforms
            })
        }
    }

    $tools
}
