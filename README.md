# nixniri

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

## Modules

| Module | Class | Owns |
|---|---|---|
| `homeManagerModules.niri` (= `.default`) | home-manager | `~/.config/niri/config.kdl` — input, layout, workspaces, binds, startup |

## The cross-repo contracts

This module reads two options from [nixdesktop][nixdesktop], both **defensively** — a host running
niri with no nixdesktop module in scope sees the fallback, never an evaluation error. Neither
requires a flake input on nixdesktop, and nothing needs hand-wiring:

| Read | Used for | Absent → |
|---|---|---|
| `nixdesktop.startup` | translated into `spawn-sh-at-startup` lines | empty list, nothing rendered |
| `nixdesktop.session.idleAndLock.lockCommand` | the Super+Alt+L lock bind | falls back to `swaylock` |

```nix
{
  imports = [
    inputs.nixniri.homeManagerModules.niri
    inputs.nixdesktop.homeManagerModules.session
  ];

  nixniri.niri = {
    enable = true;
    terminal = "kitty";
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

## License

MIT
