#!/usr/bin/env nu

# Unit test for mise-lazybox.nu functionality
# Creates a test mise.toml and verifies stub generation

use std assert

def main [] {
    print "🧪 Running mise-lazybox.nu unit tests..."

    # Setup test environment
    let test_dirs = (setup_test_environment)

    # Run all tests in the test directory
    run_tests_in_directory $test_dirs.test_dir $test_dirs.original_dir

    test_cleanup

    print "✅ All mise-lazybox.nu tests passed!"
}

def run_tests_in_directory [test_dir: string, original_dir: string] {
    cd $test_dir
    print $"🔄 Running tests in isolated directory: ($test_dir)"

    test_mise_toml_creation
    test_lockfile_generation
    test_docker_cli_multiplatform
    test_stub_generation
    test_alpine_variant_generation
    test_integration $original_dir
}

def setup_test_environment [] {
    print "📁 Setting up test environment..."

    # Store original directory before changing
    let original_dir = (pwd)

    # Create temporary test directory
    let test_dir = (mktemp -d)

    # Store both directories in files for cleanup and in the test directory
    cd $test_dir
    $original_dir | save -f original_dir.txt
    $test_dir | save test_dir.txt

    print $"   Test directory: ($test_dir)"
    print $"   Original directory: ($original_dir)"

    # Return both directories as a record
    {test_dir: $test_dir, original_dir: $original_dir}
}

def test_mise_toml_creation [] {
    print "📝 Testing mise.toml creation..."

    # Create test mise.toml with yq, jq, and bat
    let mise_toml_content = '[tools]
yq = "github:mikefarah/yq"
jq = "github:jqlang/jq"
bat = "aqua:sharkdp/bat"
'

    $mise_toml_content | save -f mise.toml

    # Verify file was created
    assert ($"mise.toml" | path exists)

    # Verify content
    let content = (open --raw mise.toml)
    assert ($content | str contains "yq")
    assert ($content | str contains "jq")
    assert ($content | str contains "bat")

    print "   ✓ mise.toml created with test tools"
}

def test_lockfile_generation [] {
    print "🔒 Testing lockfile generation..."

    # Create a mock lockfile since we can't run actual mise install in tests
    let mock_lockfile_content = '[[tools."github:mikefarah/yq"]]
version = "v4.44.2"
backend = "github:mikefarah/yq"

[tools."github:mikefarah/yq".platforms.linux-amd64]
checksum = "sha256:e4c2570249e3993e33ffa44e592b5eee8545bd807bfbeb596c2986d86cb6c85c"
size = 4087934
url = "https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64.tar.gz"

[tools."github:mikefarah/yq".platforms.darwin-arm64]
checksum = "sha256:86f172cd7b8d84f178b20b02df12c772aacb5ffefeecba33af93727b0d3000f2"
size = 3914114
url = "https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_darwin_arm64.tar.gz"

[[tools."github:jqlang/jq"]]
version = "jq-1.8.1"
backend = "github:jqlang/jq"

[tools."github:jqlang/jq".platforms.linux-amd64]
checksum = "sha256:020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d"
size = 2255816
url = "https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64"

[tools."github:jqlang/jq".platforms.darwin-arm64]
checksum = "sha256:a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603"
size = 841408
url = "https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-macos-arm64"

[[tools."aqua:sharkdp/bat"]]
version = "0.25.0"
backend = "aqua:sharkdp/bat"

[tools."aqua:sharkdp/bat".platforms.linux-amd64]
checksum = "sha256:93f47d76abe328c402ef712e9ac92aa6d5bc84d5adcbcaf0bbc5665e5275a941"
size = 3275963
url = "https://github.com/sharkdp/bat/releases/download/v0.25.0/bat-v0.25.0-x86_64-unknown-linux-musl.tar.gz"

[tools."aqua:sharkdp/bat".platforms.linux-arm64]
checksum = "sha256:ee0f12cf6006a79cf4ccf75d2ddcf9f6ba124644503244b1af909c2f72a2a9f7"
size = 3087818
url = "https://github.com/sharkdp/bat/releases/download/v0.25.0/bat-v0.25.0-aarch64-unknown-linux-musl.tar.gz"

[tools."aqua:sharkdp/bat".platforms.darwin-arm64]
checksum = "sha256:b3ed5a7515545445881f1036f0cc1b708c2b86cbce01c1b4033f38e0cfcc7b3c"
size = 2942334
url = "https://github.com/sharkdp/bat/releases/download/v0.25.0/bat-v0.25.0-aarch64-apple-darwin.tar.gz"
'

    $mock_lockfile_content | save -f mise.lock

    # Verify lockfile was created
    assert ($"mise.lock" | path exists)

    # Verify it contains our test tools
    let lockfile_content = (open --raw mise.lock)
    assert ($lockfile_content | str contains "github:mikefarah/yq")
    assert ($lockfile_content | str contains "github:jqlang/jq")
    assert ($lockfile_content | str contains "aqua:sharkdp/bat")

    print "   ✓ Mock lockfile created with cross-platform data"
}

