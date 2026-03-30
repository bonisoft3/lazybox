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
        platforms: $tool_data.platforms,
        strip_components: ($tool_data | get strip_components? | default null)
    }

    generate_single_stub $binary_info $converted_tool_data $output_dir $force $alpine
}

def derive_default_binary_name [tool_spec: string] {
    let normalized = (
        $tool_spec
        | str replace "aqua:" ""
        | str replace "github:" ""
        | str replace "http:" ""
    )
    $normalized | split row "/" | last
}

def fallback_binary_names_for_tool [tool_spec: string] {
    match $tool_spec {
        "aqua:Byron/dua-cli" => ["dua"],
        "aqua:docker/cli" => ["docker"],
        "aqua:docker/buildx" => ["docker-cli-plugin-docker-buildx"],
        "aqua:docker/compose" => ["docker-cli-plugin-docker-compose"],
        "aqua:astral-sh/uv" => ["uv", "uvx"],
        "aqua:bufbuild/buf" => ["buf", "protoc-gen-buf-breaking", "protoc-gen-buf-lint"],
        "aqua:GoogleContainerTools/skaffold" => ["skaffold-darwin-arm64"],
        "github:BurntSushi/ripgrep" => ["rg"],
        "github:lvillis/tcping-rs" => ["tcping"],
        "github:nushell/nushell" => [
            "nu",
            "nu_plugin_custom_values",
            "nu_plugin_example",
            "nu_plugin_formats",
            "nu_plugin_gstat",
            "nu_plugin_inc",
            "nu_plugin_polars",
            "nu_plugin_query",
            "nu_plugin_stress_internals",
        ],
        _ => [ (derive_default_binary_name $tool_spec) ]
    }
}

def build_binary_info_list [names: list] {
    $names | each {|name|
        {
            original_name: $name,
            clean_name: (clean_binary_name $name)
        }
    }
}

def should_include_bin_line [tool_spec: string, binary_name: string] {
    if $tool_spec == "github:mikefarah/yq" and $binary_name == "yq" { false } else { true }
}

# Check if a URL points to an archive file
def is_archive_url [url: string] {
    ($url | str ends-with ".tar.gz") or ($url | str ends-with ".tgz") or ($url | str ends-with ".tar.xz") or ($url | str ends-with ".tar.bz2") or ($url | str ends-with ".zip")
}

# Check if any platform in a tool has archive URLs
def has_archive_platforms [platforms: record] {
    $platforms | columns | any {|k|
        let url = ($platforms | get $k | get url? | default "")
        is_archive_url $url
    }
}

