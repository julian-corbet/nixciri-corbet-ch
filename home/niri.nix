# home/niri.nix — declarative niri desktop config (home-manager). Complements
# profiles/desktop.nix (the POLICY layer — which roles the session wants filled); this
# module owns the user's ~/.config/niri/config.kdl, generated from structured options instead
# of hand-edited KDL.
#
# Nothing here installs anything. nixniri never names a package or an absolute binary path:
# both are platform-specific (`thunar` on Arch vs `xfce.thunar` in nixpkgs; mate-polkit's agent
# binary lives at a different path on every distro). A platform backend — nixarch's for
# Arch/CachyOS — resolves the roles declared in profiles/desktop.nix into real packages,
# and supplies the binary paths this module spawns via `binPaths`.
#
# LEAN BY DESIGN, same doctrine as home/shell.nix and home/dev.nix: the skeleton (input/layout/
# workspaces/binds) is niri's own well-known suggested defaults (straight from its upstream
# example config — Mod+arrows, Mod+1-9, the standard media/volume/brightness keys), not this
# author's personal taste. Every value is a real option with a neutral default; nothing here
# assumes a specific keyboard layout, terminal brand, or app list. A consumer wanting kitty
# instead of foot, a different keyboard layout, messenger auto-launch, or extra keybinds does so
# via the options below, not by forking this file.
#
# `probeFact`/`collectProbes` ARE TAKEN AS A MODULE ARGUMENT, closed over by flake.nix against
# the real `nixhost.lib` (see flake.nix's own `nixhost` input comment) — the same shape
# nixscroll's `home/scroll.nix` and nixdesktop's own `modules/session.nix` already use. This is
# the probeFact MECHANISM only: neither nixdesktop nor nixgpu is ever a flake input here, and
# everything read through it below (`nixdesktop.layouts`, `nixdesktop.monitors`,
# `nixdesktop.sessions`, `nixgpu.stableDevicePaths.devices`) renders nothing at all on a host
# that never composed the sibling that owns it, silently and correctly.
{ probeFact, collectProbes }:
{ lib, config, ... }:
let
  cfg = config.nixniri.niri;

  # The neutral `nixdesktop.startup` contract, consumed rather than hand-wired.
  #
  # Read DEFENSIVELY (`or [ ]`): a host running niri WITHOUT any nixdesktop module sees an
  # empty list and renders nothing extra, never an evaluation error. That is what keeps this a
  # one-way dependency -- nixdesktop declares the contract and knows nothing about niri; this
  # module reads it and adapts. Reversing that (nixdesktop reading `nixniri.niri.*`) would
  # re-couple the neutral policy layer to one compositor by name, which is the whole thing its
  # split was for.
  #
  # `spawn-sh-at-startup`, not `spawn-at-startup`: contract entries are shell command STRINGS, and
  # niri's plain spawn form takes an argv, so anything with a flag or a pipe would break under it.
  neutralStartup =
    map (c: ''spawn-sh-at-startup "${c}"'') (config.nixdesktop.startup or [ ]);

  # The screen locker for the Super+Alt+L bind, read from nixdesktop's session policy.
  #
  # swayidle's invocation and idle timeouts are host policy, not a niri concern (byte-identical
  # under any wlroots compositor), so this module owns only which KEY locks the screen and what
  # that key spawns -- reading the locker's name defensively and binding it.
  #
  # The `or "swaylock"` fallback keeps a standalone niri user (no nixdesktop module in scope) with a
  # working lock bind rather than an evaluation error. A standalone user wanting a different locker
  # redefines the bind itself through `binds` -- no capability is lost by this module not having its
  # own option, and there is no second place to declare the same fact.
  lockBin = config.nixdesktop.session.idleAndLock.lockCommand or "swaylock";

  # ── Structured output rendering ─────────────────────────────────────────────────────────────
  #
  # Replaces the former `nixniri.niri.output` -- a single raw-KDL string interpolated once for
  # every monitor on every host, which meant nothing here could ever be asserted and no registry
  # could key on it (a host moving a monitor to a different machine got a block that silently
  # stopped applying, with no build-time signal anywhere). Two producers feed the same renderer:
  #
  #   `cfg.outputs`  -- hand-authored per output, host-specific, the escape/manual path.
  #   `cfg.layout`   -- a `nixdesktop.layouts.<name>`, translated automatically, portable between
  #                     hosts because it is keyed by the shared monitor registry rather than by
  #                     hand-copied EDID text. THE MAIN PATH on a host that composes nixdesktop.
  #
  # Both go through `renderOutputBlock`, so there is exactly one place that knows how to turn a
  # resolved output record into niri KDL -- the "everything that can be got wrong twice is got
  # right once" doctrine this whole family follows.

  # niri ALWAYS double-quotes its output-match argument -- connector name or identity triple
  # alike (`output "eDP-1" { ... }`, `output "Some Company CoolMonitor 1234" { ... }`, both from
  # niri's own upstream docs) -- unlike sway/scroll, which need quoting only when the identity
  # triple itself contains a space. Quoting unconditionally means a plain connector name and a
  # multi-word identity triple go through one code path instead of two. Same escaping doctrine as
  # nixscroll's `home/scroll.nix` `quoteName` -- double quotes are niri's DOCUMENTED grammar here,
  # not a shell-quoting convention, so this is not `lib.escapeShellArg`.
  quoteKdl = n: ''"${lib.replaceStrings [ ''"'' ] [ ''\"'' ] n}"'';

  # niri's `modeline` directive (KDL, since niri 25.11) takes the SAME nine timing numbers, in
  # the SAME order, as nixdesktop's neutral `modeline` string (`modules/layouts.nix`) -- but niri
  # wants its trailing sync-polarity flags as QUOTED KDL strings (`"-hsync" "+vsync"`), while the
  # neutral spelling, copied verbatim from sway/scroll's own unquoted grammar, carries none.
  # Requoting only the trailing tokens is the ENTIRE translation; the nine leading numbers pass
  # through byte-identical, and so does their order (verified against niri's own modeline example:
  # `173.00 1920 2048 2248 2576 1080 1083 1088 1120 "-hsync" "+vsync"` is pixelclock/hdisp/
  # hsyncstart/hsyncend/htotal/vdisp/vsyncstart/vsyncend/vtotal, the identical field order
  # nixdesktop's own `parseModeline` reads fields 2 and 6 out of).
  renderModeline =
    raw:
    let
      toks = lib.filter (t: t != "")
        (lib.splitString " " (lib.replaceStrings [ "\t" "\n" ] [ " " " " ] raw));
      numeric = lib.take 9 toks;
      flags = lib.drop 9 toks;
    in
    lib.concatStringsSep " " (numeric ++ map (f: ''"${f}"'') flags);

  # The shared field shape both `cfg.outputs` entries and a translated
  # `nixdesktop.layouts.<name>.outputs.*` entry present to the renderer below. Mirrors the shape
  # nixscroll's own `programs.scroll.outputs` submodule already uses (an attrset of typed fields
  # per output), not its exact field list -- niri's own directives differ from scroll's.
  outputEntryOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether this output is on. `false` renders niri's own `off` flag and NOTHING else --
        that is niri's documented shape for a disabled output (`output "X" { off }`), and
        emitting sibling fields alongside it is needless noise niri's own examples never carry.
      '';
    };

    mode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "3840x2160@60";
      description = ''
        `WIDTHxHEIGHT@REFRESH`, or `null` to let niri auto-detect. The refresh rate, if given,
        must match what `niri msg outputs` reports down to the same decimal digits -- niri's
        own requirement, not this module's.
      '';
    };

    modeline = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
      description = ''
        A raw modeline in nixdesktop's neutral, UNQUOTED spelling -- nine timing numbers then
        bare sync flags (`+hsync +vsync`), the identical string
        `nixdesktop.layouts.<name>.outputs.*.modeline` carries. This module requotes the
        trailing flags for niri's own grammar (see `renderModeline` above); write it unquoted
        here regardless of which compositor eventually reads it. `null` (default) omits the
        directive.
      '';
    };

    scale = lib.mkOption {
      type = lib.types.nullOr lib.types.numbers.positive;
      default = null;
      example = 1.5;
      description = "Logical-pixel scale, or `null` for niri's own guess from physical size.";
    };

    position = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          x = lib.mkOption { type = lib.types.int; description = "Logical-pixel X."; };
          y = lib.mkOption { type = lib.types.int; description = "Logical-pixel Y."; };
        };
      });
      default = null;
      description = ''
        Top-left corner in niri's logical coordinate space, or `null` to let niri place it
        automatically (see niri's own "Automatic Positioning" documentation).
      '';
    };

    transform = lib.mkOption {
      type = lib.types.enum [
        "normal"
        "90"
        "180"
        "270"
        "flipped"
        "flipped-90"
        "flipped-180"
        "flipped-270"
      ];
      default = "normal";
      description = ''
        How the output is turned, COUNTER-CLOCKWISE -- niri's own vocabulary. Read from
        nixdesktop's neutral `nixdesktop.layouts` (identical spelling, identical direction),
        this PASSES THROUGH UNCHANGED: contrast nixscroll's translator, which must swap
        90<->270 and flipped-90<->flipped-270 because sway/scroll's own grammar is clockwise.
        See nixdesktop's `modules/layouts.nix` `transform` option for the measured detail.
        Getting either translator's direction wrong rotates a monitor backwards in a way
        invisible from either compositor's own IPC (sway inverts back when reporting).
      '';
    };
  };

  # One `output "..." {}` block. `matchName` is whatever niri should match on -- a connector
  # name or an identity triple -- this function has no opinion which; `o` is any record carrying
  # the fields in `outputEntryOptions` above (a `cfg.outputs.<name>` submodule value, or a plain
  # attrset built from a translated `nixdesktop.layouts` entry -- both are read identically).
  renderOutputBlock =
    matchName: o:
    let
      body =
        if !o.enable then [ "off" ]
        else lib.filter (l: l != null) [
          (if o.mode != null then "mode ${quoteKdl o.mode}" else null)
          (if o.modeline != null then "modeline ${renderModeline o.modeline}" else null)
          (if o.scale != null then "scale ${toString o.scale}" else null)
          (if o.position != null
            then "position x=${toString o.position.x} y=${toString o.position.y}"
            else null)
          "transform ${quoteKdl o.transform}"
        ];
    in
    ''
      output ${quoteKdl matchName} {
          ${lib.concatStringsSep "\n    " body}
      }'';

  # ── Consuming nixdesktop.layouts / nixdesktop.monitors, through lib.probeFact ────────────────
  #
  # Both are `let`-bound but never FORCED unless `cfg.layout != null` actually asks for them
  # (Nix bindings are lazy) -- so a host that never sets `nixniri.niri.layout` pays nothing and,
  # crucially, never sees a spurious "did not resolve" warning for a namespace it was never
  # trying to read in the first place. See the `layout` option below for why gating on intent
  # rather than probing unconditionally is the right call here: `nixdesktop.layouts` and
  # `nixdesktop.monitors` are each their own composable module inside nixdesktop, so a host
  # importing only nixdesktop's session-policy or startup-contract module has neither composed at
  # all -- a legitimate, silent state this module must not warn about.
  layoutsProbe = probeFact {
    inherit config;
    namespace = "nixdesktop";
    path = [ "layouts" ];
    fallback = { };
  };

  monitorsProbe = probeFact {
    inherit config;
    namespace = "nixdesktop";
    path = [ "monitors" ];
    fallback = { };
  };

  # nixdesktop.layouts.<cfg.layout>.outputs, translated into one-or-more resolved output records
  # each fed to `renderOutputBlock`. An entry addressed `match = "connector"` becomes exactly one
  # block, keyed by its connector name. An entry addressed `match = "identity"` becomes one block
  # PER IDENTITY VARIANT the panel can present -- its own `identifier` AND every one of its
  # `aliases`' `identifier`s, because the SAME physical panel reports a DIFFERENT EDID per input
  # (nixdesktop's `modules/monitors.nix` header) and niri matches on whichever string the
  # connected wire happens to report. A block missing for the currently-live variant behaves
  # exactly like no block at all -- the output silently keeps its default mode/position/scale --
  # so every variant gets the identical rendered fields.
  layoutOutputBlocks =
    if cfg.layout == null then [ ]
    else
      let
        layout = layoutsProbe.value.${cfg.layout};
        resolvedEntry = o: {
          inherit (o) enable mode modeline scale position transform;
        };
        matchNamesOf = o:
          if o.match == "connector" then [ o.connector ]
          else
            let m = monitorsProbe.value.${o.monitor}; in
            [ m.identifier ] ++ map (a: a.identifier) m.aliases;
      in
      lib.concatMap
        (o: map (name: renderOutputBlock name (resolvedEntry o)) (matchNamesOf o))
        layout.outputs;

  # ── Consuming nixdesktop.sessions.<cfg.session>.{permittedDevices,deniedDevices} ─────────────
  #
  # niri has NO allowlist -- it enumerates every DRM device on the seat unconditionally -- so the
  # only lever is `debug { ignore-drm-device }`, the COMPLEMENT of the permitted set over the
  # WHOLE inventory (already computed once, by nixdesktop's own `modules/session.nix`), plus
  # `debug { render-drm-device }` naming the single PRIMARY permitted device
  # (`permittedDevices` is ordered primary-first: "exclusive" claims before "shared" ones -- see
  # nixdesktop's own module). This is why nixdesktop's device inventory must be COMPLETE: a
  # device that exists but was never declared there is in NEITHER list, so it is never ignored
  # and leaks straight into niri's enumeration -- on this estate that would mean the forbidden
  # RX 6800 being opened by the one session forbidden to touch it.
  #
  # nixdesktop hands back DEVICE NAMES ("amd", "ast", "evdi"), not paths -- see
  # `permittedDevices`/`deniedDevices`'s own option headers in nixdesktop's `modules/session.nix`.
  # A launcher resolving a NAME to a live path at process-start time is the right answer for
  # scroll, because `WLR_DRM_DEVICES` is an environment variable wlroots reads when it starts --
  # but niri reads `debug { render-drm-device; ignore-drm-device; }` STRAIGHT OUT OF config.kdl
  # ON DISK, with no launcher step in between, so a bare name sitting in that file matches no
  # live device niri has ever heard of and enforces NO restriction at all while looking like
  # perfectly valid KDL. `stableDevicePathsProbe` below is the second half of the translation
  # this file owns: NAME -> stable `/dev/dri/by-path/*` PATH, resolved at Nix eval time via
  # `nixgpu.stableDevicePaths.devices` (the same registry nixdesktop's own inventory mirror is
  # keyed from) -- see `devicePathFor`.
  sessionsProbe = probeFact {
    inherit config;
    namespace = "nixdesktop";
    path = [ "sessions" ];
    fallback = { };
  };

  # The niri `debug` namespace excludes itself from niri's own config stability policy (see the
  # `session`/`package` options), so this module pins itself to the exact niri release range its
  # `render-drm-device`/`ignore-drm-device` translation was verified against, rather than
  # trusting "it happens to still parse". `ignore-drm-device` shipped in niri 25.11 (niri's own
  # Configuration: Debug Options wiki page: "Since: 25.11") -- a niri older than that has no way
  # to express a denylist at all, so this module's whole device-restriction mechanism is
  # unavailable below it. No upper bound yet: raise this once a future niri release is verified
  # to have renamed or dropped either key.
  minNiriDebugDeviceVersion = "25.11";

  stableDevicePathsProbe = probeFact {
    inherit config;
    namespace = "nixgpu";
    path = [ "stableDevicePaths" "devices" ];
    fallback = { };
  };

  # `renderPath` is preferred (niri's own wiki examples exclusively show `renderD*` paths), but
  # `cardPath` is not a fallback of last resort -- it is the CORRECT, COMPLETE answer for a
  # device niri's own source proves has no render node to name. Verified against niri's real
  # `primary_node_from_render_node` (niri 26.04, `src/backend/tty.rs`; both `render-drm-device`
  # and `ignore-drm-device` route through it): given a path that is not itself a render node, it
  # looks up that node's render-node SIBLING and uses it, and when no sibling exists at all --
  # exactly the evdi / AST-BMC-framebuffer case, `hasRenderNode = false` -- it falls back to the
  # node it was given, for both halves of the pair, logging a warning and returning no error. So
  # a card-only device's `cardPath` resolves correctly here, matching niri's own documented
  # fallback rather than working around it.
  devicePathFor = deviceName:
    let d = stableDevicePathsProbe.value.${deviceName};
    in if d.renderPath != null then d.renderPath else d.cardPath;

  deviceDebugLines =
    if cfg.session == null then [ ]
    else
      let
        s = sessionsProbe.value.${cfg.session};
        permitted = s.permittedDevices;
        denied = s.deniedDevices;
      in
      lib.optional (permitted != [ ])
        "render-drm-device ${quoteKdl (devicePathFor (lib.head permitted))}"
      ++ map (d: "ignore-drm-device ${quoteKdl (devicePathFor d)}") denied;

  # REAL /dev/dri/by-path/* PATHS, not device names -- the opposite of what an earlier version of
  # this file rendered here. niri reads `debug { render-drm-device; ignore-drm-device; }`
  # STRAIGHT OUT OF config.kdl ON DISK; there is no launcher step between home-manager writing
  # this file and niri parsing it, so a bare NAME here (unlike scroll's `WLR_DRM_DEVICES`, an
  # environment variable a launcher genuinely can still resolve at process-start time) would
  # parse as a perfectly valid config that restricts NOTHING: niri matches it against a live
  # sysfs path, finds no device by that name, and enumerates every DRM device on the seat exactly
  # as if `session` had never been set -- silently. `address`, and `cardPath`/`renderPath` derived
  # from it, ARE knowable at Nix eval time (a PCI slot or platform device name, fixed at
  # build/install time, unlike a card NUMBER, which is enumeration order and genuinely
  # renumbers -- see nixgpu's own `stableDevicePaths.devices.<name>.address` header), which is
  # exactly what lets this module bake the real path in here instead of deferring to a runtime
  # resolver niri would never call.
  deviceDebugBlock =
    if deviceDebugLines == [ ] then ""
    else
      ''

        // ⚠ VOLATILE: both keys below live under niri's own `debug` namespace, which niri's
        // documentation explicitly excludes from its config breaking-change policy -- an
        // upgrade can rename or remove either silently. See nixniri's `session` and `package`
        // options -- `package`, once set, turns this from a comment into a build-time assertion.
        debug {
            ${lib.concatStringsSep "\n    " deviceDebugLines}
        }'';

  # Every block this module knows how to produce, in one list: hand-authored entries first
  # (`cfg.outputs`, keyed by `lib.attrNames` order, which Nix guarantees sorted), then the
  # layout-derived blocks, then the raw escape hatch. Attribute-name order is stable and
  # cosmetic-only here -- niri applies whichever block matches the live output, regardless of
  # where in the file it appears.
  outputsSection =
    let
      manualBlocks = lib.mapAttrsToList renderOutputBlock cfg.outputs;
      allBlocks = manualBlocks ++ layoutOutputBlocks;
    in
    if allBlocks == [ ] && cfg.extraOutputs == "" then
      ''
        // No output declared -- niri auto-detects. Run `niri msg outputs` on-box to find the
        // real name if you want to pin mode/scale/position: `nixniri.niri.outputs` (manual,
        // per-host) or `nixniri.niri.layout` (nixdesktop-derived, portable between hosts).
      ''
    else
      lib.concatStringsSep "\n\n" (allBlocks ++ lib.optional (cfg.extraOutputs != "") cfg.extraOutputs);

  presetWidthsSection = lib.concatMapStringsSep "\n        " (p: "proportion ${toString p}") cfg.presetColumnWidths;

  osdClient = "swayosd-client";

  # A bind is either a bare action string -- shorthand for "no hotkey-overlay title, no
  # flags", which covers most movement/layout binds -- or the full submodule below, for
  # when a bind needs a title or one of the flags niri supports on a bind. `action` is raw
  # KDL, written exactly as it appears inside the bind's `{ }` block (`close-window`,
  # `spawn "foo"`, `spawn-sh "foo | bar"`, `toggle-overview`, ...); this module supplies the
  # surrounding `{ ...; }` and the trailing semicolon.
  bindType = lib.types.submodule {
    options = {
      action = lib.mkOption {
        type = lib.types.str;
        example = ''spawn "foot"'';
        description = "The niri action this bind runs, written exactly as it appears inside the bind's `{ }` block.";
      };

      hotkeyOverlayTitle = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "Open a Terminal";
        description = ''
          Label shown for this bind in niri's hotkey overlay (Mod+Shift+Slash). Null, the
          default, omits the field -- niri leaves untitled binds out of the overlay
          entirely, rather than listing them with a blank label.
        '';
      };

      allowWhenLocked = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether the bind still fires while the session is locked. niri's own default is
          false; the volume/brightness/media-key and lock binds below flip this to true so
          they keep working at the lock screen.
        '';
      };

      repeat = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether holding the key repeats the action. niri's own default is true; set
          false for actions that only make sense once per press, like closing a window.
        '';
      };

      allowInhibiting = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether an application requesting exclusive keyboard-shortcut access (a game, a
          VM viewer) is allowed to swallow this bind. niri's own default is true; the bind
          that toggles shortcuts-inhibit itself flips this to false so there is always a
          way to back out of an inhibited session.
        '';
      };
    };
  };

  # Render the flags that go between a bind's key combo and its `{ }` block. Only ever
  # emits a flag when it differs from niri's own default (see the options above) -- e.g.
  # plain `Mod+Left { focus-column-left; }`, never `Mod+Left repeat=true { ...; }`.
  renderBindFlags = b: lib.concatStringsSep " " (
    lib.optional (b.hotkeyOverlayTitle != null) ''hotkey-overlay-title="${b.hotkeyOverlayTitle}"''
    ++ lib.optional b.allowWhenLocked "allow-when-locked=true"
    ++ lib.optional (!b.repeat) "repeat=false"
    ++ lib.optional (!b.allowInhibiting) "allow-inhibiting=false"
  );

  # Render one `binds { }` line for one `cfg.binds` entry. `null` -- a removed bind -- drops
  # out via the `lib.filter` in `bindsSection` below.
  renderBind = name: value:
    if value == null then
      null
    else if builtins.isString value then
      "${name} { ${value}; }"
    else
      let
        flags = renderBindFlags value;
      in
      "${name}${lib.optionalString (flags != "") " ${flags}"} { ${value.action}; }";

  # `lib.mapAttrsToList` walks `cfg.binds` in `builtins.attrNames` order, which Nix
  # guarantees is sorted -- so the rendered block is alphabetical by key combo. Cosmetic
  # only: niri does not care what order binds appear in within `binds { }`.
  bindsSection = lib.concatStringsSep "\n    " (
    lib.filter (l: l != null) (lib.mapAttrsToList renderBind cfg.binds)
  );
