# nixquick

nixquick is a custom home-manager configuration for [television](https://github.com/alexpasmantier/television) channels
to quickly search, install and uninstall nixpkgs across your different nix configuration files out-of-the-box in the 
television TUI.

It supports only NixOS based systems currently, and package configurations without flakes.

It's based on :
- [television](https://github.com/alexpasmantier/television) for customizable fuzzy search TUI
- [nix-search-tv](https://github.com/3timeslazy/nix-search-tv) to search the available nixpkgs in the television TUI
- [nix-editor](https://github.com/snowfallorg/nix-editor) to edit the nix configuration files and add/remove packages

## Demo

![nixquick demo](demo.gif)

[video link](https://asciinema.org/a/DAqmtuhaR2LAIXEJ)

## Installation

Include the following in your home-manager nix configuration like `home.nix`:

```nix
let
  nixquick = builtins.fetchTarball "https://github.com/gschurck/nixquick/archive/refs/tags/v0.1.0.tar.gz";
in
{
  # ...
}
```

Use `main` to receive updates automatically, or use a specific commit if you want to pin unreleased changes:

```nix
  nixquick = builtins.fetchTarball "https://github.com/gschurck/nixquick/archive/main.tar.gz";
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

## Television actions

The generated Television channels now always expose both action variants:

- `... and switch`: update the Nix file, then run `switchCommand`
- `... (edit only)`: update the Nix file without rebuilding

The default keybindings are:

- `Enter`: run the `switch` action
- `Ctrl+E`: run the `edit only` action
- `Tab`: select multiple packages

This applies to both package installation and package removal.
