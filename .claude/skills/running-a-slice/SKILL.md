---
name: running-a-slice
description: Use when starting a BiliFast slice from docs/flutter-move-spec.md section 6, when KaiC says "start slice N" or approves a slice plan, or before any milestone-sized feature work in BiliFast.
---

# Running a slice

KaiC's words: efficiency and speed. Every build and every check is done by parallel agents. Claude plans, writes the
shared pieces, merges and ships. Building a slice alone in the main session is the failure this skill prevents
(slice 3 was built solo and had to be redone this way).

## 1. Plan: KaiC's only stop

Read the spec's section 0 and the slice's entry, `docs/reference/app-inventory.md` for the Swift paths (open the
Swift only where the plan needs a detail), PiliPlus through `docs/reference/piliplus-map.md` where the spec says it
helps (GPL: read only), the slice's items in `D:\Repos\Apps\BiliNative\docs\m2-phone-checklist.md`, and for
anything on screen the official app's screenshots in `local/official-app-reference/` (iPhone 17 Pro Max at 3×: 440×956
pt portrait, 956×440 landscape). KaiC wants the layout identical to them; they win over the Swift app. `local/` is
gitignored: never copy, commit or embed them. Show one screen:

1. **Done:** the numbered phone test steps.
2. **Shared pieces** Claude commits first (step 2).
3. **Agent table:** agent | builds | owns (files) | tests. No file appears in two rows.
4. **Rounds:** only where this slice differs from steps 3-7 (for example, no Windows run when Windows can't show it).
5. **Only the phone can prove:** what KaiC should watch for.
6. **Decisions for KaiC:** anything only he can settle (a spec rule that clashes with CLAUDE.md, a product choice),
   each with your recommendation. He answers them with the go.
7. **Build number:** the next one (the last shipped, from the status section or the last run, plus one).

Size the table by files, not features: one agent per set of files that can change without the others. A file every
piece needs (such as `playback_controller.dart`) gets one owner; the others build against its new signatures, stubbed
in the contracts commit. Up to about 8 builders.

Wait for his go. After it, run straight through to TestFlight; ask him only for a decision that is truly his.

## 2. Shared pieces (the contracts commit)

Before any agent starts, commit on main: interfaces and signatures, route arguments, theme tokens, stubs of new
files, pubspec changes, and anything two agents would both touch. That includes:
- the `project.pbxproj` entries for every new Swift file (agents never edit pbxproj);
- Pigeon definitions with their generated Dart and Swift;
- `Info.plist` keys (load the ios-testflight skill first);
- `AppDelegate.swift` registrations.

Analyze and tests green. Every brief names this commit.

## 3. Build round

All builders in ONE message: `isolation: "worktree"`, background, one agent per independent piece (as many as there
are pieces). Each brief contains, in order:

1. First command: `git log --oneline -1`; if it isn't the contracts commit, `git merge --ff-only <id>`. Worktrees
   start on an old commit.
2. Read CLAUDE.md. Rules: public repo, no secrets in code or logs, tests never touch the network, theme tokens only,
   PiliPlus read only, Flutter through `fvm`.
3. The job, with its Swift and PiliPlus references, and for UI the reference screenshots it must match (by file
   name), measured in pt (px/3).
4. **Your files:** the full list; edit nothing else, and report needs outside it. For a shared file such as
   `theme.dart`, name the exact spot to insert.
5. Never `dart format` a whole file that wasn't formatted before; it rewraps everything.
6. **Done:** committed on the branch, analyze clean, the whole suite green, a test per behaviour, `swiftc -parse` for
   Swift.
7. **Report** under 600 words: branch, commits, the change per item, tests, what's not done, needs outside its files,
   every Swift change listed exactly.

## 4. Merge

Merge each branch as it finishes (`git merge --no-edit <branch>`); don't wait for all of them. Apply the agents'
"needs outside my files", then analyze and run the whole suite.

## 5. Check round

All in ONE message, background, read only. Each prompt gives the diff range and the area, and asks for verified
findings only (file:line, severity, scenario, fix) under a word cap. Leave out a checker with nothing to check in this
slice.

- Code review: the player and lifecycle side.
- Code review: UI against the Swift app and KaiC's taste.
- Silent failures, including secrets in logs.
- Test gaps, with sketch tests run against the code.
- Spec and phone checklist.
- Comments against KaiC's comment style.
- Look-alike check, for every screen the slice touches: render ours at the phone's size and safe areas (a widget test
  at 440×956 or 956×440, 3×, MiSans loaded, fake data, PNGs to the scratchpad, never committed) and compare each with
  its reference screenshot. A verdict per screen: PASS when the layout matches (positions, sizes, icons, colours,
  fonts, text; the video frame itself differs), FAIL with every difference listed.
- Swift review of every Swift change (only when Swift changed).
- Windows run, as a general agent bound by the ghosthand rules:
  - load the ghosthand skill first; no other screen tool; never `keys` with allow_focus;
  - always `--mute`; at most 3 live video opens; nothing on the clipboard (use `--play=` for links);
  - screenshots to the scratchpad; measure idle CPU;
  - every button and control the slice added or touched is operated and its effect confirmed from a fresh
    screenshot or read, reported as a table (control | worked | evidence). Nothing ships untested (KaiC): a control
    that fails is a finding, and one ghosthand can't reach is listed with why.

## 6. Fix round

Group the findings by file. Run one fix agent per group in worktrees, with the same brief (and a contracts commit if
fixers share anything). Merge each as it lands. Run the look-alike check again on every screen that failed; repeat
until each passes, or report the screens still failing and why.

Then, in parallel, run:
- a final seam review of how the merged branches fit;
- a Swift review of the final Swift;
- a second Windows run.

Fix small findings directly.

## 7. Ship

1. Add the CLAUDE.md status entry, and update the layout section for any new folders.
2. Run `python scripts/gate.py` on the committed tree.
3. Push main, then `python scripts/testflight.py start`.
4. Check once: a background `sleep 660 && python scripts/testflight.py status`. No polling, no watching.
5. Start `uv run tools/logserver.py` in the background unless it's already running (`NonUniqueNameException` means it
   is).
6. Report: the build number, what changed, how it works, the numbered phone steps from the plan, and what to watch.

## Common mistakes

| Mistake | Fix |
|---|---|
| Building a piece yourself "because it's small" | Small pieces still go to agents; you only write the shared pieces and post-merge fixes |
| Launching a round across several messages | One message per round |
| Two agents editing one file | Move it into the contracts commit or give it one owner |
| An agent working on an old base | The ff-only line opens every brief |
| Waiting for every agent before merging | Merge each as it lands |
| Extra GitHub runs to check something | Gate locally; one run per round |
| Asking KaiC between rounds | He approves the plan; then run through |
