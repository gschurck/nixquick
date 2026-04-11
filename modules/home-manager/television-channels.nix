{ config, lib, pkgs, osConfig ? null, ... }:

let
  inherit (lib)
    escapeShellArg
    mapAttrsToList
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    optionalAttrs
    optionalString
    optionals
    types;

  cfg = config.nixquick;

  # Package nix-editor from a pinned upstream revision because it is not available in nixpkgs.
  nixEditorSrc = builtins.fetchTarball {
    url = "https://github.com/gschurck/nix-editor/archive/dec443e058d7368ae18d60bc8c83f0c7a2f6f66e.tar.gz";
  };

  nixEditorPkg = import nixEditorSrc {
    inherit pkgs;
    lib = pkgs.lib;
  };

  mkInstallActionName = attrPath: runSwitch:
    "add to ${attrPath}"
    + (if runSwitch then " and switch" else " (edit only)");

  mkRemoveActionName = runSwitch:
    if runSwitch then "remove and switch" else "remove (edit only)";

  defaultFlakeRef = "${cfg.flake.path}#${cfg.flake.nixosConfiguration}";

  defaultSwitchCommand =
    if cfg.flake.enable
    then "sudo nixos-rebuild switch --flake ${escapeShellArg defaultFlakeRef}"
    else "sudo nixos-rebuild switch";

  mkSwitchCommand = _attrPath:
    if cfg.switchCommand != null then cfg.switchCommand else defaultSwitchCommand;

  mkInstallCommand = path: attrPath: runSwitch:
    ''
      set -e
      for selected_item in {}; do
        nix-editor -i -a "$(printf '%s' "$selected_item" | sed 's|^[^/]*/[[:space:]]*||')" ${escapeShellArg path} ${escapeShellArg attrPath}
      done
    ''
    + optionalString runSwitch ''
      ${mkSwitchCommand attrPath}
    ''
    + ''
      printf '%s\n' "Installed in ${attrPath} (${path})"
    '';

  mkInstallActionEntries = path: attrPath:
    map
      (runSwitch:
        nameValuePair (mkInstallActionName attrPath runSwitch) {
          description =
            "Install the selected package to ${attrPath}"
            + optionalString runSwitch " and run the switch command";
          command = mkInstallCommand path attrPath runSwitch;
          mode = "execute";
        })
      [
        true
        false
      ];

  # Build Television actions for each configured installation destination.
  installActionEntries =
    builtins.concatLists (
      mapAttrsToList
        (path: attrPaths:
          builtins.concatMap
            (attrPath: mkInstallActionEntries path attrPath)
            attrPaths)
        cfg.destinations
    );

  installActions = builtins.listToAttrs installActionEntries;
  defaultDestinationPaths = builtins.attrNames cfg.destinations;

  destinationForAttrPath = attrPath:
    let
      matchingPaths =
        builtins.filter
          (path: builtins.elem attrPath cfg.destinations.${path})
          defaultDestinationPaths;
    in
    if matchingPaths == [ ] then null else builtins.head matchingPaths;

  # Map displayed package sources back to the config locations they came from.
  removeSourceMappings =
    [
      {
        source = "system";
        attrPath = "environment.systemPackages";
      }
    ]
    ++ optionals (cfg.username != null) [
      {
        source = "users.${cfg.username}";
        attrPath = "users.users.${cfg.username}.packages";
      }
      {
        source = "home";
        attrPath = "home.packages";
      }
    ];

  removeCommandCases =
    builtins.concatStringsSep "\n"
      (builtins.map
        (mapping:
          let
            destinationPath = destinationForAttrPath mapping.attrPath;
          in
          optionalString (destinationPath != null) ''
            ${escapeShellArg mapping.source})
              config_path=${escapeShellArg destinationPath}
              config_key=${escapeShellArg mapping.attrPath}
              ;;
          '')
        removeSourceMappings);

  mkRemoveInstalledPackageCommand = runSwitch: ''
    set -e
    for selected_item in {}; do
      source_name="$(printf '%s' "$selected_item" | sed 's|/.*$||')"
      package_name="$(printf '%s' "$selected_item" | sed 's|^[^/]*/[[:space:]]*||')"

      case "$source_name" in
      ${removeCommandCases}
        *)
          echo "No configured destination for source: $source_name" >&2
          exit 1
          ;;
      esac

      nix-editor -i --remove-from-array "$package_name" "$config_path" "$config_key"
      printf '%s\n' "Removed $package_name from $config_key in $config_path"
    done
    ${optionalString runSwitch ''
      ${mkSwitchCommand null}
    ''}
  '';

  removeInstalledPackageActions = builtins.listToAttrs (
    map
      (runSwitch:
        nameValuePair (mkRemoveActionName runSwitch) {
          description =
            "Remove the selected package from its configured Nix destination"
            + optionalString runSwitch " and run the switch command";
          command = mkRemoveInstalledPackageCommand runSwitch;
          mode = "execute";
        })
      [
        true
        false
      ]
  );

  defaultSwitchActionName =
    if defaultDestinationPaths == [ ]
    then null
    else
      let
        defaultPath = builtins.head defaultDestinationPaths;
        defaultAttrPaths = cfg.destinations.${defaultPath};
      in
      if defaultAttrPaths == [ ]
      then null
      else mkInstallActionName (builtins.head defaultAttrPaths) true;

  defaultOnlyActionName =
    if defaultDestinationPaths == [ ]
    then null
    else
      let
        defaultPath = builtins.head defaultDestinationPaths;
        defaultAttrPaths = cfg.destinations.${defaultPath};
      in
      if defaultAttrPaths == [ ]
      then null
      else mkInstallActionName (builtins.head defaultAttrPaths) false;

  evalUsername = if cfg.username == null then "your-user" else cfg.username;

  installedPackagesConfigExpr =
    if cfg.flake.enable
    then ''
      let
        flake = builtins.getFlake ${builtins.toJSON cfg.flake.path};
      in
        (builtins.getAttr ${builtins.toJSON cfg.flake.nixosConfiguration} flake.nixosConfigurations).config
    ''
    else ''
      (import <nixpkgs/nixos> {}).config
    '';

  installedPackagesSourceCommand = ''
    nix eval ${optionalString cfg.flake.enable "--extra-experimental-features 'nix-command flakes' "}--impure --raw --expr '
        let
          user = ${builtins.toJSON evalUsername};

          getAttrOr = name: attrs:
            if builtins.hasAttr name attrs then builtins.getAttr name attrs else null;

          nixosConfig = ${installedPackagesConfigExpr};

          fmt = source: p:
            let
              name =
                if p ? pname then p.pname
                else if p ? name then p.name
                else "<unknown>";
            in
              source + "/ " + name;

          userConfig =
            let
              users = nixosConfig.users.users or {};
            in
              getAttrOr user users;

          homeManagerConfig = getAttrOr "home-manager" nixosConfig;

          homeConfig =
            if homeManagerConfig == null
            then null
            else
              let
                hmUsers = homeManagerConfig.users or {};
              in
                getAttrOr user hmUsers;

          systemPkgs =
            builtins.map (fmt "system")
              (nixosConfig.environment.systemPackages or []);

          userPkgs =
            builtins.map (fmt ${builtins.toJSON "users.${evalUsername}"})
              (if userConfig == null then [] else userConfig.packages or []);

          hmPkgs =
            builtins.map (fmt "home")
              (if homeConfig == null then [] else homeConfig.home.packages or []);
        in
          builtins.concatStringsSep "\n" (systemPkgs ++ userPkgs ++ hmPkgs)
      ' | sort -u
  '';
