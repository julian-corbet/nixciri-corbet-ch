{
  description = "nixniri — declarative niri compositor config (home-manager), extracted from nixdesktop";

  inputs = {
    # DELIBERATELY THE ONLY OTHER INPUT BESIDES nixpkgs. This flake pulls no compositor, no
    # package set — it generates ~/.config/niri/config.kdl from structured options and installs
    # nothing. There is no policy profile here either: `nixdesktop.want`-style role declaration
    # stays in nixdesktop (see the README's "The split" section for why niri's own config
    # module and the desktop role policy that surrounds it are separate repos now).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixhost IS an input, for exactly one thing: `lib.probeFact`/`lib.collectProbes`
    # (github:julian-corbet/nixhost-corbet-ch, `lib/facts.nix`) -- the shared, plain-function fix
    # for the cross-namespace defensive-read defect class this module's own reads of
    # `nixdesktop.layouts`/`nixdesktop.monitors`/`nixdesktop.sessions` AND
    # `nixgpu.stableDevicePaths.devices` lean on (see nixhost's own `lib/facts.nix` header, and
    # nixscroll's `home/scroll.nix`, which took this same input first). `probeFact`/
    # `collectProbes` are closed over as plain function arguments (below), never `_module.args`,
    # so a consumer importing `homeManagerModules.niri` sees an ordinary module function and
    # never needs to know `nixhost` exists. Note this is a READ, not an `imports`: neither
    # nixdesktop nor nixgpu is a flake input here (see README's "The cross-repo contracts" for
    # the full table) -- `nixhost` supplies only the probing MECHANISM both reads share. This is
    # unrelated to how `nixdesktop.startup`/`nixdesktop.session.idleAndLock` are read: those stay
    # a defensive, zero-flake-dependency probe (`or [ ]` / `or "swaylock"`) -- only the
    # `probeFact` MECHANISM is consumed from nixhost, and only for the newer, assertable seams
    # (`outputs`/`layout`/`session`).
    nixhost = {
      url = "github:julian-corbet/nixhost-corbet-ch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixhost }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

      # `probeFact`/`collectProbes` closed over here, before the module system ever sees the
      # result -- see the `nixhost` input comment above. The exported value is a plain
      # home-manager module function taking the usual `{ lib, config, ... }`; nothing about
      # consuming it changes.
      niriModule = import ./home/niri.nix { inherit (nixhost.lib) probeFact collectProbes; };
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
        niri = niriModule;

        # niri is the only module this project exists for.
        default = niriModule;
      };

      # ── CHECKS ────────────────────────────────────────────────────────────────────────────
      # `nix flake check` does NOT evaluate `homeManagerModules` — it lists them as unchecked and
      # moves on. Since that class is the only thing this repo ships, a green `flake check` here
      # used to prove nothing whatsoever about the module. These checks close that gap by
      # evaluating home/niri.nix for real against a minimal home-manager stub, and (output-accepted)
      # by running its rendered KDL past the real niri binary's own validator.
      checks = forAllSystems (system: {
        startup-contract = import ./checks/startup-contract.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit niriModule;
        };

        # Scoped to the structured-output/layout/session seam this session's work added: a
        # generated block renders syntactically sane KDL, transform passes through untouched,
        # identity matchers with spaces are quoted, the denylist covers every denied device, and
        # every alias variant of an identity-matched monitor gets its own block. See the file's
        # own header for why each of these has a SILENT failure mode that makes it worth a check.
        output-contract = import ./checks/output-contract.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit niriModule;
        };
      }
      # `output-accepted` is NOT part of the uniform `forAllSystems` set above, deliberately —
      # narrowed to x86_64-linux only, the one system this CI actually runs on and can build a
      # real binary for.
      #
      # This check runs the REAL niri binary's own `niri validate` against this module's
      # rendered output (see its own header) — it is the one check in this repo that a
      # `pkgs.emptyFile` fixed-output marker CANNOT paper over, because there is a genuine
      # foreign-arch BUILD to do here (the fixture `config.kdl` written via `pkgs.writeText`,
      # and `niri` itself) and a genuine foreign-arch BINARY to run (`niri validate` inside
      # `pkgs.runCommand`), neither of which this repo has an aarch64 builder or emulation for.
      # Measured: `nix flake check --all-systems` failed exactly here —
      # `checks.aarch64-linux.output-accepted` — with "Cannot build
      # '.../niri-fixture-config.kdl.drv': Reason: platform mismatch, Required system:
      # aarch64-linux, Current system: x86_64-linux" — a `pkgs.emptyFile` swap would have made
      # that failure disappear by silently skipping the one check whose entire point is asking a
      # real binary a real question, on the one arch nothing here can ask it on. Narrowing to
      # x86_64-linux says exactly that out loud instead: this check has no aarch64 coverage,
      # rather than pretending it passed. `startup-contract`/`output-contract` above stay on
      # every declared system unchanged — both decide everything at Nix EVALUATION time (no
      # binary of any arch ever runs), which is exactly the shape `pkgs.emptyFile` fixes for,
      # and is why they keep using it (see each file's own closing comment).
      // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        output-accepted = import ./checks/output-accepted.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          niri = nixpkgs.legacyPackages.${system}.niri;
          inherit niriModule;
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
