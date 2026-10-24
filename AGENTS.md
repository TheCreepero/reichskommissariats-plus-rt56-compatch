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

## Workflow
- The main agent implements the change and runs `build.ps1` and the tests itself.
- Before reporting it done, the main agent dispatches a fresh `reviewer` (`.claude/agents/reviewer.md`, Opus) with the task as the user asked it and the build and test summary lines, never its own verdict. A harness without Claude Code agents passes that file as the reviewer's brief.
- Every finding ends fixed or rebutted; a fix that grows beyond the finding goes back to the same reviewer through `SendMessage`. The report to the user lists the findings and what became of each.

## Commands beyond build.ps1
- `tools/Update-RkPlusGovernmentGate.ps1 [-WhatIf]`: swaps the fascism gate for the shared trigger in the copied RK+ files.

## Read when
| Task | Read |
|---|---|
| Publishing to the Workshop | `WORKSHOP_DESCRIPTION_GUIDELINES.md` |

## Engine Knowledge
- Engine facts live in the Modding Manager's register, reached through the user-level `hoi4-modding-knowledge` skill: search it before a new kind of file and before asking for a game launch, cite ids here, never write a fact into this repository.
- Topics this mod leans on: `encoding-and-syntax`, `loading-and-overrides`.
- `tests/Knowledge.Tests.ps1` runs the register's audit for this repository; it is a copy the Manager keeps current.
