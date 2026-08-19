# Wear OS Learnings

## Program Sync
Custom programs created on the phone are now synced to the watch.
The sync payload includes:
- `programJson`: The currently active program (if any).
- `allProgramsJson`: A list of ALL available programs (bundled + custom).

On the watch:
- `all_programs_json` is stored in `SharedPreferences`.
- `WatchWorkoutFlow` reads this list and displays `CUSTOM` and `BUILT-IN` sections.
- When a program is selected on the watch, it is persisted locally as `program_json`, allowing the watch to work offline.
