#!/usr/bin/env nu

# Generate cross-platform mise lockfiles using mise lock
# Can be used standalone or imported by other tools

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
    let _ = (verify_github_auth $github_token)

    try {
        run_mise_in_directory $mise_toml_dir $github_token {
            if $reset {
                rm -f "mise.lock"
            }
            if not ("mise.lock" | path exists) {
                "" | save -f "mise.lock"
            }
            ^mise lock -y
        }
        print $"✅ Generated lockfile: ($real_lockfile_path)"
    } catch {|e|
        print $"⚠️  Warning: Failed to run mise lock: ($e.msg)"
    }
}

export def main [
    --mise-toml(-m): string = "./mise.toml"  # Path to mise.toml file
    --output(-o): string = ""  # Output lockfile path (default: mise.lock next to toml)
    --update(-u)  # Write the resulting lock file next to the toml file
    --reset(-r)  # Reset lockfile before running mise lock
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

    if $reset {
        generate_expanded_lockfile $mise_toml $lockfile_path $update $default_lockfile_path --reset
    } else {
        generate_expanded_lockfile $mise_toml $lockfile_path $update $default_lockfile_path
    }
}

# Expand lockfile with cross-platform data (kept for compatibility)
export def expand_lockfile_platforms [lockfile_path: string, github_token: string, update_lock: bool, real_lockfile_path: string, reset: bool = false] {
    let mise_toml_dir = ($real_lockfile_path | path dirname)
    try {
        run_mise_in_directory $mise_toml_dir $github_token {
            if $reset {
                rm -f "mise.lock"
            }
            if not ("mise.lock" | path exists) {
                "" | save -f "mise.lock"
            }
            ^mise lock -y
        }
    } catch {|e|
        print $"⚠️  Warning: Failed to run mise lock: ($e.msg)"
    }
}
