# UI, input and blocked-action diagnostics

[Documentation home](../README.md) · [Development guide](development.md)

Olympus renders its own windows and also integrates with parts of Blizzard's UI. Those are different responsibilities. Rendering a permitted Olympus window does not make it safe to focus native chat, attach a button to a game frame or call a restricted function.

## Rendering and feature ownership

[UI.lua](../../Olympus/UI.lua) owns the main window, layout and tab routing. [Views.lua](../../Olympus/Views.lua) renders structured rows and detail content supplied by feature modules. Features provide text, right-side values, buttons and callbacks; the renderer should not become a second implementation of census, recruiting or moderation rules.

Window construction is lazy. The main UI supports its existing visual modes, and feature modules can register additional tabs. [ChurchView.lua](../../Olympus/ChurchView.lua) and [ArenaHome.lua](../../Olympus/ArenaHome.lua) illustrate feature-owned entry points. The heavier Arena screens live in the separate load-on-demand addon; the normal player card and profile editor live in the main addon.

[Dialog.lua](../../Olympus/Dialog.lua) presents Olympus-owned dialogs. Some specifications use the `StaticPopupDialogs` table as a definition book, but that does not mean every dialog is shown through the game's native popup implementation. Follow the facade and its gamepad policy when changing a dialog.

## Native UI integration gate

[GamepadRegistry.lua](../../Olympus/GamepadRegistry.lua) inventories integrations. [Gamepad.lua](../../Olympus/Gamepad.lua) evaluates policy and manages transitions. An integration's registry entry explains what the game does with the touched surface and what must happen on a gamepad login and on switching input modes.

The gate is separate from feature authorization. A player can have guild invitation rights while the current UI mode still forbids the addon's native chat path.

For a new or changed native integration, follow [AGENTS.md](../../AGENTS.md):

1. Register or extend an integration ID and its lifecycle policy.
2. Tag each native touch with `-- gp:<id>`; use `!hook` and `!undo` only for their specified roles.
3. Call `ns.Gate.Allowed("<id>")` before the first native touch and at the start of callbacks handed to the game.
4. If the integration leaves hooks, controls or state behind, register `install`, `park` and `leftover` behavior with `ns.Gate.Hooks`.
5. Cover gamepad login and both transitions in `tests/gamepad.lua`, naming the entry with `GP.Covers`.
6. Run `bash scripts/check.sh` and resolve audit failures.

An unregistered integration is not implicitly allowed. The lifecycle also matters: returning from a callback today does not remove a hook or frame installed yesterday. Restoration is constrained by combat and client state; some residual taint requires a reload. Do not bypass the gate to make an offline test green.

## Focus and recruiting

The shared focus and dialog helpers centralize input handling. Automatic recruiting prompts display the command without focusing its edit box. This is what prevents movement keys from becoming command text. Focus and native chat opening occur only after a deliberate player action and the appropriate gate check.

On an input-mode switch, native-chat work and paste watchers must stop or park as their policy requires. Read [the recruiting chapter](recruiting.md) for the distinction between a visible draft, a prepared command and a confirmed guild join.

## Error and blocked-action reports

[Bootstrap.lua](../../Olympus/Bootstrap.lua) captures early load failures where permitted. [Diagnostics.lua](../../Olympus/Diagnostics.lua) collects runtime diagnostic context, including blocked/forbidden actions attributed to exact Olympus module names.

The blocked-action record retains up to ten distinct calls. Each has a count, module/client/build identification and first/latest sampled context. Stack/probe capture is limited to the first occurrence of that call in a session. A small ring contains eight fixed UI action labels. Repeated warnings update counts and sampled context without doing a full stack capture each time.

The new UI breadcrumbs do not record pressed keys, invitation command text or invitee names. This is not a statement that every older diagnostic field is anonymous; review the full report before sharing it. Reports are not automatically uploaded.

When Blizzard disables an action, open **Help → Report a bug** before reloading, or use `/oly bug` with mouse and keyboard. A normal reload/logout persists `OlympusDB.actionsBlocked`. The report can identify the refused function and surrounding UI state; collecting it does not by itself fix or prove the origin of the taint.

[Perf.lua](../../Olympus/Perf.lua) supplies opt-in performance measurements. [SelfTest.lua](../../Olympus/SelfTest.lua) contains author-only test-build checks. Neither should be described as a live test having run merely because its code is installed.

## Client model and limits

The gamepad pass models the supported Forever client using [forever-api.lua](../../tests/fixtures/forever-api.lua). Globals, widget members, events and templates must exist in that fixture and have source provenance. The registry also pins the source behaviors its policies depend on.

When the client changes, regenerate and check against the extracted Interface source using the commands in [development](development.md). Do not add a convenient mock API without verifying that the supported client actually provides it. The model establishes repeatable integration checks; live controller navigation, native chat behavior and interaction with other installed addons still need observation in game.
