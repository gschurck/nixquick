{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkDefault
    mkOption
    optionalString
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
  systemPackageConfigFileFileArg = optionalString (cfg.systemPackageConfigFile != "") "${cfg.systemPackageConfigFile}";
in
{
  options.nixquick = {
    enable = mkEnableOption "the nix-search-tv television channel";

    systemPackageConfigFile = mkOption {
      type = types.str;
      default = "/etc/nix/configuration.nix";
      example = "~/nixos/configuration.nix";
      description = ''
        Optional path.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.nix-search-tv
      nixEditorPkg
    ];
    programs.television.enable = mkDefault true;
    programs.television.channels.nix-search-tv = mkDefault {
      metadata = {
        name = "nix-search-tv";
        description = "Search Nix packages and install the selected result";
        requirements = [ "nix-search-tv" ];
      };
      source = {
        command = "nix-search-tv print";
      };
      preview = {
        command = "nix-search-tv preview '{}'";
      };
      actions.install = {
        description = "Install the selected package";
        command = "nix-editor -i -a \"$(printf '%s' '{}' | sed 's/^nixpkgs\\///')\" ${systemPackageConfigFileFileArg} environment.systemPackages";
        mode = "execute";
      };
      keybindings = {
        enter = "actions:install";
      };
    };
  };
}