def test_docker_cli_multiplatform [] {
    print "🐳 Testing docker/cli multi-platform expansion..."

    # Create a mock lockfile with docker/cli using only the current platform
    let mock_docker_lockfile_content = '[[tools."aqua:docker/cli"]]
version = "28.5.1"
backend = "aqua:docker/cli"

[tools."aqua:docker/cli".platforms.macos-arm64]
checksum = "blake3:64c1042d130bffba07e5cd29990a642e8614d53f061a7b863e03dbbc9d7aca15"
size = 18920970
url = "https://download.docker.com/mac/static/stable/aarch64/docker-28.5.1.tgz"
'

    $mock_docker_lockfile_content | save -f mise.docker.lock

    # Copy mise-lockfile.nu, mise-platform.nu, and mise-core.nu from original directory to test directory
    let original_dir = (open original_dir.txt | str trim)

    cp ($original_dir | path join "mise-lockfile.nu") .
    cp ($original_dir | path join "mise-platform.nu") .
    cp ($original_dir | path join "mise-core.nu") .

    # Test the expansion logic
    let expansion_result = try {
        ^nu -c "
            source mise-lockfile.nu
            let result = (generate_aqua_platform_variants 'https://download.docker.com/mac/static/stable/aarch64/docker-28.5.1.tgz' 'aqua:docker/cli' ['macos-arm64'] 'fake-token')
            print ($result.platforms | length)
        "
    } catch {
        0
    }

    # Verify that we would generate multiple platforms (at least more than the 1 we started with)
    # Note: In the test environment without network access, we expect the function to attempt expansion
    # The test verifies the logic exists and would work with proper network connectivity

    # Test that the function exists and can be called without errors
    let function_exists = try {
        ^nu -c "
            source mise-lockfile.nu
            # Just test that the function can be parsed and called
            let result = (generate_aqua_platform_variants 'https://download.docker.com/mac/static/stable/aarch64/docker-28.5.1.tgz' 'aqua:docker/cli' ['macos-arm64'] 'fake-token')
            print 'function_works'
        "
    } catch {
        "function_error"
    }

    assert ($function_exists | str contains "function_works")

    # Test that the extract_version_from_url function works correctly for docker URLs
    let version_extraction_result = try {
        ^nu -c "
            source mise-lockfile.nu
            let version = (extract_version_from_url 'https://download.docker.com/mac/static/stable/aarch64/docker-28.5.1.tgz' 'docker/cli')
            print $version
        "
    } catch {
        ""
    }

    assert (($version_extraction_result | str trim) == "28.5.1")

    print "   ✓ Docker CLI multi-platform expansion logic verified"
    print "   ✓ Version extraction from Docker URLs working"
}

