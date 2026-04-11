{
  description = "Television channels for managing Nix packages from Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, ... }:
    let
      televisionChannelsModule = import ./modules/home-manager/television-channels.nix;
    in
    {
      homeManagerModules = {
        default = televisionChannelsModule;
        television-channels = televisionChannelsModule;
      };
    };
}
