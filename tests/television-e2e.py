import shlex

machine.start()
machine.wait_for_unit("multi-user.target")

profile_bin = machine.succeed("cat /etc/nixquick/home-profile-path").strip() + "/bin"
test_bin = "/etc/nixquick/test-bin"


def read_file(path):
    return machine.succeed(f"cat {shlex.quote(path)}")


def assert_contains(path, text):
    machine.succeed(f"grep -F {shlex.quote(text)} {shlex.quote(path)}")


def assert_not_contains(path, text):
    machine.fail(f"grep -F {shlex.quote(text)} {shlex.quote(path)}")


def run_action(command_path, *selected_items):
    command = read_file(command_path)
    selected = " ".join(shlex.quote(item) for item in selected_items)
    rendered = command.replace("{}", selected)
    machine.succeed(
        f"PATH={shlex.quote(test_bin)}:{shlex.quote(profile_bin)}:$PATH bash -lc {shlex.quote(rendered)}"
    )


def run_installed_source():
    command = read_file("/etc/nixquick/installed-source-command")
    return machine.succeed(f"bash -lc {shlex.quote(command)}")


# Initial state
assert_not_contains("/etc/nixos/configuration.nix", "hello")
assert_not_contains("/etc/nixos/home.nix", "jq")
assert_not_contains("/etc/nixos/home.nix", "ripgrep")
machine.fail("test -e /tmp/nixquick-switch.log")

initial_installed = run_installed_source()
if "system/ curl" not in initial_installed:
    raise AssertionError(initial_installed)
if "users.alice/ fd" not in initial_installed:
    raise AssertionError(initial_installed)
if "home/ tree" not in initial_installed:
    raise AssertionError(initial_installed)

# Install one package in Home Manager
machine.succeed("cp /etc/nixos/configuration.nix /tmp/config-before-home-install")
run_action("/etc/nixquick/install-home-command", "nixpkgs/hello")
assert_contains("/etc/nixos/home.nix", "hello")
machine.succeed("cmp -s /etc/nixos/configuration.nix /tmp/config-before-home-install")

installed_after_home = run_installed_source()
if "home/ hello" not in installed_after_home:
    raise AssertionError(installed_after_home)
if "system/ curl" not in installed_after_home:
    raise AssertionError(installed_after_home)
if "users.alice/ fd" not in installed_after_home:
    raise AssertionError(installed_after_home)
if "home/ tree" not in installed_after_home:
    raise AssertionError(installed_after_home)

# Install multiple system packages
machine.succeed("cp /etc/nixos/home.nix /tmp/home-before-system-install")
run_action("/etc/nixquick/install-system-command", "nixpkgs/jq", "nixpkgs/ripgrep")
machine.succeed("cmp -s /etc/nixos/home.nix /tmp/home-before-system-install")
assert_contains("/etc/nixos/configuration.nix", "jq")
assert_contains("/etc/nixos/configuration.nix", "ripgrep")

installed_after_system = run_installed_source()
if "system/ jq" not in installed_after_system or "system/ ripgrep" not in installed_after_system:
    raise AssertionError(installed_after_system)
if "system/ curl" not in installed_after_system:
    raise AssertionError(installed_after_system)
if "users.alice/ fd" not in installed_after_system:
    raise AssertionError(installed_after_system)
if "home/ tree" not in installed_after_system:
    raise AssertionError(installed_after_system)

# Remove one Home Manager package
run_action("/etc/nixquick/remove-command", "home/ hello")
assert_not_contains("/etc/nixos/home.nix", "hello")

installed_after_home_remove = run_installed_source()
if "home/ hello" in installed_after_home_remove:
    raise AssertionError(installed_after_home_remove)
if "system/ curl" not in installed_after_home_remove:
    raise AssertionError(installed_after_home_remove)
if "users.alice/ fd" not in installed_after_home_remove:
    raise AssertionError(installed_after_home_remove)
if "home/ tree" not in installed_after_home_remove:
    raise AssertionError(installed_after_home_remove)

# Remove multiple system packages
run_action("/etc/nixquick/remove-command", "system/ jq", "system/ ripgrep")
assert_not_contains("/etc/nixos/configuration.nix", "jq")
assert_not_contains("/etc/nixos/configuration.nix", "ripgrep")

installed_after_system_remove = run_installed_source()
if "system/ jq" in installed_after_system_remove or "system/ ripgrep" in installed_after_system_remove:
    raise AssertionError(installed_after_system_remove)
if "system/ curl" not in installed_after_system_remove:
    raise AssertionError(installed_after_system_remove)
if "users.alice/ fd" not in installed_after_system_remove:
    raise AssertionError(installed_after_system_remove)
if "home/ tree" not in installed_after_system_remove:
    raise AssertionError(installed_after_system_remove)

# Check switch-command behavior
expected_switches = int("@expectedSwitches@")
if expected_switches == 0:
    machine.fail("test -e /tmp/nixquick-switch.log")
else:
    machine.succeed("test -e /tmp/nixquick-switch.log")
    switch_count = int(machine.succeed("wc -l < /tmp/nixquick-switch.log").strip())
    if switch_count != expected_switches:
        raise AssertionError(
            f"expected {expected_switches} switch runs, got {switch_count}"
        )
