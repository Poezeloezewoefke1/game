# Release checklist

Nothing here is optional, and nothing here may be ticked on the basis that it
"should" work. A box is ticked when someone has seen the evidence.

## 1. Code and tests

- [ ] `tools/check_structure.sh` passes.
- [ ] `godot --headless --path . res://tests/test_runner.tscn` exits 0, and the
      summary line is pasted into the release notes.
- [ ] `tools/run_multiplayer_check.sh <godot> 7700 3` exits 0, and its
      `RESULT: PASS` line is pasted into the release notes.
- [ ] No `SCRIPT ERROR`, `Parse Error` or `Compile Error` in the import log.
- [ ] No new engine `ERROR:` lines in the multiplayer check logs. (This is how
      four separate real defects were caught; a new one is a regression, not
      noise.)

## 2. Documentation is true

- [ ] `docs/QA_REPORT.md` reflects **this** commit: what was run, what was not.
- [ ] `docs/KNOWN_LIMITATIONS.md` lists every unverified behaviour.
- [ ] `docs/REQUIREMENTS_TRACEABILITY.md` has no requirement left at
      *Not implemented*, and every `AUTO`/`NET` status is backed by a test that
      currently passes.
- [ ] `CHANGELOG.md` has an entry for this version.
- [ ] `README.md`'s status table matches reality.

## 3. Protocol and versioning

- [ ] `GameConfig.PROTOCOL_VERSION` incremented if any RPC signature, the
      mission snapshot shape, or the replicated node path changed.
- [ ] `GameConfig.GAME_VERSION` and `project.godot`'s `config/version` agree.
- [ ] The engine version pin is identical in both workflows and in
      `docs/TECH_STACK.md`.

## 4. Build

- [ ] The Windows release export completes with exit code 0.
- [ ] The output is a `PE32+ executable (GUI) x86-64`.
- [ ] Both `StarboundStation.exe` and `StarboundStation.pck` are present.
- [ ] The pack contains no harness code (`NETCHECK` search is clean).
- [ ] The CI artifact contains the **whole folder**, not just the executable.

## 5. Runtime verification — currently BLOCKED

None of this has been done. Until it has, the honest description of a build is
"validated headlessly", not "release-ready".

- [ ] The exported executable launches on Windows 10 or 11 x64.
- [ ] The main menu renders and accepts input.
- [ ] Hosting works from the exported build.
- [ ] A second exported build joins over `127.0.0.1`.
- [ ] Two **physical machines** complete a mission over a LAN.
- [ ] A full mission is completed to victory in the exported build.
- [ ] A mission is failed and retried in the exported build.
- [ ] Killing the host leaves clients with a readable message, not a hang.
- [ ] Audio cues are audible and distinguishable.
- [ ] Frame time is acceptable with four players and the Sentinel active.
- [ ] The manual pass in `docs/TEST_CHECKLIST.md` has been worked through.

## 6. Release

- [ ] Merge to `main` via pull request, with the PR template completed
      truthfully — including the "tests NOT run" section.
- [ ] Tag `vX.Y.Z`.
- [ ] Confirm the tag-triggered Windows build succeeded.
- [ ] Attach the artifact to the release, with the known-limitations list in the
      release notes.

## The claim you are allowed to make

If sections 1-4 pass and section 5 has not been done, the accurate statement is:

> Validated headlessly on Godot 4.5.1-stable: every script compiles, every scene
> instantiates, 533 automated assertions pass, a full mission completes against
> a real host session, and a 4-player session plus hostile-client probes pass
> across real OS processes. The Windows build exports to a valid executable that
> has never been launched. Runtime behaviour on Windows and on a physical LAN is
> unverified.

That is not the same as "release-ready", and it should not be described as such.
