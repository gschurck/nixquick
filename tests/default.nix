let
  nixpkgsSrc = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  };

  homeManagerSrc = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/master.tar.gz";
  };

  pkgs = import nixpkgsSrc { };
  repoPath = toString ../.;
  repoSrc = builtins.path {
    path = ../.;
    name = "nixquick-src";
  };

  makeTest = import (nixpkgsSrc + "/nixos/tests/make-test-python.nix");

  mkTest = { name, useFlake ? false }:
    makeTest (
      { pkgs, ... }:
      let
        repoFlake = if useFlake then builtins.getFlake repoPath else null;

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

        testSudo = pkgs.writeShellScriptBin "sudo" ''
          exec "$@"
        '';

        testNixosRebuild = pkgs.writeShellScriptBin "nixos-rebuild" ''
          printf '%s\n' "$*" >> /tmp/nixquick-switch.log
        '';

        legacyConfiguration = pkgs.writeText "nixquick-test-configuration.nix" ''
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
            home-manager.useUserPackages = true;
            home-manager.users.alice = {
              imports = [ /etc/nixos/home.nix ];
            };

            system.stateVersion = "24.11";
          }
        '';

        flakeConfiguration = pkgs.writeText "nixquick-test-flake-configuration.nix" ''
          { inputs, pkgs, ... }:
          {
            imports = [ inputs.home-manager.nixosModules.home-manager ];

            users.users.alice = {
              isNormalUser = true;
              home = "/home/alice";
              packages = with pkgs; [ fd ];
            };

            environment.systemPackages = with pkgs; [ curl ];

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.alice = {
              imports = [ /etc/nixos/home.nix ];
              home.username = "alice";
              home.homeDirectory = "/home/alice";
              home.stateVersion = "24.11";
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

        initialFlake = pkgs.writeText "nixquick-test-flake.nix" ''
          {
            description = "nixquick flake test";

            inputs = {
              nixpkgs.url = "path:${nixpkgsSrc}";
              home-manager.url = "path:${homeManagerSrc}";
              home-manager.inputs.nixpkgs.follows = "nixpkgs";
            };

            outputs = inputs@{ nixpkgs, ... }: {
              nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs; };
                modules = [ ./configuration.nix ];
              };
            };
          }
        '';

        expectedSwitchCommandFragment =
          if useFlake
          then "sudo nixos-rebuild switch --flake '/etc/nixos#machine'"
          else "sudo nixos-rebuild switch";

        expectedSwitchLogFragment =
          if useFlake
          then "switch --flake /etc/nixos#machine"
          else "switch";

        expectedInstalledSourceFragment =
          if useFlake
          then "builtins.getFlake \"/etc/nixos\""
          else "import <nixpkgs/nixos>";
      in
      {
        name = "nixquick-${name}";

        nodes.machine =
          { config, lib, pkgs, ... }:
          {
            imports = [
              (homeManagerSrc + "/nixos")
            ];

            nix.nixPath = [
              "nixpkgs=${nixpkgsSrc}"
              "nixos-config=/etc/nixos/configuration.nix"
            ];
            nix.settings.experimental-features =
              [ "nix-command" ]
              ++ lib.optionals useFlake [ "flakes" ];

            users.users.alice = {
              isNormalUser = true;
              home = "/home/alice";
            };

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.alice = {
              imports = [
                (
                  if useFlake
                  then repoFlake.homeManagerModules.default
                  else (import (repoSrc + "/modules/home-manager")).television-channels
                )
              ];
              home.username = "alice";
              home.homeDirectory = "/home/alice";
              home.stateVersion = "24.11";

              nixquick =
                {
                  enable = true;
                  username = "alice";
                  destinations = {
                    "/etc/nixos/configuration.nix" = [ "environment.systemPackages" ];
                    "/etc/nixos/home.nix" = [ "home.packages" ];
                  };
                }
                // lib.optionalAttrs useFlake {
                  flake = {
                    enable = true;
                    path = "/etc/nixos";
                    nixosConfiguration = "machine";
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

            environment.etc."nixquick/nix-packages-shortcut".text =
              config.home-manager.users.alice.programs.television.channels."nix-packages".keybindings.shortcut;

            environment.etc."nixquick/nix-packages-ctrl-e".text =
              config.home-manager.users.alice.programs.television.channels."nix-packages".keybindings."ctrl-e";

            environment.etc."nixquick/nix-installed-enter".text =
              config.home-manager.users.alice.programs.television.channels."nix-installed-packages".keybindings.enter;

            environment.etc."nixquick/nix-installed-shortcut".text =
              config.home-manager.users.alice.programs.television.channels."nix-installed-packages".keybindings.shortcut;

            environment.etc."nixquick/nix-installed-ctrl-e".text =
              config.home-manager.users.alice.programs.television.channels."nix-installed-packages".keybindings."ctrl-e";

            environment.etc."nixquick/home-profile-path".text =
              toString config.home-manager.users.alice.home.path;

            environment.etc."nixquick/test-mode".text =
              if useFlake then "flake" else "legacy";

            environment.etc."nixquick/expected-switch-command-fragment".text =
              expectedSwitchCommandFragment;

            environment.etc."nixquick/expected-switch-log-fragment".text =
              expectedSwitchLogFragment;

            environment.etc."nixquick/expected-installed-source-fragment".text =
              expectedInstalledSourceFragment;

            environment.etc."nixquick/test-bin/nix-editor".source =
              "${testNixEditor}/bin/nix-editor";

            environment.etc."nixquick/test-bin/sudo".source =
              "${testSudo}/bin/sudo";

            environment.etc."nixquick/test-bin/nixos-rebuild".source =
              "${testNixosRebuild}/bin/nixos-rebuild";

            system.activationScripts.nixquickTestFiles.text = ''
              install -Dm644 ${
                if useFlake then flakeConfiguration else legacyConfiguration
              } /etc/nixos/configuration.nix
              install -Dm644 ${initialHome} /etc/nixos/home.nix
              ${lib.optionalString useFlake "install -Dm644 ${initialFlake} /etc/nixos/flake.nix"}
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
  television-action-modes = mkTest {
    name = "television-action-modes";
  };

  flake-television-action-modes = mkTest {
    name = "flake-television-action-modes";
    useFlake = true;
  };
}
