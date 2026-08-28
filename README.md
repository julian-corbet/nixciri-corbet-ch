# nixciri

Declarative Ciri compositor integration for Home Manager.

`nixciri` generates `~/.config/ciri/config.kdl` from structured Nix options. It
translates neutral display, session-device, and startup contracts into Ciri's KDL
grammar while keeping personal desktop choices outside the public module.

## Boundary

The compositor stack has three layers:

| Layer | Owner | Contains |
|---|---|---|
| Runtime | `ciri` | compositor source, renderer and protocol fixes, CLI and runtime identity |
| Public integration | `nixciri` | config serialization and translation of neutral contracts |
| Private values | `ciri.nix` | selected layout, bindings, colors, gaps, rules and host overrides |

This repository intentionally ships no keyboard choice, workspace count,
bindings, colors, application rules, bar, launcher, OSD, locker, or polkit
agent. It also installs no package. A platform backend supplies the Ciri runtime
and passes that derivation through `programs.ciri.package` when version-sensitive
device restriction is enabled.

## Module

| Export | Namespace | Output |
|---|---|---|
| `homeManagerModules.ciri` (`.default`) | `programs.ciri.*` | `~/.config/ciri/config.kdl` |

There are no compatibility aliases. The public API is Ciri-only.

```nix
{
  imports = [ inputs.nixciri.homeManagerModules.ciri ];

  programs.ciri = {
    enable = true;
    layout = "docked";
    session = "primary";
    package = ciriPackage;

    binds."Mod+Return" = {
      action = ''spawn "my-terminal"'';
      hotkeyOverlayTitle = "Open a terminal";
    };
  };
}
```

## Neutral contracts

The module reads sibling options defensively. None of the domain owners below is
a flake input.

| Contract | Ciri translation | If not selected |
|---|---|---|
| `nixdesktop.startup` | `spawn-sh-at-startup` lines | nothing rendered |
| `nixdisplay.layouts.<name>` | typed `output {}` blocks | Ciri auto-detection |
| `nixdisplay.monitors.<name>` | identity and alias match blocks | only needed by identity layouts |
| `nixdesktop.sessions.<name>` | primary render device and denylist | no device restriction |
| `nixgpu.stableDevicePaths.devices` | stable `/dev/dri/by-path/*` values | only needed by a selected session |

Naming a layout, session, monitor, or device that cannot be resolved fails
evaluation. A missing sibling namespace is otherwise a silent and valid state.

### Output translation

`programs.ciri.outputs` is the manual, host-specific escape path.
`programs.ciri.layout` is the portable path: it names a neutral
`nixdisplay.layouts` entry and expands monitor identities and aliases into Ciri
output blocks. Counter-clockwise transforms pass through unchanged. Modeline
sync flags are quoted for KDL while their timing fields remain unchanged.

### Device restriction

Ciri's inherited backend currently expresses device selection through the
unstable `debug` keys `render-drm-device` and `ignore-drm-device`. The module
resolves neutral device names to stable paths before writing the config. Setting
`programs.ciri.session` therefore also requires `programs.ciri.package`; the
package version is checked rather than trusting a security boundary silently.

## Raw escape hatches

Structured outputs and binds cover the validated surface. The following options
carry Ciri KDL verbatim for private choices or new upstream syntax:

- `extraOutputs`
- `extraStartup`
- `extraWindowRules`
- `extraBinds`
- `extraTopLevel`

## Validation

The flake checks:

- evaluate the Home Manager module instead of merely listing it;
- test startup translation in both composed and standalone states;
- test output, layout, monitor-alias, transform and device-path translation;
- feed a broad rendered fixture to the upstream grammar validator inherited by
  the current Ciri source line;
- reject retired public names in the repository source.

Run the full suite on the configured build service:

```console
nix flake check --all-systems
```

## Status

Source-preparation only. Ciri is not activated by this repository, and the live
compositor remains unchanged. Runtime package resolution, compositor registration,
portal/session integration, and validation against the final Ciri binary are the
next integration steps once the runtime product is published.

## License

MIT
