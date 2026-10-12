{
  description = "a phone UI for ComfyUI's text-to-picture workflows";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      release = builtins.fromJSON (builtins.readFile ./release.json);
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        petal = pkgs.stdenv.mkDerivation {
          pname = "petal";
          inherit (release) version;

          src = pkgs.fetchurl {
            inherit (release.${pkgs.stdenv.hostPlatform.system}) url hash;
          };
          sourceRoot = ".";

          nativeBuildInputs = [ pkgs.autoPatchelfHook ];
          buildInputs = [ pkgs.stdenv.cc.cc.lib ];

          installPhase = ''
            runHook preInstall
            install -Dm755 petal $out/bin/petal
            runHook postInstall
          '';

          meta = {
            description = "A phone UI for ComfyUI's text-to-picture workflows";
            homepage = "https://github.com/boatette/petal-flake";
            license = pkgs.lib.licenses.mit;
            mainProgram = "petal";
            platforms = systems;
            sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
          };
        };

        default = petal;
      });

      nixosModules = rec {
        petal = import ./nix/nixos.nix self;
        default = petal;
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
