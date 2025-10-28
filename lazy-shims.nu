#!/usr/bin/env nu

# Convert mise shims to lazy-loading shell scripts
# This script replaces symlink shims with shell scripts that run `mise x` on demand

# Read versions from mise.toml to get package names with their pinned versions
def read_mise_config [mise_toml_path: string] {
    
    if not ($mise_toml_path | path exists) {
        print $"❌ mise.toml not found at ($mise_toml_path)"
        exit 1
    }
    
    print "📖 Reading package versions from mise.toml..."
    
    # Parse the TOML file to extract tool versions
    try {
        let config_content = (open $mise_toml_path)
        $config_content.tools
    } catch { |e|
        print $"❌ Error reading mise.toml: ($e.msg)"
        exit 1
    }
}

# Build a mapping of binary names to their package names with versions by scanning installation directories
def build_tool_mapping [mise_toml_path: string] {
    let installs_dir = $"($env.HOME)/.local/share/mise/installs"
    
    if not ($installs_dir | path exists) {
        print $"❌ Installs directory not found at ($installs_dir)"
        exit 1
    }
    
    # Read the configured tools and versions from mise.toml
    let mise_tools = (read_mise_config $mise_toml_path)
    if ($mise_tools | is-empty) {
        print "❌ No tools found in mise.toml"
        exit 1
    }
    
    print $"📖 Scanning installation directories and validating against mise.toml..."
    
    mut tool_mapping = {}
    mut sync_errors = []
    
    # Iterate through each configured tool in mise.toml
    for tool_entry in ($mise_tools | items { |k, v| {package: $k, version: $v} }) {
        let package_name = $tool_entry.package
        let expected_version = $tool_entry.version
        
        # Convert package name to directory format (kebab-case)
        let package_dir_name = if ($package_name | str starts-with "aqua:") {
            let repo_part = ($package_name | str replace "aqua:" "" | str replace "/" "-")
            # Convert camelCase to kebab-case, then lowercase
            let kebab_case = ($repo_part | str replace -ra '([a-z])([A-Z])' '${1}-${2}' | str downcase)
            $"aqua-($kebab_case)"
        } else if ($package_name | str starts-with "github:") {
            let repo_part = ($package_name | str replace "github:" "" | str replace "/" "-")
            # Convert camelCase to kebab-case, then lowercase  
            let kebab_case = ($repo_part | str replace -ra '([a-z])([A-Z])' '${1}-${2}' | str downcase)
            $"github-($kebab_case)"
        } else {
            $package_name
        }
        
        let package_dir_path = $"($installs_dir)/($package_dir_name)"
        
        # Check if the package is installed
        if not ($package_dir_path | path exists) {
            $sync_errors = ($sync_errors | append $"Package ($package_name) not installed - missing ($package_dir_path)")
            continue
        }
        
        # Check if the expected version is installed
        let version_dir_path = $"($package_dir_path)/($expected_version)"
        if not ($version_dir_path | path exists) {
            $sync_errors = ($sync_errors | append $"Version ($expected_version) for ($package_name) not installed - missing ($version_dir_path)")
            continue
        }
        
        # Find all executable files in this version directory (recursively)
        let files_result = try {
            glob $"($version_dir_path)/**/*" | each { |path|
                if ($path | path type) == "file" {
                    $path
                } else {
                    null
                }
            } | where $it != null
        } catch {
            []
        }
        
        if ($files_result | is-empty) and ($version_dir_path | path exists) {
            $sync_errors = ($sync_errors | append $"Cannot read version directory: ($version_dir_path)")
            continue
        }
        
        for file_path in $files_result {
            let binary_name = ($file_path | path basename)
            
            # Check if it's likely an executable (has execute permission)
            let is_executable = try {
                ^test -x $file_path; $env.LAST_EXIT_CODE == 0
            } catch {
                false
            }
            
            if $is_executable {
                $tool_mapping = ($tool_mapping | upsert $binary_name $"($package_name)@($expected_version)")
            }
        }
    }
    
    # Check for sync errors and bail out if found
    if ($sync_errors | length) > 0 {
        print "❌ mise.toml and installs directory are out of sync:"
        for error in $sync_errors {
            print $"   • ($error)"
        }
        print "\\n💡 Run 'mise install' to sync installations with mise.toml"
        exit 1
    }
    
    $tool_mapping
}

