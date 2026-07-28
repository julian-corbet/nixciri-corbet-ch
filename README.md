# nixniri

A declarative [niri](https://github.com/YaLTeR/niri) compositor config, as a single
home-manager module. It generates `~/.config/niri/config.kdl` — input, layout, workspaces,
keybinds, idle/lock timing, startup — from structured Nix options instead of hand-edited KDL,
and installs nothing.

## The split

`nixniri` was extracted out of [nixdesktop][nixdesktop], where this module originally lived as
`home/niri.nix`. nixdesktop still owns the platform-neutral **policy** layer (which desktop
roles — file manager, polkit agent, notification daemon, bar — a session wants filled, published
as `nixdesktop.want`) and the **session** layer (turning niri startup components into systemd
user services). This repo owns only the **niri compositor's own config file**: input devices,
layout, workspaces, keybinds, and the idle/lock timing niri itself needs to know about.

Nothing here installs a package or names an absolute binary path. `niri` itself, and everything
this module's options point at by name (`terminal`, `launcher`, `lockCommand`, `osd`), is
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
| `homeManagerModules.niri` (= `.default`) | home-manager | `~/.config/niri/config.kdl` — input, layout, workspaces, binds, idle/lock assembly, startup |

## The cross-repo contract: `idle.command`

The one real API surface this split creates: `nixniri.niri.idle.command` is a **read-only**,
computed option — the fully assembled `swayidle` invocation (timeouts, from
`idle.lockAfterSeconds`/`idle.suspendAfterSeconds`, plus `lockCommand`, already combined into one
shell command). niri itself has no way to restart a `spawn-at-startup` line when a running
session's config changes, so this module no longer spawns the idle daemon itself — it only
assembles the command string an idle daemon needs, once, in one place.

nixdesktop's `home/session.nix` runs that daemon as a systemd user service, via its own
`idleAndLock.command` option, which wants exactly that kind of finished command. **Neither repo
wires the two together implicitly anymore** — that used to be true when both lived in one file;
now that the split is a package boundary, not just a file boundary, the CONSUMER connects them
explicitly at their own top-level config, same as any other cross-flake option reference:

```nix
{
  imports = [
    inputs.nixniri.homeManagerModules.niri
    inputs.nixdesktop.homeManagerModules.session
  ];

  nixniri.niri = {
    enable = true;
    terminal = "kitty";
    idle.lockAfterSeconds = 300;
    idle.suspendAfterSeconds = 600;
    lockCommand = "swaylock";
  };

  nixdesktop.session = {
    enable = true;
    idleAndLock = {
      enable = true;
      # The wiring: nixniri assembles the command, nixdesktop's session layer runs it.
      command = config.nixniri.niri.idle.command;
    };
  };
}
```

A consumer who only wants niri's own config file — no bar, no notification daemon, no systemd
session layer — imports `nixniri.homeManagerModules.niri` alone and ignores `idle.command`
entirely; niri's own `lockCommand`-bound keybind still works without an idle daemon running.

## Status

Early. Extracted from [nixdesktop][nixdesktop] as its own repo so a consumer who wants niri's
config but not nixdesktop's session/policy layers doesn't have to pull them in. The option
surface will move as niri itself does; there are no compatibility shims at this stage.

[nixdesktop]: https://github.com/julian-corbet/nixdesktop-corbet-ch
[nixarch]: https://github.com/julian-corbet/nixarch-corbet-ch

## License

MIT
