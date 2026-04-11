# nixquick

nixquick is a custom home-manager configuration for [television](https://github.com/alexpasmantier/television) channels
to quickly search, install and uninstall nixpkgs across your different nix configuration files out-of-the-box in the 
television TUI.

It supports NixOS based systems, including both classic setups with `systemPackages`, Home Manager setups and flake-based setups as long as your pkgs are configured in arrays in nix config files.

Features :
- 🔎 Search and install available nix packages
- 🗑️ Search and uninstall packages installed on your machine
- ⚙️ Trigger rebuild switch optionnaly
- ✅ Support selecting, installing and uninstalling multiple packages simultaneously from different places

It's based on :
- [television](https://github.com/alexpasmantier/television) for customizable fuzzy search TUI
- [nix-search-tv](https://github.com/3timeslazy/nix-search-tv) to search the available nixpkgs in the television TUI
- [nix-editor](https://github.com/snowfallorg/nix-editor) to edit the nix configuration files and add/remove packages

## Demo

![nixquick demo](demo.gif)

[video link](https://asciinema.org/a/DAqmtuhaR2LAIXEJ)

## Installation

### Classic setup

Include the following in your home-manager nix configuration like `home.nix`:

```nix
let
  nixquick = builtins.fetchTarball "https://github.com/gschurck/nixquick/archive/main.tar.gz";
in
{
  # ...
}
```

Use `main` to receive updates automatically, or use latest commit for full reproducibility:

```nix
  nixquick = builtins.fetchTarball "https://github.com/gschurck/nixquick/archive/<latest_commit_hash>.tar.gz";
```

And configure it as you want :

```nix
{
  # ...
  nixquick = {
    enable = true;
    switchCommand = "sudo nixos-rebuild switch";
    username = "<your_username>";
    destinations = {
      "/home/<your_username>/nixos-config/configuration.nix" = [
        "environment.systemPackages"
        "users.users.<your_username>.packages"
      ];
      "/home/<your_username>/nixos-config/home.nix" = [ "home.packages" ];
    };
  };
}
```
Available options:

- `nixquick.enable`: enable nixquick channels and helpers
- `nixquick.switchCommand`: optional command run by `... and switch` actions
- `nixquick.username`: optional username used to inspect user and Home Manager packages
- `nixquick.destinations`: map of config file paths to package attribute paths that nixquick can edit
Then run `sudo nixos-rebuild switch` to apply the configuration.

### Flake setup

Add `nixquick` as an input and import the Home Manager module from the flake output:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixquick.url = "github:gschurck/nixquick";
  };

  outputs = inputs@{ nixpkgs, home-manager, nixquick, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        home-manager.nixosModules.home-manager
        ({ ... }: {
          home-manager.useGlobalPkgs = true;
          home-manager.users.<your_username> = {
            imports = [ nixquick.homeManagerModules.default ];

            nixquick = {
              enable = true;
              username = "<your_username>";
              flake = {
                enable = true;
                path = "/home/<your_username>/nixos-config";
                nixosConfiguration = "my-host";
              };
              destinations = {
                "/home/<your_username>/nixos-config/configuration.nix" = [
                  "environment.systemPackages"
                  "users.users.<your_username>.packages"
                ];
                "/home/<your_username>/nixos-config/home.nix" = [ "home.packages" ];
              };
            };
          };
        })
      ];
    };
  };
}
```

In a flake setup, nixquick still edits ordinary `.nix` module files through `destinations`.
The flake settings only change how nixquick evaluates the active configuration and which
default rebuild command it generates.

## Start nixquick tv channels

- `tv nix-packages` to search and install available nix packages
- `tv nix-installed-packages` to search and uninstall locally configured packages

## Television actions

The generated Television channels now always expose both action variants:

- `... and switch`: update the Nix file, then run `switchCommand`
- `... (edit only)`: update the Nix file without rebuilding

The default keybindings are:

- `Enter`: run the `switch` action
- `Ctrl+E`: run the `edit only` action
- `Tab`: select multiple packages
- `F5` from Television to jump to `nix-packages`
- `F6` from Television to jump to `nix-installed-packages`

This applies to both package installation and package removal.
