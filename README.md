# nixniri

> **DEPRECATED (2026-08-02).** niri is retired on every host that used to run it — the fleet
> moved to [nixscroll](https://github.com/julian-corbet/nixscroll-corbet-ch) (a sway/wlroots
> fork with the same scrolling/PaperWM layout model) fleet-wide after a head-to-head VRAM
> comparison found the two within noise of each other, closing the last reason to run two
> compositors across the estate. This repo still works and remains published (niri itself is a
> fine compositor), but it is no longer consumed by any host in production and should not be
> proposed for new work here — use nixscroll instead.

A declarative [niri](https://github.com/YaLTeR/niri) compositor config, as a single
home-manager module. It generates `~/.config/niri/config.kdl` — input, layout, workspaces,
keybinds, startup — from structured Nix options instead of hand-edited KDL,
and installs nothing.

## The split

`nixniri` was extracted out of [nixdesktop][nixdesktop], where this module originally lived as
`home/niri.nix`. nixdesktop still owns the platform-neutral **policy** layer (which desktop
roles — file manager, polkit agent, notification daemon, bar — a session wants filled, published
as `nixdesktop.want`) and the **session** layer (turning niri startup components into systemd
user services). This repo owns only the **niri compositor's own config file**: input devices,
layout, workspaces, keybinds, and startup.

Nothing here installs a package or names an absolute binary path. `niri` itself, and everything
this module's options point at by name (`terminal`, `launcher`, `osd`), is
supplied by whatever actually puts binaries on the box — a platform backend such as
[nixarch][nixarch] for Arch/CachyOS, or plain NixOS `environment.systemPackages` — never by this
module. Config generation and package resolution are different jobs on purpose: package names
and binary paths are not portable (`thunar` on Arch is `xfce.thunar` in nixpkgs; polkit agents
each live at a different path on every distro), so a module that hard-codes either only works on
the one platform it was written against.

**Mechanism public, values private.** Every default here is a sensible one for any user — niri's
own upstream example config (Mod+arrows, Mod+1-9, the standard media/volume/brightness keys), not
this author's personal setup. Nothing defaults to a specific hostname, monitor name, keyboard
layout, or key layout; a consumer who wants those sets the relevant option.

### Breaking change from nixdesktop's copy

The option namespace moved from `nixdesktop.niri.*` to **`nixniri.niri.*`** — matching this
family's own convention (`nixremote.forward`, `nixremote.sunshine`, `nixdesktop.session`: the
top-level attribute is always the repo's own name), not nixdesktop's, now that the module lives
in its own repo. This is a deliberate, un-shimmed breaking change, consistent with this family's
"no compatibility aliases" policy — a consumer migrating from nixdesktop's `home/niri.nix` needs
to rename every `nixdesktop.niri.*` reference (including inside `binds`/`extraStartup` overrides)
to `nixniri.niri.*`. Nothing else about the option surface changed in the move: every option,
default, and description is otherwise identical to nixdesktop's copy.

### Breaking change: `output` → `outputs` / `layout`

`nixniri.niri.output` — a single raw-KDL string interpolated once for every monitor on every
host — is **gone**, not deprecated. Nothing here could ever be asserted about it and no registry
could key on it: a host moving a monitor to a different machine got a block that silently stopped
applying, with no build-time signal anywhere. It is replaced by two structured, additive options:

| Option | Shape | For |
|---|---|---|
| `nixniri.niri.outputs.<name>` | attrset of typed fields (`mode`, `scale`, `position`, `transform`, `modeline`, `enable`) | hand-authored, per-host, keyed by connector name or identity triple — the manual/escape path |
| `nixniri.niri.layout` | a `nixdesktop.layouts.<name>` name | translated automatically from the shared monitor registry — portable between hosts, the main path on a host that composes nixdesktop |

Both render into the same generated `output {}` blocks; a consumer naming neither gets niri's own
auto-detection, exactly as `output = null` used to. A consumer migrating a hand-written `output`
string moves its fields into one `nixniri.niri.outputs."<connector-or-identity>"` entry.

## Modules

| Module | Class | Owns |
|---|---|---|
| `homeManagerModules.niri` (= `.default`) | home-manager | `~/.config/niri/config.kdl` — input, layout, workspaces, binds, startup |

## The cross-repo contracts

This module reads several options from [nixdesktop][nixdesktop] and [nixgpu][nixgpu], all
**defensively** — a host running niri with none of these composed sees the fallback for each,
never an evaluation error. None of them requires a flake input on nixdesktop or nixgpu (this
repo's only flake inputs are `nixpkgs` and `nixhost` — see below), and nothing needs hand-wiring:

| Read | Used for | Absent → |
|---|---|---|
| `nixdesktop.startup` | translated into `spawn-sh-at-startup` lines | empty list, nothing rendered |
| `nixdesktop.session.idleAndLock.lockCommand` | the Super+Alt+L lock bind | falls back to `swaylock` |
| `nixdesktop.layouts.<name>` (via `nixniri.niri.layout`) | translated into `output {}` blocks | build failure if named and unresolved; nothing rendered if never named |
| `nixdesktop.monitors.<name>` (via a layout's identity-matched entries) | the `"<make> <model> <serial>"` triple + alias fan-out | build failure if the layout needs it and it is unresolved |
| `nixdesktop.sessions.<name>` (via `nixniri.niri.session`) | `permittedDevices`/`deniedDevices` — device NAMES, not paths | build failure if named and unresolved; nothing rendered if never named |
| `nixgpu.stableDevicePaths.devices.<name>` (via `nixniri.niri.session`) | resolving each device NAME above to a stable `/dev/dri/by-path/*` PATH — see "Device restriction", below | build failure if a named device does not resolve to one; nothing rendered if `session` is never named |

```nix
{
  imports = [
    inputs.nixniri.homeManagerModules.niri
    inputs.nixdesktop.homeManagerModules.session
  ];

  nixniri.niri = {
    enable = true;
    terminal = "kitty";

    # THE MAIN PATH on a host that composes nixdesktop's monitor/layout registry — portable
    # between hosts because it is keyed by shared identity, not hand-copied EDID text.
    layout = "docked";

    # Device restriction, translated from nixdesktop.sessions.<name> down to real
    # /dev/dri/by-path/* paths via nixgpu.stableDevicePaths.devices — see below.
    # REQUIRES `package` the moment it is set (see "Device restriction").
    session = "primary";
    package = pkgs.niri;
  };

  nixdesktop.session = {
    enable = true;
    idleAndLock = {
      enable = true;
      lockAfterSeconds = 300;
      suspendAfterSeconds = 600;
      lockCommand = "swaylock";
    };
  };
}
```

### The `nixhost` flake input

This repo's only flake inputs are `nixpkgs` and [nixhost][nixhost]. `nixhost` is not a sibling
domain repo the way nixdesktop and nixgpu are — every read in the table above stays a *defensive*
read of live `config`, exactly as `nixdesktop.startup`/`nixdesktop.session.idleAndLock` always
were, needing no `imports` of nixdesktop or nixgpu and no flake input on either. What `nixhost`
supplies is `lib.probeFact`/`lib.collectProbes` (`lib/facts.nix`) — the one MECHANISM every read
above shares, and the fix for a defect class a bare `config.nixfoo.bar or fallback` cannot avoid:
it cannot tell "nixfoo is not composed on this host at all" (legitimate, silent) apart from
"nixfoo IS composed, but `bar` moved, was renamed, or was rejected by its own type" (a defect that
hides exactly as silently). `probeFact` tells the two apart, warns (or, for the `session`/`layout`
seams below, asserts) only on the second, and is closed over as a plain function argument in
`flake.nix` — a consumer importing `homeManagerModules.niri` sees an ordinary module function and
never needs to know `nixhost` exists.

### Device restriction — real paths, not names, and why

niri has no allowlist: it enumerates every DRM device on the seat unconditionally, so the only
lever is `debug { ignore-drm-device; render-drm-device; }` — a DENYLIST, the complement of
whatever `nixdesktop.sessions.<name>` permits, over the complete inventory nixgpu maintains. But
niri reads `config.kdl` straight off disk, with **no launcher step** in between: unlike scroll's
`WLR_DRM_DEVICES` (an environment variable a launcher can still resolve against live sysfs at
process-start time), a bare device NAME sitting in niri's own config file matches no live device
and enforces **nothing at all**, silently, while looking like a perfectly valid file. This module
therefore resolves each name to a stable `/dev/dri/by-path/*` PATH — via
`nixgpu.stableDevicePaths.devices.<name>.{cardPath,renderPath}` — at Nix EVAL time, and renders
only the resolved path. `renderPath` is preferred where the device has one; `cardPath` is the
correct (not merely a fallback) answer for one that never will (an evdi dock, an ASPEED/AST BMC
framebuffer) — verified against niri's own real device-resolution code, which accepts either node
type and looks up the sibling itself.

Both `debug` keys live in niri's own `debug` namespace, which niri's documentation explicitly
excludes from its config stability policy — a future niri release can rename or remove either
with no notice. That is why `nixniri.niri.session` **requires** `nixniri.niri.package` (the real
niri derivation this config will run under) the moment it is set: this module asserts
`package.version` against the niri release its `debug` translation was verified against, so an
incompatible niri upgrade fails the build instead of silently rendering a block niri no longer
understands — device restriction is a security boundary, and a boundary that fails open, quietly,
is not one.

### Idle and lock moved out, and why

This module used to own `idle.lockAfterSeconds`, `idle.suspendAfterSeconds` and `lockCommand`, and
computed a read-only `idle.command` — the whole assembled `swayidle` invocation — which the consumer
then had to wire into nixdesktop's `idleAndLock.command` by hand.

All of it now lives in nixdesktop. The original reasoning was that keeping the assembly in one place
beat duplicating it in nixdesktop, which was the right instinct about duplication and the wrong
choice of owner:

- **`swayidle` is not compositor-specific.** The invocation is byte-identical under niri, scroll, or
  any other wlroots compositor. Nothing in it needs to know which one is running.
- **Idle timeouts are policy.** "Lock after 30 minutes, never suspend" describes the *host*, not
  niri's config syntax — and policy is nixdesktop's entire remit.
- So owning the assembly per-compositor did not avoid duplication, it **guaranteed** it: one copy per
  compositor repo, free to drift. Owning it once in nixdesktop is what actually makes it one place.

> **This used to be your job, and it was a trap.** Earlier versions asked you to write the mapping
> yourself, on the stated grounds that a compositor module *cannot* read an option from a repo it
> does not depend on. That premise was simply wrong — a defensive read needs no dependency. The cost
> of believing it was a silent failure mode: forget the line and the component is fully configured,
> its files written, and it never launches, with no error possible, because a populated list with no
> reader is a valid configuration. `checks/startup-contract.nix` now asserts the splice in both
> directions, since `nix flake check` does not evaluate `homeManagerModules` and so never covered
> this at all.

`nixniri.niri.extraStartup` remains yours, for raw KDL startup lines this module does not generate.

What legitimately stays here is which **key** locks the screen, and what that key spawns. So this
module keeps the bind and reads the locker's name from the table above.

A consumer who only wants niri's config file — no bar, no notifier, no systemd session layer —
imports `homeManagerModules.niri` alone. The lock bind still works via the `swaylock` fallback;
there is simply no idle daemon running, which is the correct behaviour for that setup. To bind a
different locker standalone, redefine the bind through `binds` rather than reintroducing an option
that would be a second place to declare the same fact.

## Status

Early. Extracted from [nixdesktop][nixdesktop] as its own repo so a consumer who wants niri's
config but not nixdesktop's session/policy layers doesn't have to pull them in. The option
surface will move as niri itself does; there are no compatibility shims at this stage.

[nixdesktop]: https://github.com/julian-corbet/nixdesktop-corbet-ch
[nixarch]: https://github.com/julian-corbet/nixarch-corbet-ch
[nixgpu]: https://github.com/julian-corbet/nixgpu-corbet-ch
[nixhost]: https://github.com/julian-corbet/nixhost-corbet-ch

## License

MIT
