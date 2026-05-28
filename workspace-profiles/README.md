# Workspace Profiles

A [Noctalia](https://noctalia.dev) plugin for managing [niri](https://github.com/YaLTeR/niri)
workspaces as **profiles**, from a UI in the bar.

> Note: the id is `workspace-profiles` (not `niri-workspaces`, which is a different,
> official plugin in the noctalia-plugins repo).

## What it does

A **profile** maps to a workspace **position** (its 1-based place in the list — so
the 1st profile is workspace 1, the 2nd is workspace 2, matching `Mod+1`, `Mod+2`, …).
Each profile has:

- a list of **pinned apps**
- **On all screens** — the profile spans every monitor (required for linking)
- **Linked** — switching to it switches all monitors at once (only with *On all screens*)
- a **Monitor** — which output the ▶ switch targets (single-screen profiles)

**niri's hard rule:** workspace names must be unique — the same name can't exist on
two monitors (verified with `niri validate`). So the plugin is **position/index-based**
and imposes **no names** on niri workspaces (no ugly `·monitor` suffix). It does **not**
edit your niri config at all. The profile name is shown in the bar for the current
workspace position.

### How features map to niri (all live, via `niri msg`)

| Profile setting        | Mechanism |
|------------------------|-----------|
| ▶ switch / activate    | `focus-monitor` + `focus-workspace <index>` (single or all monitors) |
| Pinned apps            | new windows are moved to the profile's index via `move-window-to-workspace --window-id … --reference <index>` |
| Linked                 | engine watches the focused monitor's active workspace **index**; when it lands on a linked profile's position (by any means — bar pills, keybinds, ▶), every other monitor follows to that index (brief focus flicker) |

## Install (local / development)

1. This folder lives at `~/.config/noctalia/plugins/workspace-profiles/`.
2. Enable it in **Settings → Plugins → Installed**, or set
   `"workspace-profiles": { "enabled": true }` in `~/.config/noctalia/plugins.json`.
3. Add the **Workspace Profiles** widget to your bar (Settings → Bar).
4. Restart the shell to pick up code changes:
   `systemctl --user restart noctalia-shell.service`.

No niri config changes are required — the plugin drives everything live over `niri msg`.

## IPC

Toggle the panel from a niri keybind:

```kdl
Mod+Shift+Backslash { spawn-sh "qs -c noctalia-shell ipc call plugin:workspace-profiles toggle"; }
```

## Settings

- **Linked switching** — master on/off for the cross-monitor sync engine
- **Open pinned apps silently** — don't move focus to a launched pinned app
- **Pairing debounce (ms)** — guard window for the sync engine
- **Show profile name in bar**

## Status

v0.1.0 — first working version. Known follow-ups: unit tests for the KDL generator,
splitting the panel into smaller components, live refresh of the running-apps list.
