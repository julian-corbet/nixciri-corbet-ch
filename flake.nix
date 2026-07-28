{
  description = "nixniri — declarative niri compositor config (home-manager), extracted from nixdesktop";

  # DELIBERATELY ONE INPUT. This flake pulls no compositor, no package set — it generates
  # ~/.config/niri/config.kdl from structured options and installs nothing. There is no
  # policy profile here either: `nixdesktop.want`-style role declaration stays in nixdesktop
  # (see the README's "The split" section for why niri's own config module and the desktop
  # role policy that surrounds it are separate repos now).
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      # ── CONFIG GENERATION ─────────────────────────────────────────────────────────────────
      # A home-manager module that writes one real dotfile. It does not install a package
      # either: it assumes the `niri` binary exists, which is a platform backend's job, not
      # this module's.
      #
      # `homeManagerModules`, not `homeModules`: home-manager upstream has moved to the
      # shorter name, but every other project in this family (nixdesktop, nixarch, nixsh,
      # nixremote) exports `homeManagerModules`, and a consumer importing several of them at
      # once should not have to remember which one is spelled differently. Family consistency
      # wins over upstream fashion.
      homeManagerModules = {
        niri = ./home/niri.nix;

        # niri is the only module this project exists for.
        default = ./home/niri.nix;
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