export def write_extra_stub_artifacts [tools_data: list, output_dir: string, alpine: bool] {
    let yq_entry = (
        $tools_data
        | where tool_spec == "github:mikefarah/yq"
        | where name == "yq"
        | first
    )

    if ($yq_entry | is-empty) {
        return
    }

    let yq_tool_data = {
        tool_spec: $yq_entry.tool_spec,
        version: $yq_entry.version,
        platforms: $yq_entry.platforms,
        strip_components: ($yq_entry | get strip_components? | default null)
    }

    let yq_binary_info = { original_name: "yq", clean_name: "yq" }
    let yq_toml_content = (build_toml_content $yq_binary_info $yq_tool_data false)
    $yq_toml_content | save -f ($output_dir | path join "yq_darwin_arm64")

    let install_binary_info = { original_name: "install-man-page.sh", clean_name: "install-man-page.sh" }
    let install_toml_content = (build_toml_content $install_binary_info $yq_tool_data false)
    $install_toml_content | save -f ($output_dir | path join "install-man-page.sh.toml")

    let alpine_tool_data = (generate_alpine_platform_data $yq_tool_data)
    let needs_alpine_variant = $alpine or (($alpine_tool_data | get platforms) != ($yq_tool_data | get platforms))
    if $needs_alpine_variant {
        let install_musl_content = (build_toml_content $install_binary_info $alpine_tool_data true)
        $install_musl_content | save -f ($output_dir | path join "install-man-page.sh.musl.toml")
    }
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

# Extract platforms from both legacy and inline lockfile formats
def extract_platforms_from_entry [entry: record] {
    let base_platforms = ($entry | get platforms? | default {})
    let base_record = if ($base_platforms | describe | str starts-with "record") {
        $base_platforms
    } else {
        {}
    }

    let inline_platforms = (
        $entry
        | columns
        | where {|key| $key | str starts-with "platforms."}
        | reduce -f {} {|key, acc|
            let value = ($entry | get $key)
            $acc | upsert ($key | str replace "platforms." "") $value
        }
    )

    $base_record | merge $inline_platforms
}

# Find tool data in lockfile
def find_tool_in_lockfile [tool_name: string, lockfile: string] {
    if not ($lockfile | path exists) {
        return {}
    }

    let lockfile_text = (open --raw $lockfile)
    let lockfile_toml = try {
        $lockfile_text | from toml
    } catch {
        return {}
    }

    let tools_table = ($lockfile_toml | get tools? | default {})
    let tool_entries = try {
        $tools_table | get $tool_name
    } catch {
        null
    }
    if $tool_entries == null {
        return {}
    }
    let entries_is_list = (
        ($tool_entries | describe | str starts-with "list")
        or ($tool_entries | describe | str starts-with "table")
    )
    let entry = if $entries_is_list { $tool_entries | first } else { $tool_entries }
    let platforms = (extract_platforms_from_entry $entry)
    if ($platforms | columns | length) == 0 {
        return {}
    }

    {
        tool_spec: $tool_name,
        version: ($entry | get version? | default ""),
        platforms: $platforms
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
    if $tool_name == "docker" {
        return (build_docker_wrapper_content)
    }
    if $tool_name == "yq" {
        return (build_yq_wrapper_content)
    }

    mut content = "#!/bin/sh\n"
    $content = ($content + "# Get the directory where this script lives\n")
    $content = ($content + "DIR=\"\$(dirname \"\$(readlink -f \"\$0\")\")\" \n")
    $content = ($content + "\n")

    if $has_alpine_variant {
        $content = ($content + "# Check for Alpine and prefer musl variant if available\n")
        $content = ($content + $"if [ -f /etc/alpine-release ] && [ -f \"\$DIR/($tool_name).musl.toml\" ]; then\n")
        $content = ($content + "    \"\$DIR/../libexec/lazy-mise\" trust -y -a -q .\n")
        $content = ($content + $"    MISE_LOCKED=0 exec \"\$DIR/../libexec/lazy-mise\" tool-stub \"\$DIR/($tool_name).musl.toml\" \"\$@\"\n")
        $content = ($content + "else\n")
        $content = ($content + "    \"\$DIR/../libexec/lazy-mise\" trust -y -a -q .\n")
        $content = ($content + $"    MISE_LOCKED=0 exec \"\$DIR/../libexec/lazy-mise\" tool-stub \"\$DIR/($tool_name).toml\" \"\$@\"\n")
        $content = ($content + "fi\n")
    } else {
        $content = ($content + "# Run mise tool-stub with trusted config\n")
        $content = ($content + "\"\$DIR/../libexec/lazy-mise\" trust -y -a -q .\n")
        $content = ($content + $"MISE_LOCKED=0 exec \"\$DIR/../libexec/lazy-mise\" tool-stub \"\$DIR/($tool_name).toml\" \"\$@\"\n")
    }

    $content
}

def build_docker_wrapper_content [] {
    mut content = "#!/bin/sh\n"
    $content = ($content + "# Get the directory where this script lives\n")
    $content = ($content + "DIR=\"\$(dirname \"\$(readlink -f \"\$0\")\")\" \n")
    $content = ($content + "\n")
    $content = ($content + "mkdir -p $HOME/.docker/cli-plugins/\n")
    $content = ($content + "if [ ! -x $HOME/.docker/cli-plugins/docker-compose ]; then\n")
    $content = ($content + " ln -sf $DIR/docker-cli-plugin-docker-compose $HOME/.docker/cli-plugins/docker-compose\n")
    $content = ($content + "fi\n")
    $content = ($content + "if [ ! -x $HOME/.docker/cli-plugins/docker-buildx ]; then\n")
    $content = ($content + " ln -sf $DIR/docker-cli-plugin-docker-buildx $HOME/.docker/cli-plugins/docker-buildx\n")
    $content = ($content + "fi\n")
    $content = ($content + "# Check for Alpine and prefer musl variant if available\n")
    $content = ($content + "if [ -f /etc/alpine-release ] && [ -f \"$DIR/docker.musl.toml\" ]; then\n")
    $content = ($content + "    \"$DIR/../libexec/lazy-mise\" trust -y -a -q .\n")
    $content = ($content + "    MISE_LOCKED=0 exec \"$DIR/../libexec/lazy-mise\" tool-stub \"$DIR/docker.musl.toml\" \"$@\"\n")
    $content = ($content + "else\n")
    $content = ($content + "    \"$DIR/../libexec/lazy-mise\" trust -y -a -q .\n")
    $content = ($content + "    MISE_LOCKED=0 exec \"$DIR/../libexec/lazy-mise\" tool-stub \"$DIR/docker.toml\" \"$@\"\n")
    $content = ($content + "fi\n")
    $content
}

def build_yq_wrapper_content [] {
    mut content = "#!/bin/sh\n"
    $content = ($content + "# Get the directory where this script lives\n")
    $content = ($content + "DIR=\"\$(dirname \"\$(readlink -f \"\$0\")\")\"\n")
    $content = ($content + "\n")
    $content = ($content + "bin=yq_$(uname -s | tr A-Z a-z)_$(uname -m | sed -e 's/x86_64/amd64/; s/aarch64/arm64/')\n")
    $content = ($content + "cp $DIR/yq.toml $DIR/$bin\n")
    $content = ($content + "# Run mise tool-stub with trusted config\n")
    $content = ($content + "\"$DIR/../libexec/lazy-mise\" trust -y -a -q .\n")
    $content = ($content + "MISE_LOCKED=0 exec \"$DIR/../libexec/lazy-mise\" tool-stub \"$DIR/$bin\" \"$@\"\n")
    $content
}

# Build TOML configuration content
def build_toml_content [binary_info: record, tool_data: record, is_musl_variant: bool] {
    mut content = if $is_musl_variant {
        "# Auto-generated Alpine/musl stub for ($binary_info.clean_name)\n\n"
    } else {
        "# Auto-generated stub for ($binary_info.clean_name)\n\n"
    }

    $content = ($content + $"tool = \"($tool_data.tool_spec)\"\n")
    $content = ($content + $"version = \"($tool_data.version)\"\n")
    if (should_include_bin_line $tool_data.tool_spec $binary_info.original_name) {
        $content = ($content + $"bin = \"($binary_info.original_name)\"\n")
    }
    let strip = ($tool_data | get strip_components? | default null)
    if $strip != null {
        $content = ($content + $"strip_components = ($strip)\n")
    }

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
    if not ($lockfile | path exists) {
        return []
    }

    let lockfile_text = (open --raw $lockfile)
    let lockfile_toml = try {
        $lockfile_text | from toml
    } catch {
        return []
    }

    let tools_table = ($lockfile_toml | get tools? | default {})
    mut tools = []

    for tool_spec in ($tools_table | columns) {
        let tool_entries = ($tools_table | get $tool_spec | default [])
        let entries_is_list = (
            ($tool_entries | describe | str starts-with "list")
            or ($tool_entries | describe | str starts-with "table")
        )
        let entries = if $entries_is_list { $tool_entries } else { [$tool_entries] }

        for entry in $entries {
            let platforms = (extract_platforms_from_entry $entry)
            if ($platforms | columns | length) == 0 {
                continue
            }
            let version = ($entry | get version? | default "")
            let strip = if (has_archive_platforms $platforms) { 1 } else { null }
            let tool_binaries = (find_tool_binaries $tool_spec $binary_map)
            let fallback_binaries = (build_binary_info_list (fallback_binary_names_for_tool $tool_spec))
            let binaries = (
                $tool_binaries
                | append $fallback_binaries
                | uniq
            )
            for binary_info in $binaries {
                $tools = ($tools | append {
                    name: $binary_info.clean_name,
                    original_name: $binary_info.original_name,
                    tool_spec: $tool_spec,
                    version: $version,
                    platforms: $platforms,
                    strip_components: $strip
                })
            }
        }
    }

    $tools
}
