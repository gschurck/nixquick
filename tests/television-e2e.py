import shlex

machine.start()
machine.wait_for_unit("multi-user.target")

profile_bin = machine.succeed("cat /etc/nixquick/home-profile-path").strip() + "/bin"
test_bin = "/etc/nixquick/test-bin"
switch_log = "/tmp/nixquick-switch.log"


def read_file(path):
    return machine.succeed(f"cat {shlex.quote(path)}").strip()


def assert_contains(path, text):
    machine.succeed(f"grep -F {shlex.quote(text)} {shlex.quote(path)}")


def assert_not_contains(path, text):
    machine.fail(f"grep -F {shlex.quote(text)} {shlex.quote(path)}")


def reset_switch_log():
    machine.succeed(f"rm -f {shlex.quote(switch_log)}")


def assert_switch_count(expected):
    if expected == 0:
        machine.fail(f"test -e {shlex.quote(switch_log)}")
        return

    machine.succeed(f"test -e {shlex.quote(switch_log)}")
    switch_count = int(machine.succeed(f"wc -l < {shlex.quote(switch_log)}").strip())
    if switch_count != expected:
        raise AssertionError(f"expected {expected} switch runs, got {switch_count}")


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


def assert_installed_output_contains(output, *entries):
    for entry in entries:
        if entry not in output:
            raise AssertionError(output)


def assert_installed_output_excludes(output, *entries):
    for entry in entries:
        if entry in output:
            raise AssertionError(output)


# Initial state
assert_not_contains("/etc/nixos/configuration.nix", "hello")
assert_not_contains("/etc/nixos/configuration.nix", "jq")
assert_not_contains("/etc/nixos/home.nix", "hello")
assert_not_contains("/etc/nixos/home.nix", "ripgrep")
assert_switch_count(0)

if read_file("/etc/nixquick/nix-packages-enter") != "actions:add to environment.systemPackages and switch":
    raise AssertionError(read_file("/etc/nixquick/nix-packages-enter"))
if read_file("/etc/nixquick/nix-packages-ctrl-e") != "actions:add to environment.systemPackages (edit only)":
    raise AssertionError(read_file("/etc/nixquick/nix-packages-ctrl-e"))
if read_file("/etc/nixquick/nix-installed-enter") != "actions:remove and switch":
    raise AssertionError(read_file("/etc/nixquick/nix-installed-enter"))
if read_file("/etc/nixquick/nix-installed-ctrl-e") != "actions:remove (edit only)":
    raise AssertionError(read_file("/etc/nixquick/nix-installed-ctrl-e"))

initial_installed = run_installed_source()
assert_installed_output_contains(initial_installed, "system/ curl", "users.alice/ fd", "home/ tree")

# Install with switch
reset_switch_log()
machine.succeed("cp /etc/nixos/configuration.nix /tmp/config-before-home-switch-install")
run_action("/etc/nixquick/install-home-switch-command", "nixpkgs/hello")
assert_contains("/etc/nixos/home.nix", "hello")
machine.succeed("cmp -s /etc/nixos/configuration.nix /tmp/config-before-home-switch-install")
assert_switch_count(1)

installed_after_home_switch = run_installed_source()
assert_installed_output_contains(
    installed_after_home_switch,
    "home/ hello",
    "system/ curl",
    "users.alice/ fd",
    "home/ tree",
)

# Install without switch
reset_switch_log()
machine.succeed("cp /etc/nixos/home.nix /tmp/home-before-system-only-install")
run_action("/etc/nixquick/install-system-only-command", "nixpkgs/jq", "nixpkgs/ripgrep")
machine.succeed("cmp -s /etc/nixos/home.nix /tmp/home-before-system-only-install")
assert_contains("/etc/nixos/configuration.nix", "jq")
assert_contains("/etc/nixos/configuration.nix", "ripgrep")
assert_switch_count(0)

installed_after_system_only = run_installed_source()
assert_installed_output_contains(
    installed_after_system_only,
    "system/ jq",
    "system/ ripgrep",
    "system/ curl",
    "users.alice/ fd",
    "home/ tree",
    "home/ hello",
)

# Remove with switch
reset_switch_log()
run_action("/etc/nixquick/remove-switch-command", "home/ hello")
assert_not_contains("/etc/nixos/home.nix", "hello")
assert_switch_count(1)

installed_after_home_remove = run_installed_source()
assert_installed_output_excludes(installed_after_home_remove, "home/ hello")
assert_installed_output_contains(
    installed_after_home_remove,
    "system/ curl",
    "system/ jq",
    "system/ ripgrep",
    "users.alice/ fd",
    "home/ tree",
)

# Remove without switch
reset_switch_log()
run_action("/etc/nixquick/remove-only-command", "system/ jq", "system/ ripgrep")
assert_not_contains("/etc/nixos/configuration.nix", "jq")
assert_not_contains("/etc/nixos/configuration.nix", "ripgrep")
assert_switch_count(0)

installed_after_system_remove = run_installed_source()
assert_installed_output_excludes(installed_after_system_remove, "system/ jq", "system/ ripgrep")
assert_installed_output_contains(
    installed_after_system_remove,
    "system/ curl",
    "users.alice/ fd",
    "home/ tree",
)
