# Development, validation and troubleshooting

[Documentation home](../README.md) · [Repository instructions](../../AGENTS.md) · [Player README](../../README.md#development)

Start from the [architecture](architecture.md), use the [feature map](features.md) to find the owner, and consult the [complete module inventory](module-map.md) for load order. This guide summarizes the workflow; `AGENTS.md` and the executable scripts remain the detailed requirements.

## Working on a change

Read the owning module's callers, event listeners, storage and tests before editing it. Runtime code belongs in `Olympus/` or the relevant companion addon; a file is loaded only when its TOC names it. Shared namespace dependencies must respect load order and startup events.

Keep native observations, peer claims, saved preferences and transient UI state distinct. Recheck permissions in delayed callbacks, cancel work when its owner stops, and preserve existing bounds and client guards. New behavior should expose observable outcomes through the owning module, rather than asking tests to duplicate its implementation.

Every bug fix needs a regression that fails before the fix and passes afterward. When practical, prove this with the old source or a scratch copy with the fix removed. If a failure depends on the live client and cannot be reproduced offline, explain the limit and provide concrete in-game steps. Do not invent a client API in a mock to make the fix possible.

For native frames, menus, tooltips, chat, bindings or restricted calls, follow the [gamepad integration workflow](ui-and-gamepad.md) as part of the change, not as a later cleanup.

## Checks from the repository root

These commands use Bash and LuaJIT. The CI setup in [tests.yml](../../.github/workflows/tests.yml) is the reference for its Linux dependencies; some signing/artifact checks also need Python and their listed dependencies.

```sh
bash scripts/check.sh
```

This runs syntax and TOC checks, generated-content checks, global lint, the gamepad audit, offline scenarios and the other checks selected by the script. Read [check.sh](../../scripts/check.sh) for dependency-sensitive checks and failures. A filtered test run is not evidence that the full scenario suite ran.

Useful development commands:

```sh
luajit tests/run.lua
bash scripts/lint-globals.sh
OLYMPUS_TEST_FILTER='gamepad JOIN popup recovery' bash scripts/check.sh
```

The first two are also the repository's fallback when `check.sh` is unavailable. The filter is useful while reproducing a particular bug; remove it for the complete required run. An empty selection must not be reported as a pass of the intended scenarios.

| Test area | What to look for |
| --- | --- |
| [tests/run.lua](../../tests/run.lua) | Offline runner, fixtures and module scenarios |
| [tests/gamepad.lua](../../tests/gamepad.lua) | Native UI lifecycle, gamepad login and input-mode transitions |
| [tests/arena](../../tests/arena) | Game rules, domain protocols and result scenarios |
| [tests/fixtures](../../tests/fixtures) | Recorded/modelled client shapes and evidence used by tests |
| [scripts/gamepad-audit.lua](../../scripts/gamepad-audit.lua) | Registry, source tags and native UI access audit |

For documentation-only changes, validate linked paths, commands and claims against the current source. Check that new navigation works and the module inventory still matches all TOCs. Runtime tests need not be presented as newly run when only Markdown changed.

## Updating the Forever client model

The extracted Blizzard Interface source is not committed here. When the supported client changes, use that source to regenerate the fixture and verify registry pins:

```sh
luajit scripts/forever-api.lua "<Interface folder>"
luajit scripts/forever-pins.lua "<Interface folder>"
```

Replace the placeholder with the real extracted folder. Tests switch through the client's input style (`WithGamepadUI` and `GamepadStyle`); they must not replace `ns.GamepadUI` or `ns.Gate` to simulate success.

## Generated files and assets

`Olympus/AnswerBank.lua` is generated from [docs/answers.json](../answers.json) using `luajit scripts/answers.lua`. The repository also checks its generated store-page material and artwork through the scripts referenced by `check.sh`. Change the source input and regenerate when a file says it is generated.

`Olympus/TestBuild.lua` and shipped signed lists are package inputs/outputs, not normal committed source. Author signing material and player-bearing signed-list artifacts must not be added to this public repository.

## Packaging and release evidence

Run packaging from a clean, committed worktree after the relevant checks:

```sh
bash scripts/package.sh
bash scripts/package.sh --test 10
```

The number above is an example, not a claim that test 10 has been released. Choose an unused test number. [package.sh](../../scripts/package.sh) stages committed addon files, verifies the stage's TOCs, applies [bets-only.txt](../../scripts/bets-only.txt) and writes a ZIP, sorted file manifest and SHA-256 checksum under `dist/`. It rejects tracked changes and unexpected untracked/ignored files inside the addon folders.

A normal ZIP contains three addon folders. A test ZIP also contains generated build metadata and a modified main TOC in its stage; it does not edit the source tree. Optional signed lists and Olympus_Link packaging have explicit inputs and validation. Follow the script and root README for those workflows; do not copy a live SavedVariables directory into a package.

Treat these as separate pieces of evidence:

1. Source checks passed for a particular commit.
2. The ZIP contains the intended addon roots, TOC entries, version and build metadata.
3. The remote tag resolves to the intended commit.
4. The GitHub release is actually published, has the intended prerelease status, and offers the ZIP and checksum/manifest.
5. Downloaded assets match the locally verified digests.
6. The packaged addon was exercised in the live client.

One does not prove the next. A PR update is not a new release, and a successful offline run is not an in-game test. Use [BETA-TESTING.md](../BETA-TESTING.md) and the feature-specific acceptance guide for live checks.

## Troubleshooting and handoff

For a Blizzard blocked-action warning, open **Help → Report a bug** before reloading; `/oly bug` is also available with mouse and keyboard. Capture the refused function, build, input mode and reproduction steps. A normal reload/logout writes saved diagnostics. See [UI and diagnostics](ui-and-gamepad.md) for what is captured and its limits.

Performance capture is opt-in through `/oly perf on` and `/oly perf off`. Use measurements to support performance claims; reducing a polling interval's frequency is not, by itself, a measured FPS improvement.

A PR should lead with the player-visible problem and resulting behavior, then give the implementation boundary, relevant tests and remaining live checks. Spell out whether checks were filtered, skipped or incomplete. Link the engineering chapter and acceptance steps instead of burying the reader in internal field names.
