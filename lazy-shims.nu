#!/usr/bin/env nu

# Convert mise shims to lazy-loading shell scripts
# This script replaces symlink shims with shell scripts that run `mise x` on demand

# Build a mapping of binary names to their package names by reading mise.toml
def build_tool_mapping [mise_toml_path: string] {
    
    if not ($mise_toml_path | path exists) {
        print $"❌ config.toml not found at ($mise_toml_path)"
        return {}
    }
    
    print $"📖 Reading tool mapping from mise.toml..."
    
    let mise_config = try {
        (open $mise_toml_path)
    } catch {
        print $"❌ Failed to parse mise.toml"
        return {}
    }
    
    let tools = ($mise_config | get tools? | default {})
    mut tool_mapping = {}
    
    # Build mapping of binary names to tool package names
    for tool_spec in ($tools | items { |k, v| {tool: $k, version: $v} }) {
        let tool_name = $tool_spec.tool
        
        # Extract binary name based on backend type
        if ($tool_name | str starts-with "aqua:") {
            let repo_path = ($tool_name | str replace "aqua:" "")
            let binary_name = ($repo_path | split row "/" | last)
            
            # Handle special cases for aqua tools
            let mapped_name = match $binary_name {
                "ripgrep" => "rg",
                "dua-cli" => "dua", 
                "buildx" => "docker-cli-plugin-docker-buildx",
                "compose" => "docker-cli-plugin-docker-compose",
                _ => $binary_name
            }
            
            $tool_mapping = ($tool_mapping | upsert $mapped_name $tool_name)
            
        } else if ($tool_name | str starts-with "github:") {
            let repo_path = ($tool_name | str replace "github:" "")
            let binary_name = ($repo_path | split row "/" | last)
            
            # Handle special cases for github tools
            let mapped_name = match $binary_name {
                "nushell" => "nu",
                "ripgrep" => "rg",
                _ => $binary_name
            }
            
            $tool_mapping = ($tool_mapping | upsert $mapped_name $tool_name)
        }
    }
    
    $tool_mapping
}

def main [mise_config_path?: string] {
    # Default to current directory's config.toml if no path provided
    let config_path = if ($mise_config_path | is-empty) { "config.toml" } else { $mise_config_path }
    let config_dir = ($config_path | path dirname)
    let config_file = ($config_path | path basename)
    
    # Change to config directory to ensure mise commands work correctly
    cd $config_dir
    let shims_dir = $"($env.HOME)/.local/share/mise/shims"
    let local_bin_dir = $"($env.HOME)/.local/bin"
    let installs_dir = $"($env.HOME)/.local/share/mise/installs"
    
    if not ($shims_dir | path exists) {
        print "❌ Shims directory not found at $shims_dir"
        return
    }
    
    # Ensure .local/bin directory exists
    if not ($local_bin_dir | path exists) {
        mkdir $local_bin_dir
    }
    
    print "🔍 Analyzing mise shims and creating lazy loaders in .local/bin..."
    
    # Build dynamic tool mapping by reading mise.toml
    let tool_map = build_tool_mapping $config_file
    
    # Get all shims
    let shims = (ls $shims_dir | where type == "symlink" | get name)
    
    if ($shims | length) == 0 {
        print "⚠️  No shims found in $shims_dir"
        return
    }
    
    mut converted = 0
    
    let mapping_count = ($tool_map | items { |k, v| {key: $k, value: $v} } | length)
    print $"🔧 Found ($mapping_count) tool mappings:"
    for mapping in ($tool_map | items { |k, v| {key: $k, value: $v} }) {
        print $"   ($mapping.key) -> ($mapping.value)"
    }
    
    for shim_path in $shims {
        let shim_name = ($shim_path | path basename)
        let lazy_shim_path = $"($local_bin_dir)/($shim_name)"
        
        try {
            # Look up the package name for this shim
            let package_name = if ($shim_name in $tool_map) { $tool_map | get $shim_name } else { $shim_name }
            
            # Create lazy loading shell script in .local/bin
            let script_content = $"#!/bin/sh
exec mise x ($package_name) -- ($shim_name) \"$@\"
"
            
            # Create the lazy shim in .local/bin (which has higher precedence in PATH)
            $script_content | save -f $lazy_shim_path
            ^chmod +x $lazy_shim_path
            
            print $"✅ ($shim_name) -> lazy load ($package_name) [.local/bin]"
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