def main [mise_toml_path?: string] {
    # Default to mise.toml in current directory if no path provided
    let toml_path = if ($mise_toml_path | is-empty) { "mise.toml" } else { $mise_toml_path }
    
    # Check if the mise.toml file exists
    if not ($toml_path | path exists) {
        print $"❌ Error: mise.toml file not found at '($toml_path)'"
        print "Usage: ./lazy-shims.nu [path/to/mise.toml]"
        exit 1
    }
    let shims_dir = $"($env.HOME)/.local/share/mise/shims"
    let local_bin_dir = $"($env.HOME)/.local/bin"
    let installs_dir = $"($env.HOME)/.local/share/mise/installs"
    
    if not ($shims_dir | path exists) {
        print "❌ Shims directory not found at $shims_dir"
        exit 1
    }
    
    # Ensure .local/bin directory exists
    if not ($local_bin_dir | path exists) {
        mkdir $local_bin_dir
    }
    
    print "🔍 Analyzing mise shims and creating lazy loaders in .local/bin..."
    
    # Build dynamic tool mapping by scanning installs directory
    let tool_map = (build_tool_mapping $toml_path)
    
    # If tool mapping is empty due to sync errors, bail out completely
    if ($tool_map | is-empty) {
        print "❌ Cannot create lazy shims due to sync errors. Please fix the issues above first."
        exit 1
    }
    
    # Get all shims
    let shims = (ls $shims_dir | where type == "symlink" | get name)
    
    if ($shims | length) == 0 {
        print "⚠️  No shims found in $shims_dir"
        exit 0
    }
    
    mut converted = 0
    
    let mapping_count = ($tool_map | items { |k, v| {key: $k, value: $v} } | length)
    print $"🔧 Found ($mapping_count) tool mappings with versions:"
    for mapping in ($tool_map | items { |k, v| {key: $k, value: $v} }) {
        print $"   ($mapping.key) -> ($mapping.value)"
    }
    
    for shim_path in $shims {
        let shim_name = ($shim_path | path basename)
        let lazy_shim_path = $"($local_bin_dir)/($shim_name)"
        
        try {
            # Look up the package name with version for this shim
            let package_spec = if ($shim_name in $tool_map) { $tool_map | get $shim_name } else { $shim_name }
            
            # Create lazy loading shell script in .local/bin
            let script_content = $"#!/bin/sh
lazy-mise x ($package_spec) -- ($shim_name) \"$@\"
"
            
            # Create the lazy shim in .local/bin (which has higher precedence in PATH)
            $script_content | save -f $lazy_shim_path
            ^chmod +x $lazy_shim_path
            
            print $"✅ ($shim_name) -> lazy load ($package_spec) [.local/bin]"
            $converted = ($converted + 1)
            
        } catch { |e|
            print $"❌ Error processing ($shim_name): ($e.msg)"
        }
    }
    
    # Summary
    print $"\\n📊 Lazy shim conversion complete!"
    print $"   Converted: ($converted) shims to .local/bin"
    print $"   Tools will be installed on first use via 'mise x'"
    print $"   Lazy shims in .local/bin will override mise shims"
    
    if $converted > 0 {
        print "\\n💡 Benefits:"
        print "   • Reduced container size (no pre-installed tools)"
        print "   • Faster container startup" 
        print "   • Tools install automatically when needed"
        print "   • Lazy shims persist even when mise recreates shim directory"
    }
}
