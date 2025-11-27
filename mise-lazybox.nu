#!/usr/bin/env nu

# Generate cross-platform mise lockfile and native tool stubs for all tools
# This is the "lazybox" approach - create stubs for everything in mise.toml

use mise-lockfile.nu [generate_expanded_lockfile, expand_lockfile_platforms]
use mise-platform.nu *
use mise-stub.nu [create_tool_stubs, parse_lockfile_and_map_binaries]

export def main [
    --mise-toml(-m): string = "./mise.toml"  # Path to mise.toml file
    --output-dir(-o): string = ""  # Output directory for stubs
    --update-lock  # Write the resulting lock file next to the toml file
    --force(-f)  # Overwrite existing stubs
    --alpine(-a)  # Generate Alpine-specific .musl.toml variants
] {
    # Verify mise.toml exists
    if not ($mise_toml | path exists) {
        print $"❌ Error: mise.toml not found at ($mise_toml)"
        exit 1
    }

    let mise_toml_dir = ($mise_toml | path dirname)
    let mise_toml_stem = ($mise_toml | path parse | get stem)
    let real_lockfile_path = ($mise_toml_dir | path join $"($mise_toml_stem).lock")

    # Determine which lockfile to use for processing
    let lockfile_path = if $update_lock {
        # Always use the real lockfile path when --update-lock is set
        $real_lockfile_path
    } else if ($real_lockfile_path | path exists) {
        # Use existing lockfile if present
        $real_lockfile_path
    } else {
        # Use a temporary lockfile
        (mktemp)
    }

    let default_output_dir = ($env.HOME | path join ".local/share/mise/stubs")
    let stubs_dir = if ($output_dir | is-empty) { $default_output_dir } else { $output_dir }

    print "🔧 Generating cross-platform mise lockfile and tool stubs..."

    try {
        # Step 1: Create empty lockfile (or use existing)
        if not ($lockfile_path | path exists) {
            "" | save -f $lockfile_path
        }

        # Step 2: Generate lockfile from mise.toml and expand with cross-platform data
        generate_expanded_lockfile $mise_toml $lockfile_path $update_lock $real_lockfile_path

        # Step 3: Parse lockfile and map binaries
        let tools_data = (parse_lockfile_and_map_binaries $lockfile_path)

        if ($tools_data | is-empty) {
            print "⚠️  No tools with platform data found in lockfile."
            return
        }

        # Step 4: Generate tool stubs
        ^mkdir -p $stubs_dir
        let created_stubs = (create_tool_stubs $tools_data $stubs_dir $force $alpine)

        print $"\n📦 Created ($created_stubs | length) tool stubs in ($stubs_dir)"
        if ($created_stubs | length) > 0 {
            let stub_names = ($created_stubs | get name | str join ", ")
            print $"   Tools: ($stub_names)"
            print $"\n💡 Add to PATH: export PATH=\"($stubs_dir):$PATH\""
        }

    } catch {|e|
        print $"❌ Error: ($e.msg)"
    }
}