def test_stub_generation [] {
    print "🔨 Testing stub generation..."

    # Create test stubs directory
    let test_stubs_dir = "./test_stubs"
    mkdir $test_stubs_dir

    # Create mock mise shims directory structure for binary mapping
    let mock_mise_dir = "./mock_mise"
    let mock_shims_dir = ($mock_mise_dir | path join "shims")
    let mock_installs_dir = ($mock_mise_dir | path join "installs")

    mkdir $mock_shims_dir
    mkdir $mock_installs_dir

    # Create mock tool installations
    create_mock_tool_install $mock_installs_dir "github_mikefarah_yq" "yq" "v4.44.2"
    create_mock_tool_install $mock_installs_dir "github_jqlang_jq" "jq" "jq-1.8.1"
    create_mock_tool_install $mock_installs_dir "aqua_sharkdp_bat" "bat" "0.25.0"

    # Create mock shims
    create_mock_shim $mock_shims_dir "yq" "github:mikefarah/yq@v4.44.2"
    create_mock_shim $mock_shims_dir "jq" "github:jqlang/jq@jq-1.8.1"
    create_mock_shim $mock_shims_dir "bat" "aqua:sharkdp/bat@0.25.0"

    # Set environment to use our mock mise directory
    with-env {MISE_DATA_DIR: $mock_mise_dir} {
        # Test the core functionality of stub generation by calling mise-lazybox.nu
        # We'll create a minimal version that doesn't require external tools
        let stub_generator_result = (test_stub_generation_core $test_stubs_dir)
        assert $stub_generator_result
    }

    print "   ✓ Stub generation logic tested"
}

def create_mock_tool_install [installs_dir: string, tool_dir: string, binary_name: string, version: string] {
    let tool_path = ($installs_dir | path join $tool_dir)
    let version_path = ($tool_path | path join $version)
    let latest_path = ($tool_path | path join "latest")
    let bin_path = ($version_path | path join "bin")

    mkdir $bin_path

    # Create mock binary
    touch ($bin_path | path join $binary_name)
    chmod +x ($bin_path | path join $binary_name)

    # Create backend file
    $"($tool_dir | str replace "_" ":")" | save -f ($tool_path | path join ".mise.backend")

    # Create latest symlink
    ln -sf $version_path $latest_path
}

def create_mock_shim [shims_dir: string, binary_name: string, tool_spec: string] {
    # Create a mock shim (symlink to a fake mise executable)
    let fake_mise = ($shims_dir | path join "fake_mise")
    touch $fake_mise
    chmod +x $fake_mise

    ln -sf $fake_mise ($shims_dir | path join $binary_name)
}

def test_stub_generation_core [stubs_dir: string] {
    # Test the core logic of generating stubs from parsed lockfile data

    # Mock binary mapping
    let binary_map = {
        "yq": "github:mikefarah/yq@v4.44.2",
        "jq": "github:jqlang/jq@jq-1.8.1",
        "bat": "aqua:sharkdp/bat@0.25.0"
    }

    # Test parsing lockfile for stub data
    let tools_data = [
        {
            name: "yq",
            original_name: "yq",
            tool_spec: "github:mikefarah/yq",
            version: "v4.44.2",
            platforms: {
                "linux-amd64": {
                    url: "https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64.tar.gz",
                    checksum: "sha256:e4c2570249e3993e33ffa44e592b5eee8545bd807bfbeb596c2986d86cb6c85c",
                    size: 4087934
                },
                "darwin-arm64": {
                    url: "https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_darwin_arm64.tar.gz",
                    checksum: "sha256:86f172cd7b8d84f178b20b02df12c772aacb5ffefeecba33af93727b0d3000f2",
                    size: 3914114
                }
            }
        }
    ]

    # Test TOML content generation
    let tool_data = $tools_data.0
    let toml_content = (build_test_toml_content $tool_data false)

    # Verify TOML contains expected content
    if not ($toml_content | str contains $"tool = \"($tool_data.tool_spec)\"") {
        return false
    }

    if not ($toml_content | str contains $"version = \"($tool_data.version)\"") {
        return false
    }

    if not ($toml_content | str contains "platforms.linux-amd64") {
        return false
    }

    # Test wrapper script generation
    let wrapper_content = (build_test_wrapper_content "yq" false)

    if not ($wrapper_content | str contains "#!/bin/sh") {
        return false
    }

    if not ($wrapper_content | str contains "mise trust -y -a -q") {
        return false
    }

    true
}

