# Evaluates home/niri.nix for real, and asserts the `nixdesktop.startup` seam works BOTH ways.
#
# WHY THIS FILE EXISTS AT ALL: `nix flake check` does not evaluate `homeManagerModules`. It reports
# them as "unchecked" and moves on, so a green check here previously covered nothing this repo
# actually ships -- the module could fail to evaluate, or render the wrong thing, and CI would
# still pass. That blind spot is exactly how the startup contract came to have one producer
# (nixdesktop's noctalia module) and zero consumers for as long as it did.
#
# The stub below is a deliberately minimal stand-in for the home-manager options this module
# writes to. It is NOT an attempt to reimplement home-manager: the point is to evaluate THIS
# module's own logic, and a full home-manager instantiation would add a large dependency for no
# extra coverage of the thing under test.
{ pkgs, lib ? pkgs.lib }:
let
  stubs = { lib, ... }: {
    options = {
      xdg.configFile = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = { };
      };
      home.packages = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      home.file = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      systemd.user = lib.mkOption { type = lib.types.anything; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      warnings = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    };
  };

  # The neutral contract, declared the way nixdesktop declares it, and populated the way a
  # nixdesktop component populates it. Deliberately includes an entry with a flag: contract
  # entries are shell command strings, so anything rendered through niri's argv-taking
  # `spawn-at-startup` rather than `spawn-sh-at-startup` would mis-handle this one.
  contract = { lib, ... }: {
    options.nixdesktop.startup = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    config.nixdesktop.startup = [ "noctalia-shell -d" "some-agent --flag" ];
  };

  # nixdesktop's session policy, declaring the locker. The second contract this module reads:
  # swayidle assembly and idle timeouts are nixdesktop's; this module only reads the lock KEY
  # bind's target from this option.
  sessionPolicy = locker: { lib, ... }: {
    options.nixdesktop.session.idleAndLock.lockCommand = lib.mkOption {
      type = lib.types.str;
      default = "swaylock";
    };
    config.nixdesktop.session.idleAndLock.lockCommand = locker;
  };

  render = extra: (lib.evalModules {
    modules = [ stubs ../home/niri.nix { nixniri.niri.enable = true; } ] ++ extra;
    specialArgs = { inherit pkgs; };
  }).config.xdg.configFile."niri/config.kdl".text;

  withContract = render [ contract ];
  withoutContract = render [ ];
  withLocker = render [ (sessionPolicy "waylock") ];

  has = haystack: needle: lib.hasInfix needle haystack;

  results = {
    # POSITIVE — contract entries reach the KDL, in niri's shell-taking spawn form.
    "contract entry renders as spawn-sh-at-startup" =
      has withContract ''spawn-sh-at-startup "noctalia-shell -d"'';
    "a contract entry carrying a flag survives intact" =
      has withContract ''spawn-sh-at-startup "some-agent --flag"'';

    # NEGATIVE — with NO nixdesktop module in scope at all, this module must still evaluate (that
    # `withoutContract` is a string at all proves it) and must render none of the contract.
    "evaluates and renders nothing extra when nixdesktop is absent" =
      !(has withoutContract "noctalia-shell");

    # THE LOCK-COMMAND SEAM, both ways. nixdesktop owns the locker's name (needed for the
    # swayidle invocation it assembles); this module reads it for the Super+Alt+L bind only.
    "the lock bind follows nixdesktop's declared locker" =
      has withLocker ''spawn "waylock"'';
    "the lock bind falls back to swaylock when nixdesktop is absent" =
      has withoutContract ''spawn "swaylock"'';

    # NON-VACUITY — without this, an empty render would make every hasInfix check above pass
    # trivially and the whole file would be a very confident no-op.
    "both renders are real, non-empty configs" =
      lib.stringLength withoutContract > 200 && lib.stringLength withContract > 200;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.runCommand "nixniri-startup-contract-ok" { } "touch $out"
else throw ''
  nixniri: the nixdesktop.startup seam is broken. Failing assertions:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
''