in
{
  options.nixquick = {
    enable = mkEnableOption "the nix-search-tv television channel";

    switchCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Command executed when a switch is requested after add or remove actions.
        Defaults to `sudo nixos-rebuild switch`, or to `sudo nixos-rebuild switch --flake <path>#<configuration>`
        when flake support is enabled.
      '';
    };

    username = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "guillaume";
      description = ''
        Optional username used by the nix-installed-packages channel when querying user and Home Manager packages.
      '';
    };

    destinations = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {
        "/etc/nix/configuration.nix" = [ "environment.systemPackages" ];
      };
      example = {
        "~/nixos/configuration.nix" = [
          "environment.systemPackages"
          "users.users.guillaume.packages"
        ];
      };
      description = ''
        Destination config paths and the attribute paths where selected packages can be installed.
      '';
    };

    flake = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "flake-aware evaluation and rebuild commands";

          path = mkOption {
            type = types.str;
            default = "/etc/nixos";
            example = "/home/guillaume/nixos-config";
            description = ''
              Local path to the flake containing the NixOS configuration.
            '';
          };

          nixosConfiguration = mkOption {
            type = types.nullOr types.str;
            default = if osConfig != null then osConfig.networking.hostName else null;
            example = "laptop";
            description = ''
              Name of the target under `nixosConfigurations`.
            '';
          };
        };
      };
      default = { };
      description = ''
        Flake settings used to build the default switch command and installed-package query.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = optionals cfg.flake.enable [
      {
        assertion = cfg.flake.nixosConfiguration != null;
        message = ''
          nixquick.flake.nixosConfiguration must be set when nixquick.flake.enable is true.
        '';
      }
    ];

    home.packages = [
      pkgs.nix-search-tv
      nixEditorPkg
    ];

    programs.television.enable = mkDefault true;

    programs.television.channels.nix-packages = mkDefault ({
      metadata = {
        name = "nix-packages";
        description = "Search Nix packages and install the selected result";
        requirements = [
          "nix-search-tv"
          "nix-editor"
        ];
      };
      source.command = "nix-search-tv print";
      preview.command = "nix-search-tv preview '{}'";
      actions = installActions;
    } // optionalAttrs (defaultSwitchActionName != null && defaultOnlyActionName != null) {
      keybindings = {
        shortcut = "f7";
        enter = "actions:${defaultSwitchActionName}";
        "ctrl-e" = "actions:${defaultOnlyActionName}";
      };
    });

    # Surface packages coming from system, user, and Home Manager declarations in one channel.
    programs.television.channels.nix-installed-packages = mkDefault {
      metadata = {
        name = "nix-installed-packages";
        description = "List installed Nix packages from system, user, and Home Manager configs";
        requirements = [ "nix-editor" ];
      };
      source.command = installedPackagesSourceCommand;
      preview.command = "nix-search-tv preview \"$(printf '%s' '{}' | sed 's|^[^/]*/|nixpkgs/|')\"";
      actions = removeInstalledPackageActions;
      keybindings = {
        shortcut = "f8";
        enter = "actions:${mkRemoveActionName true}";
        "ctrl-e" = "actions:${mkRemoveActionName false}";
      };
    };
  };
}