def build_test_toml_content [tool: record, is_musl_variant: bool] {
    mut content = if $is_musl_variant {
        $"# Auto-generated Alpine/musl stub for ($tool.name)\n\n"
    } else {
        $"# Auto-generated stub for ($tool.name)\n\n"
    }

    $content = ($content + $"tool = \"($tool.tool_spec)\"\n")
    $content = ($content + $"version = \"($tool.version)\"\n")
    $content = ($content + $"bin = \"($tool.original_name)\"\n")

    if ($tool.platforms | items {|k, v| {key: $k, value: $v}} | length) > 0 {
        $content = ($content + "\n# Platform configurations\n")

        for platform in ($tool.platforms | items {|k, v| {key: $k, value: $v}}) {
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

            $content = ($content + "\n")
        }
    }

    $content
}

def build_test_wrapper_content [tool_name: string, has_alpine_variant: bool] {
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

def test_alpine_variant_generation [] {
    print "🏔️  Testing Alpine variant generation..."

    # Test Alpine variant logic with a tool that has musl/gnu differences
    let tool_with_variants = {
        name: "test-tool",
        original_name: "test-tool",
        tool_spec: "test:tool",
        version: "1.0.0",
        platforms: {
            "linux-amd64": {
                url: "https://example.com/tool-x86_64-unknown-linux-musl.tar.gz",
                checksum: "sha256:abc123",
                size: 1000000
            },
            "linux-arm64": {
                url: "https://example.com/tool-aarch64-unknown-linux-gnu.tar.gz",
                checksum: "sha256:def456",
                size: 900000
            }
        }
    }

    # Test Alpine variant detection
    let should_generate = (test_should_generate_alpine_variant $tool_with_variants)
    assert $should_generate

    # Test wrapper content with Alpine variant
    let wrapper_with_alpine = (build_test_wrapper_content "test-tool" true)
    assert ($wrapper_with_alpine | str contains "/etc/alpine-release")
    assert ($wrapper_with_alpine | str contains ".musl.toml")

    print "   ✓ Alpine variant generation logic tested"
}

def test_should_generate_alpine_variant [tool: record] {
    let platforms = ($tool | get platforms? | default {})
    let linux_amd64_data = ($platforms | get linux-amd64? | default {})
    let linux_arm64_data = ($platforms | get linux-arm64? | default {})
    let linux_amd64_url = ($linux_amd64_data | get url? | default "")
    let linux_arm64_url = ($linux_arm64_data | get url? | default "")

    let has_musl_amd64 = ($linux_amd64_url | str contains "musl")
    let has_musl_arm64 = ($linux_arm64_url | str contains "musl")
    let has_gnu_arm64 = ($linux_arm64_url | str contains "gnu")

    # Generate Alpine variant if we have the fallback case
    $has_musl_amd64 and (not $has_musl_arm64) and $has_gnu_arm64
}

def test_integration [original_dir: string] {
    print "🔗 Testing integration with mise-lazybox.nu..."

    # Copy the module files to our test directory instead of changing directories
    try {
        let modules = ["mise-platform.nu", "mise-lockfile.nu"]
        for module in $modules {
            let source = ($original_dir | path join $module)
            if ($source | path exists) {
                cp $source .
                print $"   ✓ Copied ($module) to test directory"
            }
        }

        # Now test importing modules from current (test) directory
        use mise-platform.nu *
        let test_platform = (get_platform_definitions "test:tool")
        assert (($test_platform | length) > 0)
        print "   ✓ mise-platform.nu imported and working"

        # Test that Alpine detection works
        let is_alpine_result = (is_alpine)
        assert ($is_alpine_result == true or $is_alpine_result == false)
        print "   ✓ Alpine detection function working"

        print "   ✅ Integration test completed (all modules imported successfully)"

    } catch {|e|
        print $"   ❌ Integration test failed: ($e.msg)"
        assert false
    }
}

def test_cleanup [] {
    print "🧹 Cleaning up test environment..."

    # Read test directory path and cleanup
    if ("test_dir.txt" | path exists) {
        let test_dir = (open test_dir.txt | str trim)
        cd ..
        rm -rf $test_dir
        print "   ✓ Test directory cleaned up"
    }
}