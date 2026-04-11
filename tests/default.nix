let
  nixpkgsSrc = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  };

  homeManagerSrc = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/master.tar.gz";
  };

  pkgs = import nixpkgsSrc { };
  repoSrc = builtins.path {
    path = ../.;
    name = "nixquick-src";
  };

  makeTest = import (nixpkgsSrc + "/nixos/tests/make-test-python.nix");

  mkTest = { name }:
    makeTest (
      { pkgs, ... }:
      let
        testNixEditor = pkgs.writeShellScriptBin "nix-editor" ''
          exec ${pkgs.python3}/bin/python3 - "$@" <<'PY'
          import re
          import sys
          from pathlib import Path

          def parse_items(body):
              return [item for item in re.split(r"\s+", body.strip()) if item]

          def render_items(items):
              if not items:
                  return ""
              return "\n" + "".join(f"    {item}\n" for item in items)

          def update_array(file_path, attr_path, package_name, remove):
              path = Path(file_path)
              content = path.read_text()
              pattern = re.compile(
                  rf"({re.escape(attr_path)}\s*=\s*with pkgs;\s*\[)(.*?)(\];)",
                  re.S,
              )
              match = pattern.search(content)
              if match is None:
                  raise SystemExit(f"Could not find array assignment for {attr_path} in {file_path}")

              items = parse_items(match.group(2))
              if remove:
                  items = [item for item in items if item != package_name]
              elif package_name not in items:
                  items.append(package_name)

              replacement = f"{match.group(1)}{render_items(items)}{match.group(3)}"
              path.write_text(content[: match.start()] + replacement + content[match.end() :])

          if len(sys.argv) != 6 or sys.argv[1] != "-i":
              raise SystemExit(f"Unsupported invocation: {' '.join(sys.argv[1:])}")

          operation = sys.argv[2]
          package_name = sys.argv[3]
          file_path = sys.argv[4]
          attr_path = sys.argv[5]

          if operation == "-a":
              update_array(file_path, attr_path, package_name, remove=False)
          elif operation == "--remove-from-array":
              update_array(file_path, attr_path, package_name, remove=True)
          else:
              raise SystemExit(f"Unsupported operation: {operation}")
          PY
        '';

        initialConfiguration = pkgs.writeText "nixquick-test-configuration.nix" ''
          { pkgs, ... }:
          {
            imports = [ ${homeManagerSrc}/nixos ];

            users.users.alice = {
              isNormalUser = true;
              home = "/home/alice";
              packages = with pkgs; [ fd ];
            };

            environment.systemPackages = with pkgs; [ curl ];

            home-manager.useGlobalPkgs = true;
            home-manager.users.alice = {
              imports = [ /etc/nixos/home.nix ];
            };

            system.stateVersion = "24.11";
          }
        '';

        initialHome = pkgs.writeText "nixquick-test-home.nix" ''
          { pkgs, ... }:
          {
            home.username = "alice";
            home.homeDirectory = "/home/alice";
            home.stateVersion = "24.11";

            home.packages = with pkgs; [ tree ];
          }
        '';
      in
      {
        name = "nixquick-${name}";

        nodes.machine =
          { config, pkgs, ... }:
          {
            imports = [
              (homeManagerSrc + "/nixos")
            ];

            nix.nixPath = [
              "nixpkgs=${nixpkgsSrc}"
              "nixos-config=/etc/nixos/configuration.nix"
            ];
            nix.settings.experimental-features = [ "nix-command" ];

            users.users.alice = {
              isNormalUser = true;
              home = "/home/alice";
            };

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.alice = {
              imports = [ (import (repoSrc + "/modules/home-manager")).television-channels ];
              home.username = "alice";
              home.homeDirectory = "/home/alice";
              home.stateVersion = "24.11";

              nixquick = {
                enable = true;
                username = "alice";
                switchCommand = "echo switch >> /tmp/nixquick-switch.log";
                destinations = {
                  "/etc/nixos/configuration.nix" = [ "environment.systemPackages" ];
                  "/etc/nixos/home.nix" = [ "home.packages" ];
                };
              };
            };

            environment.etc."nixquick/install-system-switch-command".text =
              config.home-manager.users.alice.programs.television.channels."nix-packages".actions."add to environment.systemPackages and switch".command;

            environment.etc."nixquick/install-system-only-command".text =
              config.home-manager.users.alice.programs.television.channels."nix-packages".actions."add to environment.systemPackages (edit only)".command;

            environment.etc."nixquick/install-home-switch-command".text =
              config.home-manager.users.alice.programs.television.channels."nix-packages".actions."add to home.packages and switch".command;

            environment.etc."nixquick/install-home-only-command".text =
              config.home-manager.users.alice.programs.television.channels."nix-packages".actions."add to home.packages (edit only)".command;

            environment.etc."nixquick/remove-switch-command".text =
              config.home-manager.users.alice.programs.television.channels."nix-installed-packages".actions."remove and switch".command;

            environment.etc."nixquick/remove-only-command".text =
              config.home-manager.users.alice.programs.television.channels."nix-installed-packages".actions."remove (edit only)".command;

            environment.etc."nixquick/installed-source-command".text =
              config.home-manager.users.alice.programs.television.channels."nix-installed-packages".source.command;

            environment.etc."nixquick/nix-packages-enter".text =
              config.home-manager.users.alice.programs.television.channels."nix-packages".keybindings.enter;

            environment.etc."nixquick/nix-packages-ctrl-e".text =
              config.home-manager.users.alice.programs.television.channels."nix-packages".keybindings."ctrl-e";

            environment.etc."nixquick/nix-installed-enter".text =
              config.home-manager.users.alice.programs.television.channels."nix-installed-packages".keybindings.enter;

            environment.etc."nixquick/nix-installed-ctrl-e".text =
              config.home-manager.users.alice.programs.television.channels."nix-installed-packages".keybindings."ctrl-e";

            environment.etc."nixquick/home-profile-path".text =
              toString config.home-manager.users.alice.home.path;

            environment.etc."nixquick/test-bin/nix-editor".source =
              "${testNixEditor}/bin/nix-editor";

            system.activationScripts.nixquickTestFiles.text = ''
              install -Dm644 ${initialConfiguration} /etc/nixos/configuration.nix
              install -Dm644 ${initialHome} /etc/nixos/home.nix
              rm -f /tmp/nixquick-switch.log
            '';

            system.stateVersion = "24.11";
            virtualisation.memorySize = 2048;
          };

        testScript = builtins.readFile ./television-e2e.py;
      }
    );
in
{
  "television-action-modes" = mkTest {
    name = "television-action-modes";
  };
}