in
{
  options.nixniri.niri = {
    enable = lib.mkEnableOption "declarative niri config (~/.config/niri/config.kdl)";

    keyboard = {
      layout = lib.mkOption {
        type = lib.types.str;
        default = "us";
        example = "ch";
        description = "XKB keyboard layout.";
      };
      variant = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "de_nodeadkeys";
        description = "XKB keyboard variant. Empty string omits the field.";
      };
    };

    outputs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule { options = outputEntryOptions; });
      default = { };
      example = lib.literalExpression ''
        {
          "eDP-1" = { enable = false; };
          "Dell Inc. DELL U4323QE 9BQR2P3" = {
            mode = "3840x2160@60";
            scale = 1.5;
            position = { x = 0; y = 0; };
          };
        }
      '';
      description = ''
        One niri `output "..." {}` block per entry, keyed by the EXACT string niri should match
        an output against -- a connector name ("eDP-1", "HDMI-A-1") or the
        "<make> <model> <serial>" identity triple (see nixdesktop's `modules/monitors.nix` for
        how that triple is built, on a host that composes it). This module never inspects the
        key: it quotes it and writes it, unconditionally, the identical structural shape
        nixscroll's `programs.scroll.outputs` already uses.

        THE MAIN PATH for a host with no `nixdesktop.layouts` to name -- this REPLACES the
        former `nixniri.niri.output` (a single raw-KDL string interpolated once for every
        monitor, in which nothing could ever be asserted and no registry could key on it). On a
        host that composes nixdesktop, prefer naming a `layout` (below) instead of hand-filling
        this option: a layout is portable between hosts and keyed by the shared registry, this
        option is host-specific hand-typed text. The two are additive -- both render into the
        same generated file -- for the case where a host wants nixdesktop's registry for most
        outputs and a hand-authored stanza for one it does not.
      '';
    };

    layout = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "docked";
      description = ''
        A `nixdesktop.layouts.<name>` to render as niri output blocks, read through
        `lib.probeFact` (see this file's own top-of-file comment on the `probeFact` module
        argument, and the README on the `nixhost` flake input this needs -- never a flake input
        on nixdesktop itself).

        Each layout entry becomes ONE OR MORE `output {}` blocks: an entry addressed by
        `match = "connector"` becomes exactly one, keyed by its connector name; an entry
        addressed by `match = "identity"` becomes one block per identity variant the panel can
        present -- the monitor's own `identifier` AND every one of its `aliases`' `identifier`s
        (the SAME panel through a different input reports a DIFFERENT EDID, see nixdesktop's
        `modules/monitors.nix` header) -- because niri matches on whichever string the connected
        wire happens to report, and a block missing for the currently-live variant behaves
        exactly like no block at all.

        `transform` PASSES THROUGH UNCHANGED: nixdesktop's neutral vocabulary is
        counter-clockwise, matching `wl_output` (and niri's own config values) exactly, so this
        translator does no inversion at all. Contrast nixscroll's translator, which MUST swap
        90<->270 and flipped-90<->flipped-270, because sway/scroll's own config grammar is
        clockwise -- see nixdesktop's `modules/layouts.nix` `transform` option for the measured
        detail. Getting either translator's direction wrong rotates a monitor backwards in a
        way invisible from either compositor's own IPC.

        `null` (default) renders no layout-derived blocks at all -- the correct, silent stance
        for a host with no `nixdesktop.layouts` composed, or that only wants `outputs` above.
        Naming a layout that `nixdesktop.layouts` does not declare (or that nixdesktop is not
        composed on this host at all) is a build failure, not a silent no-op -- see this
        module's own `assertions`.
      '';
    };

    session = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "primary";
      description = ''
        A `nixdesktop.sessions.<name>` whose resolved `permittedDevices`/`deniedDevices`
        becomes this niri instance's device restriction, read through `lib.probeFact`. niri has
        NO allowlist -- it enumerates every DRM device on the seat unconditionally -- so the
        only lever is `debug { ignore-drm-device }`, one per device this session may NOT touch
        (the complement of the permitted set over the WHOLE inventory, already computed by
        nixdesktop's `modules/session.nix`), plus `debug { render-drm-device }` naming the
        single PRIMARY permitted device. This is why nixdesktop's device inventory must be
        COMPLETE: a device that exists but was never declared is in neither list, so it is
        never ignored and leaks straight into niri's enumeration.

        nixdesktop hands back DEVICE NAMES ("amd", "ast", "evdi"); this module resolves each one
        to a stable `/dev/dri/by-path/*` PATH via `nixgpu.stableDevicePaths.devices.<name>.
        {cardPath,renderPath}` (also read through `lib.probeFact`) and renders PATHS, never
        names, into the `debug` block. That resolution has to happen HERE, at Nix eval time:
        niri reads `config.kdl` straight off disk, with no launcher step in between, so a bare
        name would parse as valid KDL matching no live device and enforce nothing at all --
        silently. A card NUMBER (`/dev/dri/card1`) is the one spelling that could not be used
        instead: DRM minors are enumeration order and genuinely renumber on live hardware (an
        evdi module load renumbered this estate's host on 2026-07-29). `address` does not: it is
        a PCI slot or platform device name, fixed at build/install time, which is exactly what
        makes `cardPath`/`renderPath` safe to bake in here rather than defer to a resolver niri
        would never call. Naming a device that `nixgpu.stableDevicePaths.devices` does not
        declare, or that declares no `address`, is a build failure -- see this module's own
        `assertions`.

        ⚠ Both `debug` keys live under niri's own `debug` namespace, which niri's documentation
        explicitly excludes from its config breaking-change policy -- a niri upgrade can rename
        or remove either with no notice. Setting `session` therefore REQUIRES `package` too (see
        that option, below): this module asserts `package`'s own `.version` is new enough to
        still have these keys, so an incompatible niri upgrade fails the build instead of
        silently rendering a `debug` block niri no longer understands, and therefore no longer
        enforces.

        `null` (default): no device restriction is rendered at all. Naming a session that
        `nixdesktop.sessions` does not declare (or that nixdesktop is not composed on this host
        at all) is a build failure -- see this module's own `assertions`.
      '';
    };

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.niri";
      description = ''
        The REAL niri package this generated config will run under. Used ONLY to assert its
        `.version` -- same doctrine as nixscroll's own `package` option (`home/scroll.nix`):
        never added to `home.packages`, this module installs nothing, a platform backend
        resolves the real binary that actually runs.

        `null` (the default) is fine for a config that never sets `session`: nothing else here
        reads niri's own volatile `debug` namespace, so there is no version-sensitive
        translation to verify. The moment `session` is set, `package` becomes REQUIRED, by
        assertion, not merely recommended -- device restriction is a security boundary, and
        whether niri STILL has `render-drm-device`/`ignore-drm-device` (niri's documentation
        explicitly excludes `debug` from its config stability policy -- either key can be
        renamed or removed with no notice) is exactly the one fact this module cannot verify
        without a real package to ask.
      '';
    };

    extraOutputs = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra raw KDL, verbatim, appended after every generated `output {}` block -- for
        whatever the structured `outputs`/`layout` surfaces above cannot express (same
        escape-hatch doctrine as `extraWindowRules`/`extraBinds`/`extraTopLevel` below).
      '';
    };

    workspaceCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 9;
      description = ''
        Number of named, always-present workspaces ("1".."N"). Declared in ascending order --
        workspace "1" is niri's own index 1 (top of the vertical stack), counting down to "N"
        at the bottom, matching left-to-right ascending order in a workspace-indicator bar
        (waybar's niri/workspaces module lists by niri index, not by name).
      '';
    };

    presetColumnWidths = lib.mkOption {
      type = lib.types.listOf lib.types.float;
      default = [ 0.33333 0.5 0.66667 ];
      example = [ 0.25 0.33333 0.5 0.66667 0.75 ];
      description = ''
        Widths (as a fraction of output width) that Mod+R (switch-preset-column-width)
        cycles through. The niri-upstream default is thirds/half/two-thirds; add 0.25/0.75
        for a 3-column 25:50:25-style layout.
      '';
    };

    terminal = lib.mkOption {
      type = lib.types.str;
      default = "foot";
      example = "kitty";
      description = "Terminal emulator bound to Mod+T.";
    };

    launcher = lib.mkOption {
      type = lib.types.str;
      default = "fuzzel";
      description = "App launcher bound to Mod+D (and used by the clipboard-history bind).";
    };

    clipboardHistory = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Wire the Mod+Alt+V clipboard-history picker bind (through the configured launcher).
        The wl-paste watcher processes that actually feed cliphist's history run elsewhere
        now -- nixdesktop's home/session.nix starts them as a systemd user service -- so this option
        only controls the picker bind, and does nothing useful without that service also
        running. Requires the `cliphist` and `wl-clipboard` packages present (see
        profiles/desktop.nix).
      '';
    };

    binds = lib.mkOption {
      type = lib.types.attrsOf (lib.types.nullOr (lib.types.either lib.types.str bindType));
      default = { };
      example = {
        "Mod+T" = ''spawn "kitty"'';
        "Print" = null;
        "Mod+Z" = ''spawn "my-script"'';
      };
      description = ''
        Keybindings, keyed by the exact niri key-combo string ("Mod+T",
        "XF86AudioRaiseVolume", ...). Every binding this module ships lives here as a
        CONFIG-side default (see the `config` block below), never in this option's own
        `default` (which stays `{ }`) -- an `attrsOf` option's `default` is discarded in
        full the instant a consumer defines the option at all, even for one unrelated key,
        whereas config-side definitions merge attribute-by-attribute against it. Same trap
        nixk3s's tenancy module documents for its `projects` option.

        A plain string is shorthand for a bind with no hotkey-overlay title and no flags --
        the common case. Use the submodule (`action`, `hotkeyOverlayTitle`,
        `allowWhenLocked`, `repeat`, `allowInhibiting`) when a bind needs either.

        - ADD a bind: define a new key.
        - OVERRIDE a shipped bind: redefine its key with a new value. This replaces the
          shipped entry WHOLESALE -- string or submodule, every field -- rather than
          merging field-by-field against the shipped one. See the `config` block for why:
          for this option's type, partial field overrides and clean null-removal are in
          tension, and removal is the one this module can't do without.
        - REMOVE a shipped bind: redefine its key as `null`.
      '';
    };

    extraStartup = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ ''spawn-at-startup "mako"'' ];
      description = "Extra raw spawn-at-startup / spawn-sh-at-startup lines, verbatim.";
    };

    extraWindowRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra raw `window-rule {}` blocks, verbatim, appended after the built-in ones.";
    };

    extraBinds = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra raw keybind lines, verbatim, appended inside the `binds {}` block after every
        entry from the `binds` option above. Kept as an escape hatch even though `binds`
        now covers add/override/remove for ordinary bindings: this module's bind submodule
        only models the flags this file's own shipped binds actually use
        (`hotkey-overlay-title`, `allow-when-locked`, `repeat`, `allow-inhibiting`), and
        niri's bind syntax was not exhaustively re-verified against its own docs while
        writing it -- a property it supports that isn't modelled here (e.g. `cooldown-ms`)
        has no home in `binds` and belongs here instead.
      '';
    };

    osd = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "swayosd" ]);
      default = null;
      description = ''
        On-screen-display for volume/brightness/mic-mute. `"swayosd"` swaps the volume/
        brightness/mic-mute binds below from raw wpctl/brightnessctl calls to swayosd-client,
        which performs the same action AND shows a popup. Requires the `swayosd` package and a
        running `swayosd-server` (spawn it yourself via extraStartup -- this profile doesn't).
        Null keeps the original silent wpctl/brightnessctl binds.
      '';
    };

    extraTopLevel = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        debug {
            enable-overlay-planes
        }
      '';
      description = ''
        Extra raw top-level KDL blocks, verbatim, appended at the end of the file (outside
        `binds {}`/`window-rule {}` -- for things like a `debug {}` block).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The shipped keybindings. Two rules, both non-obvious, both required for the
    # override/remove/add contract on the `binds` option above to actually hold:
    #
    #  1. Every entry lives here, config-side, as its own `lib.mkDefault` -- not gathered
    #     into the option's own `default = { }`. An `attrsOf` option's `default` is
    #     discarded WHOLESALE the instant a consumer defines the option at all (even for
    #     one unrelated key), so a shipped default can only survive a consumer's own
    #     additions by living in `config`, where definitions merge attribute-by-attribute.
    #     Same trap, same fix, as nixk3s's tenancy module and its `projects` option.
    #
    #  2. `mkDefault` has to wrap the WHOLE VALUE at each key, not each field within it.
    #     `binds`' element type is `nullOr (either str submodule)`, and `nullOr`'s merge
    #     THROWS ("defined both null and not null") if a null definition and a non-null
    #     definition for the same key ever reach it at the SAME priority. A consumer's
    #     plain (normal-priority) `binds.NAME = null;` removal would race the shipped
    #     entry for that exact key -- UNLESS the shipped entry sits at strictly lower
    #     (`mkDefault`) priority, so ordinary priority resolution drops it before `nullOr`
    #     ever runs, leaving only the consumer's `null` behind. The price is that override
    #     is whole-key, not whole-field: redefining "Mod+T" replaces its action, title and
    #     flags together, because a per-FIELD `mkDefault` here would let a consumer's
    #     single-field redefinition outrank -- and silently drop -- the shipped entry's
    #     OTHER fields, which is the opposite of what an override should do.
    nixniri.niri.binds = {
      "Mod+Shift+Slash" = lib.mkDefault "show-hotkey-overlay";

      "Mod+T" = lib.mkDefault {
        action = ''spawn "${cfg.terminal}"'';
        hotkeyOverlayTitle = "Open a Terminal";
      };
      "Mod+D" = lib.mkDefault {
        action = ''spawn "${cfg.launcher}"'';
        hotkeyOverlayTitle = "Run an Application";
      };
      "Super+Alt+L" = lib.mkDefault {
        action = ''spawn "${lockBin}"'';
        hotkeyOverlayTitle = "Lock the Screen";
      };

      "XF86AudioRaiseVolume" = lib.mkDefault {
        allowWhenLocked = true;
        action =
          if cfg.osd == "swayosd"
          then ''spawn "${osdClient}" "--output-volume=raise"''
          else ''spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"'';
      };
      "XF86AudioLowerVolume" = lib.mkDefault {
        allowWhenLocked = true;
        action =
          if cfg.osd == "swayosd"
          then ''spawn "${osdClient}" "--output-volume=lower"''
          else ''spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"'';
      };
      "XF86AudioMute" = lib.mkDefault {
        allowWhenLocked = true;
        action =
          if cfg.osd == "swayosd"
          then ''spawn "${osdClient}" "--output-volume=mute-toggle"''
          else ''spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"'';
      };
      "XF86AudioMicMute" = lib.mkDefault {
        allowWhenLocked = true;
        action =
          if cfg.osd == "swayosd"
          then ''spawn "${osdClient}" "--input-volume=mute-toggle"''
          else ''spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"'';
      };

      "XF86AudioPlay" = lib.mkDefault { allowWhenLocked = true; action = ''spawn-sh "playerctl play-pause"''; };
      "XF86AudioStop" = lib.mkDefault { allowWhenLocked = true; action = ''spawn-sh "playerctl stop"''; };
      "XF86AudioPrev" = lib.mkDefault { allowWhenLocked = true; action = ''spawn-sh "playerctl previous"''; };
      "XF86AudioNext" = lib.mkDefault { allowWhenLocked = true; action = ''spawn-sh "playerctl next"''; };

      "XF86MonBrightnessUp" = lib.mkDefault {
        allowWhenLocked = true;
        action =
          if cfg.osd == "swayosd"
          then ''spawn "${osdClient}" "--brightness=raise"''
          else ''spawn "brightnessctl" "--class=backlight" "set" "+10%"'';
      };
      "XF86MonBrightnessDown" = lib.mkDefault {
        allowWhenLocked = true;
        action =
          if cfg.osd == "swayosd"
          then ''spawn "${osdClient}" "--brightness=lower"''
          else ''spawn "brightnessctl" "--class=backlight" "set" "10%-"'';
      };

      "Mod+O" = lib.mkDefault { action = "toggle-overview"; repeat = false; };
      "Mod+Q" = lib.mkDefault { action = "close-window"; repeat = false; };

      "Mod+Left" = lib.mkDefault "focus-column-left";
      "Mod+Down" = lib.mkDefault "focus-window-or-workspace-down";
      "Mod+Up" = lib.mkDefault "focus-window-or-workspace-up";
      "Mod+Right" = lib.mkDefault "focus-column-right";
      "Mod+H" = lib.mkDefault "focus-column-left";
      "Mod+J" = lib.mkDefault "focus-window-or-workspace-down";
      "Mod+K" = lib.mkDefault "focus-window-or-workspace-up";
      "Mod+L" = lib.mkDefault "focus-column-right";

      "Mod+Ctrl+Left" = lib.mkDefault "move-column-left";
      "Mod+Ctrl+Down" = lib.mkDefault "move-window-down-or-to-workspace-down";
      "Mod+Ctrl+Up" = lib.mkDefault "move-window-up-or-to-workspace-up";
      "Mod+Ctrl+Right" = lib.mkDefault "move-column-right";
      "Mod+Ctrl+H" = lib.mkDefault "move-column-left";
      "Mod+Ctrl+J" = lib.mkDefault "move-window-down-or-to-workspace-down";
      "Mod+Ctrl+K" = lib.mkDefault "move-window-up-or-to-workspace-up";
      "Mod+Ctrl+L" = lib.mkDefault "move-column-right";

      "Mod+Home" = lib.mkDefault "focus-column-first";
      "Mod+End" = lib.mkDefault "focus-column-last";

      "Mod+Page_Down" = lib.mkDefault "focus-workspace-down";
      "Mod+Page_Up" = lib.mkDefault "focus-workspace-up";
      "Mod+U" = lib.mkDefault "focus-workspace-down";
      "Mod+I" = lib.mkDefault "focus-workspace-up";

      "Mod+BracketLeft" = lib.mkDefault "consume-or-expel-window-left";
      "Mod+BracketRight" = lib.mkDefault "consume-or-expel-window-right";
      "Mod+Comma" = lib.mkDefault "consume-window-into-column";
      "Mod+Period" = lib.mkDefault "expel-window-from-column";

      "Mod+R" = lib.mkDefault "switch-preset-column-width";
      "Mod+Shift+R" = lib.mkDefault "switch-preset-column-width-back";

      "Mod+F" = lib.mkDefault "maximize-column";
      "Mod+Shift+F" = lib.mkDefault "fullscreen-window";
      "Mod+M" = lib.mkDefault "maximize-window-to-edges";
      "Mod+C" = lib.mkDefault "center-column";

      "Mod+Minus" = lib.mkDefault ''set-column-width "-10%"'';
      "Mod+Equal" = lib.mkDefault ''set-column-width "+10%"'';

      "Mod+V" = lib.mkDefault "toggle-window-floating";
      "Mod+Shift+V" = lib.mkDefault "switch-focus-between-floating-and-tiling";

      "Mod+W" = lib.mkDefault "toggle-column-tabbed-display";

      "Print" = lib.mkDefault "screenshot";
      "Ctrl+Print" = lib.mkDefault "screenshot-screen";
      "Alt+Print" = lib.mkDefault "screenshot-window";

      "Mod+Escape" = lib.mkDefault { action = "toggle-keyboard-shortcuts-inhibit"; allowInhibiting = false; };
      "Mod+Shift+E" = lib.mkDefault "quit";
      "Mod+Shift+P" = lib.mkDefault "power-off-monitors";
    }
    # The clipboard-history picker bind, gated on `clipboardHistory` like the rest of that
    # feature. This is a normal user-invoked keybinding, not a startup daemon, so it is
    # unaffected by the wl-paste watchers living in nixdesktop's home/session.nix.
    // lib.optionalAttrs cfg.clipboardHistory {
      "Mod+Alt+V" = lib.mkDefault ''spawn-sh "cliphist list | ${cfg.launcher} --dmenu | cliphist decode | wl-copy"'';
    }
    # The per-workspace focus binds (Mod+1..Mod+N) are generated from `workspaceCount`, but
    # they land in this SAME `binds` set, each its own `mkDefault` entry, rather than a
    # separately-rendered block outside it. Deliberately: that keeps them subject to the
    # identical override/remove/add rules as every hand-written bind above -- a consumer who
    # wants Mod+9 to do something else, or wants it gone, redefines or nulls "Mod+9" exactly
    # like they would "Mod+T", with no second escape hatch to learn for "generated" binds.
    // lib.listToAttrs (map
      (n: lib.nameValuePair "Mod+${toString n}" (lib.mkDefault "focus-workspace ${toString n}"))
      (lib.range 1 cfg.workspaceCount));

    # ── The seams read through lib.probeFact, both gated on the option that expresses intent ──
    #
    # Neither seam probes unconditionally: see `layoutsProbe`/`monitorsProbe`/`sessionsProbe`
    # above for why an always-on probe would misreport "nixdesktop.layouts was renamed" about a
    # host that simply never named a `layout` (or a `session`) in the first place.
    assertions =
      lib.optionals (cfg.layout != null) (
        [{
          assertion = layoutsProbe.value ? ${cfg.layout};
          message = ''
            nixniri.niri.layout names "${cfg.layout}", which nixdesktop.layouts does not
            declare (or nixdesktop.layouts is not composed on this host at all). Declared:
            ${if layoutsProbe.value == { }
              then "  (none)"
              else lib.concatMapStringsSep "\n" (n: "  - ${n}") (lib.attrNames layoutsProbe.value)}
          '';
        }]
        ++ lib.optionals (layoutsProbe.value ? ${cfg.layout}) (map
          (o: {
            assertion = o.match != "identity" || monitorsProbe.value ? ${o.monitor};
            message = ''
              nixniri.niri.layout "${cfg.layout}" addresses monitor "${o.monitor}" by
              identity, but nixdesktop.monitors does not declare that slug (or
              nixdesktop.monitors is not composed on this host at all). Without it there is
              no "<make> <model> <serial>" triple to emit -- either compose
              nixdesktop.monitors, or address this output by connector instead.
            '';
          })
          layoutsProbe.value.${cfg.layout}.outputs)
      )
      ++ lib.optional (cfg.session != null) {
        assertion = sessionsProbe.value ? ${cfg.session};
        message = ''
          nixniri.niri.session names "${cfg.session}", which nixdesktop.sessions does not
          declare (or nixdesktop.sessions is not composed on this host at all). Declared:
          ${if sessionsProbe.value == { }
            then "  (none)"
            else lib.concatMapStringsSep "\n" (n: "  - ${n}") (lib.attrNames sessionsProbe.value)}
        '';
      }

      # ── device restriction is a security boundary: pin the niri VERSION, don't just warn ────
      #
      # niri's `debug` namespace is explicitly excluded from its own config stability policy
      # (see the `session`/`package` options), so trusting that `render-drm-device`/
      # `ignore-drm-device` still exist on whatever niri happens to be installed is exactly the
      # silent-regression risk this whole mechanism exists to close. A real `package` is what
      # lets this module ask instead of assume -- a warning alone (what this module used to
      # ship) never stops a build, so an upgrade that drops both keys would still converge.
      ++ lib.optional (cfg.session != null) {
        assertion = cfg.package != null;
        message = ''
          nixniri.niri.session = "${toString cfg.session}" renders niri's
          `debug { render-drm-device; ignore-drm-device; }` block. Both keys live under niri's
          own `debug` namespace, which niri's documentation explicitly excludes from its config
          breaking-change policy -- an upgrade can rename or remove either with no notice. Set
          nixniri.niri.package to the real niri derivation this config will run under (e.g.
          `pkgs.niri`) so this module can assert its version instead of silently trusting that a
          future niri release still has these keys.
        '';
      }
      ++ lib.optional (cfg.session != null && cfg.package != null) {
        assertion = lib.versionAtLeast cfg.package.version minNiriDebugDeviceVersion;
        message = ''
          nixniri.niri.session = "${toString cfg.session}" needs niri >=
          ${minNiriDebugDeviceVersion} -- `ignore-drm-device` (niri's own Configuration: Debug
          Options wiki page: "Since: 25.11") is what this module's device denylist is built on,
          and an older niri has no way to express one at all. nixniri.niri.package is niri
          ${cfg.package.version}. Device restriction has no fallback here: there is no other way
          to tell niri which DRM devices to leave alone.
        '';
      }

      # ── every device this session names must resolve to a real, stable path ────────────────
      #
      # A name absent from nixgpu.stableDevicePaths.devices (or present with no `address`) is
      # not survivable the way an unset `layout`/`session` is: it would either throw a raw,
      # nixgpu-internal error the moment `devicePathFor` forces `cardPath` (see that option's own
      # `readOnly` default in nixgpu), or -- worse, if this module caught that some other way --
      # silently drop one line out of the `debug` block, exactly the "device leaks into niri's
      # enumeration" failure this whole mechanism exists to prevent. Naming it here, precisely,
      # beats either.
      ++ lib.optionals (cfg.session != null && sessionsProbe.value ? ${cfg.session}) (
        let
          s = sessionsProbe.value.${cfg.session};
          namedDevices = s.permittedDevices ++ s.deniedDevices;
        in
        map
          (d: {
            assertion = stableDevicePathsProbe.value ? ${d};
            message = ''
              nixniri.niri.session = "${cfg.session}" names device "${d}" (via
              nixdesktop.sessions.${cfg.session}.permittedDevices/deniedDevices), which
              nixgpu.stableDevicePaths.devices does not declare (or nixgpu.stableDevicePaths is
              not composed on this host at all). Declared:
              ${if stableDevicePathsProbe.value == { }
                then "  (none)"
                else lib.concatMapStringsSep "\n" (n: "  - ${n}") (lib.attrNames stableDevicePathsProbe.value)}
              Every device a session may render with or must ignore has to resolve to a stable
              /dev/dri/by-path/* entry at eval time -- there is no other moment niri's own
              config.kdl can be given one.
            '';
          })
          namedDevices
        ++ map
          (d: {
            assertion = !(stableDevicePathsProbe.value ? ${d}) || stableDevicePathsProbe.value.${d}.address != null;
            message = ''
              nixniri.niri.session = "${cfg.session}" names device "${d}", but
              nixgpu.stableDevicePaths.devices.${d} declares no `address`. `cardPath`/
              `renderPath` are DERIVED from `address` alone (a PCI domain:bus:device.function or
              platform device name) -- without it neither can be computed, and this module has
              no stable path left to put in niri's `debug` block for it. Set
              nixgpu.stableDevicePaths.devices.${d}.address on the GPU-bearing host.
            '';
          })
          namedDevices
      );

    warnings =
      lib.optionals (cfg.layout != null) (collectProbes [ layoutsProbe monitorsProbe ]).warnings
      ++ lib.optionals (cfg.session != null) (collectProbes [ sessionsProbe stableDevicePathsProbe ]).warnings
      ++ lib.optional (deviceDebugLines != [ ]) ''
        nixniri.niri.session = "${toString cfg.session}" renders niri's
        `debug { render-drm-device; ignore-drm-device; }` block, resolved to real
        /dev/dri/by-path/* paths via nixgpu.stableDevicePaths.devices. Both keys live under
        niri's own `debug` namespace, which niri's documentation explicitly excludes from its
        config breaking-change policy -- an upgrade can rename or remove either with no notice.
        This module ASSERTS nixniri.niri.package's version against the range it was verified
        against (see the `package` option); re-verify that range after every niri upgrade.
      '';

    xdg.configFile."niri/config.kdl".text = ''
      // Managed by home-manager (nixniri's home/niri.nix). Hand edits will be overwritten by
      // the next `home-manager switch` -- set options instead.

      input {
          keyboard {
              xkb {
                  layout "${cfg.keyboard.layout}"
                  ${lib.optionalString (cfg.keyboard.variant != "") ''variant "${cfg.keyboard.variant}"''}
              }
              numlock
          }

          touchpad {
              tap
              natural-scroll
          }
      }

      ${outputsSection}

      layout {
          gaps 16
          center-focused-column "never"

          preset-column-widths {
              ${presetWidthsSection}
          }

          default-column-width { proportion 0.5; }

          focus-ring {
              width 4
              active-color "#7fc8ff"
              inactive-color "#505050"
          }

          border {
              off
              width 4
              active-color "#ffc87f"
              inactive-color "#505050"
              urgent-color "#9b0000"
          }
      }

      ${lib.concatMapStringsSep "\n" (n: ''workspace "${toString n}"'') (lib.range 1 cfg.workspaceCount)}

      ${lib.concatStringsSep "\n" (neutralStartup ++ cfg.extraStartup)}

      // The polkit authentication agent, the org.freedesktop.secrets keyring, the cliphist
      // wl-paste watchers, and the idle/lock daemon run as systemd user services owned by
      // nixdesktop's home/session.nix, not as spawn-at-startup lines here -- this module
      // names none of those binaries. All it keeps is the lock KEY bind, whose target it
      // reads from nixdesktop's session policy.

      screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

      animations { }

      // Work around WezTerm's initial configure bug (niri-upstream default rule).
      window-rule {
          match app-id=r#"^org\.wezfurlong\.wezterm$"#
          default-column-width {}
      }

      // Open Firefox picture-in-picture as floating (niri-upstream default rule).
      window-rule {
          match app-id=r#"firefox$"# title="^Picture-in-Picture$"
          open-floating true
      }

      ${cfg.extraWindowRules}

      binds {
          ${bindsSection}

          ${cfg.extraBinds}
      }
      ${deviceDebugBlock}

      ${cfg.extraTopLevel}
    '';
  };
}
