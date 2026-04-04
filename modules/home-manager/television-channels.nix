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
    optionalString
    replaceStrings
    types;

  cfg = config.nixquick;
  nixEditorSrc = builtins.fetchTarball {
    url = "https://github.com/snowfallorg/nix-editor/archive/a72c7d695d5568fe19ff34d161a22c716ffbdc07.tar.gz";
    sha256 = "04i44zxc5282p0xaqacf2r8dgw5fazbwl50211cl4d4gy4sgj8zl";
  };
  nixEditorPkg = import nixEditorSrc {
    inherit pkgs;
    lib = pkgs.lib;
  };
  mkActionName = path: attrPath:
    "install to ${attrPath}";
  mkInstallCommand = path: attrPath:
    "nix-editor -i -a \"$(printf '%s' '{}' | sed 's|^[^/]*/||')\" ${escapeShellArg path} ${escapeShellArg attrPath}"
    + optionalString cfg.rebuild " && sudo nixos-rebuild switch";
  installActionEntries =
    builtins.concatLists (
      mapAttrsToList
        (path: attrPaths:
          map
            (attrPath:
              nameValuePair (mkActionName path attrPath) {
                description = "Install the selected package to ${attrPath}";
                command = mkInstallCommand path attrPath;
                mode = "execute";
              })
            attrPaths)
        cfg.destinations
    );
  installActions = builtins.listToAttrs installActionEntries;
  defaultDestinationPaths = builtins.attrNames cfg.destinations;
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
      else mkActionName defaultPath (builtins.head defaultAttrPaths);
in
{
  options.nixquick = {
    enable = mkEnableOption "the nix-search-tv television channel";

    rebuild = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether install actions should also run sudo nixos-rebuild switch.
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
    programs.television.channels.nix-packages = mkDefault {
      metadata = {
        name = "nix-search-tv";
        description = "Search Nix packages and install the selected result";
        requirements = [ "nix-search-tv" ];
      };
      source.command = "nix-search-tv print";
      preview.command = "nix-search-tv preview '{}'";
      actions = installActions;
    } // optionalAttrs (defaultActionName != null) {
      keybindings.enter = "actions:${defaultActionName}";
    };
  };
}
