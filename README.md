# petal-flake

Nix flake for [petal](https://github.com/boatette/petal), a phone UI for ComfyUI's
text-to-picture workflows: a chat-like feed with live previews, a gallery, Remix, Magic prompts
through a local LLM and push notifications, installable as an app on Android. It starts
ComfyUI's systemd unit when a picture is asked for and stops it again after it has idled.

The petal source is not public. This repository only carries the flake and prebuilt release
binaries for `x86_64-linux` and `aarch64-linux`. `release.json` and `nix/nixos.nix` are written
by the release workflow of the source repository, so changes made here by hand will be
overwritten.

## Usage

```nix
{
  inputs.petal = {
    url = "github:boatette/petal-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then the NixOS module:

```nix
{ inputs, ... }:
{
  imports = [ inputs.petal.nixosModules.petal ];

  services.petal = {
    enable = true;
    user = "alice";
    # https://<host>.<tailnet>.ts.net; needs HTTPS certificates on in the Tailscale admin console.
    tailscale.enable = true;
    settings = {
      catalog = ./petal-catalog.json;
      comfyui = {
        unit = "comfyui.service";
        outputs.image = "/home/alice/Pictures/ComfyUI";
      };
    };
  };
}
```

petal offers the workflows its catalog lists (ComfyUI API graphs plus where the prompt, size,
seed and LoRAs go). The user it runs as needs polkit permission to start and stop the ComfyUI
unit. The module's options are documented in `nix/nixos.nix`, the settings in
`config.example.toml`.

## License

MIT
