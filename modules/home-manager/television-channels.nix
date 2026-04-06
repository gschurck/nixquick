{ config, lib, pkgs, ... }:

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
    optionals
    optionalString
    replaceStrings
    types;

  cfg = config.nixquick;
  nixEditorSrc = builtins.fetchTarball {
    url = "https://github.com/gschurck/nix-editor/archive/dec443e058d7368ae18d60bc8c83f0c7a2f6f66e.tar.gz";
  };
  nixEditorPkg = import nixEditorSrc {
    inherit pkgs;
    lib = pkgs.lib;
  };
  mkInstallActionName = path: attrPath:
    "install to ${attrPath}";
  mkSwitchCommand = _attrPath: "sudo nixos-rebuild switch";
  mkInstallCommand = path: attrPath:
    ''
      set -e
      nix-editor -i -a "$(printf '%s' '{}' | sed 's|^[^/]*/||')" ${escapeShellArg path} ${escapeShellArg attrPath}
    ''
    + optionalString cfg.switchAfterAdd ''
      ${mkSwitchCommand attrPath}
    ''
    + ''
      printf '%s\n' "Installed in ${attrPath} (${path})"
    '';
  installActionEntries =
    builtins.concatLists (
      mapAttrsToList
        (path: attrPaths:
          map
            (attrPath:
              nameValuePair (mkInstallActionName path attrPath) {
                description = "Install the selected package to ${attrPath}";
                command = mkInstallCommand path attrPath;
                mode = "execute";
              })
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
  removeInstalledPackageCommand = ''
    set -e
    source_name="$(printf '%s' '{}' | sed 's|/.*$||')"
    package_name="$(printf '%s' '{}' | sed 's|^[^/]*/[[:space:]]*||')"

    case "$source_name" in
    ${removeCommandCases}
      *)
        echo "No configured destination for source: $source_name" >&2
        exit 1
        ;;
    esac

    nix-editor -i --remove-from-array "$package_name" "$config_path" "$config_key"
    ${optionalString cfg.switchAfterRemove ''
      sudo nixos-rebuild switch
    ''}
    printf '%s\n' "Removed $package_name from $config_key in $config_path"
  '';
  removeInstalledPackageAction = {
    description = "Remove the selected package from its configured Nix destination";
    command = removeInstalledPackageCommand;
    mode = "execute";
  };
  defaultActionName =
      if defaultDestinationPaths == [ ]
      then null
      else
        let
          defaultPath = builtins.head defaultDestinationPaths;
          defaultAttrPaths = cfg.destinations.${defaultPath};
        in
        if defaultAttrPaths == [ ]
        then null
        else mkInstallActionName defaultPath (builtins.head defaultAttrPaths);
in
{
  options.nixquick = {
    enable = mkEnableOption "the nix-search-tv television channel";

    switchAfterAdd = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether add actions should run a configuration switch after editing the target file.
        Destinations run sudo nixos-rebuild switch after the edit.
      '';
    };

    switchAfterRemove = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether remove actions should run a configuration switch after editing the target file.
        Destinations run sudo nixos-rebuild switch after the edit.
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
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.nix-search-tv
      nixEditorPkg
    ];

    programs.television.enable = mkDefault true;
    programs.television.channels.nix-packages = mkDefault ({
      metadata = {
        name = "nix-packages";
        description = "Search Nix packages and install the selected result";
        requirements = [ "nix-search-tv" ];
      };
      source.command = "nix-search-tv print";
      preview.command = "nix-search-tv preview '{}'";
      actions = installActions;
    } // optionalAttrs (defaultActionName != null) {
      keybindings.enter = "actions:${defaultActionName}";
    });

    programs.television.channels.nix-installed-packages = mkDefault {
      metadata = {
        name = "nix-installed-packages";
        description = "List installed Nix packages from system, user, and Home Manager configs";
      };
      source.command = ''
        nix eval --impure --raw --expr '
          let
            nixos = import <nixpkgs/nixos> {};
            user = "${if cfg.username == null then "your-user" else cfg.username}";

            fmt = source: p:
              let
                name =
                  if p ? pname then p.pname
                  else if p ? name then p.name
                  else "<unknown>";
              in
                "''${source}/ ''${name}";

            systemPkgs =
              builtins.map (fmt "system")
                nixos.config.environment.systemPackages;

            userPkgs =
              builtins.map (fmt "users.''${user}")
                (nixos.config.users.users.''${user}.packages or []);

            hmPkgs =
              builtins.map (fmt "home")
                (nixos.config.home-manager.users.''${user}.home.packages or []);
          in
            builtins.concatStringsSep "\n" (systemPkgs ++ userPkgs ++ hmPkgs)
        ' | sort -u
      '';
      preview.command = "nix-search-tv preview \"$(printf '%s' '{}' | sed 's|^[^/]*/|nixpkgs/|')\"";
      actions.remove = removeInstalledPackageAction;
      keybindings.enter = "actions:remove";
    };
  };
}
