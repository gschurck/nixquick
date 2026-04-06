# nixquick

nixquick is a custom home-manager configuration for [television](https://github.com/alexpasmantier/television) channels
to quickly search, install and uninstall nixpkgs across your different nix configuration files out-of-the-box in the 
television TUI.

It supports only NixOS based systems currently, and package configurations without flakes.

## Demo

![nixquick demo](demo.gif)

[video link](https://asciinema.org/a/DAqmtuhaR2LAIXEJ)

## Installation

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
    username = "<your_username>";
    switchAfterAdd = true;
    switchAfterRemove = false;
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

Then run `sudo nixos-rebuild switch` to apply the configuration.