# Reichskommissariats Plus - RT56 Compatch - Agent Rules

Shared rules for every mod in this tree (file encodings, build commands, engine knowledge, git) are in the Modding Manager's `../../AGENTS.md`. `CLAUDE.md` and `GEMINI.md` import this file.

## What this mod is
- Reichskommissariats Plus - RT56 Compatch for Hearts of Iron IV.
- Standard single-root layout: `descriptor.mod`, `build.ps1`, content folders, `tests/`, `tools/`, `wiki/` at the root; `artifacts/` and `scratch/` are git-ignored.

## Out of scope
- New countries, focus trees, events or decisions.
- Balance changes: no new factories, resources or manpower beyond what the parent state had.

## Mod invariants
- Germany-side release gates use the scripted trigger `rkplus_ger_can_run_rks` (fascism or neutrality), never a bare `has_government = fascism`; the copied RK+ files get it from `tools/Update-RkPlusGovernmentGate.ps1`, which is re-run after every RK+ refresh [LOAD-010] [LOAD-019].
- Frozen RK+ files are never edited; changes go in this mod as same-path whole-file copies.
- RK+ names states by the game's numbers up to 1081 and Road to 56's above [RKP-001], and province ids do not line up between the two maps everywhere [RT56-010]. Every RK+ file the compatch ships because it names states is kept in `rkplus-source/` with the game's numbers and the compatch's own edits (the other RK+ files load from RK+ and are audited there); `tools/Update-RkPlusStateIds.ps1` generates the shipped file at the same path from it. Edit the source and regenerate, never the generated file. A state the map rule gets wrong goes into `tools/RkPlusRt56StateMapOverrides.json` with its reason.
- After an RK+ update, merge it into each source with the previous frozen copy as base, `git merge-file rkplus-source/<path> <old frozen>/<path> <new frozen>/<path>`, never by copying over (the sources carry compatch edits). Then run `Update-RkPlusGovernmentGate.ps1`, `Update-RkPlusStateMap.ps1`, `Update-RkPlusStateIds.ps1` and `Test-RkPlusStateReferences.ps1`, which must report 0 WRONG. An RK+ file it reports as WRONG and loaded from RK+ is copied into `rkplus-source/` (a decision, event or focus file is added to the target list in `tools/RkPlusStateReferences.psm1`; a country history file is picked up from its folder).

## Workflow
- The main agent implements the change and runs `build.ps1` and the tests itself.
- Before reporting it done, the main agent dispatches a fresh `reviewer` (`.claude/agents/reviewer.md`, Opus) with the task as the user asked it, the decisions the user made while planning, and the build and test summary lines, never its own verdict. A harness without Claude Code agents passes that file as the reviewer's brief.
- Every finding ends fixed or rebutted; a fix that grows beyond the finding goes back to the same reviewer through `SendMessage`, naming the finding ids it answers and the files it changed. The report to the user lists the findings and what became of each.

## Commands beyond build.ps1
- `tools/Update-RkPlusGovernmentGate.ps1 [-WhatIf]`: swaps the fascism gate for the shared trigger in the copied RK+ files, in the `rkplus-source/` copy where one exists.
- `tools/Update-RkPlusStateMap.ps1 [-WhatIf]`: writes `tools/RkPlusRt56StateMap.json`, the Road to 56 states of each of the game's states, from both maps and the overrides; needs the game and the RT56 standalone installed.
- `tools/Update-RkPlusStateIds.ps1 [-Detail] [-WhatIf]`: regenerates each target from `rkplus-source/` with that map: state ids, moved province ids, and a block with one-time effects (units, buildings, resources) kept in the one piece that holds its provinces; stops before writing when a reference has no conversion rule.
- `tools/Test-RkPlusStateReferences.ps1 [-Detail] [-PassThru]`: compares the land of every decision, event, focus and capital section RK+ loads with the frozen RK+ original on Road to 56's map; exit 1 on a WRONG section. `tests/StateReferences.Tests.ps1` runs it when the game and the mods are installed.

## Read when
| Task | Read |
|---|---|
| Publishing to the Workshop | `WORKSHOP_DESCRIPTION_GUIDELINES.md` |

## Engine Knowledge
- Engine facts live in the Modding Manager's register, reached through the user-level `hoi4-modding-knowledge` skill: search it before a new kind of file and before asking for a game launch, cite ids here, never write a fact into this repository.
- Topics this mod leans on: `encoding-and-syntax`, `loading-and-overrides`, `mods/rt56`, `mods/rkplus`.
- `tests/Knowledge.Tests.ps1` runs the register's audit for this repository; it is a copy the Manager keeps current.
