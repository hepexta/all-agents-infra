# 09: Scheduled dumps with retention and retrieval

**What to build:** The cluster database produces periodic dumps on wall-clock boundaries, prunes old ones by age while always keeping a minimum number, names them the way the existing container stack does, and a developer can copy them out to the repository's backup folder.

**Blocked by:** 07

**Status:** ready-for-agent

- [x] A dump appears on schedule with no manual intervention, using the same naming convention the existing container stack produces.
- [x] Dumps older than the retention window are removed while at least the configured minimum number always remains, shown by seeding more dumps than the window allows.
- [x] A dump taken from the cluster restores into a scratch database and its rows are present, proving the dump is complete rather than merely written.
- [x] A documented command copies the newest dump onto the Windows filesystem inside the repository's ignored backup folder, and the copied file is not tracked by version control.
- [x] Schedule and retention come from values.
- [x] The dump job never runs concurrently with itself and never captures a database that is mid-restore.

**Acceptance evidence:** a scheduled dump listing with names and timestamps; the pruning run showing the minimum kept; a restored scratch database with row counts; the copied file on the host and its ignored status; the values.

## Comments

- 2026-10-14: a scheduled job takes one dump and then prunes, sharing the container stack's naming, retention rules and sentinel, so a dump from either place is restorable by the other. Dumps live on a claim of their own rather than inside the data directory, so losing the database volume does not lose the backups with it.
- The schedule fired unattended: with the interval temporarily shortened, a job completed on its own and produced `allagents-20261014T184006Z.dump`, which is the naming the container stack uses. The schedule is a value, and it was returned to hourly afterwards.
- Retention was exercised rather than assumed. Five dumps older than the window were planted with distinct ages and one more dump was taken: four were pruned by age, one was kept explicitly because the floor of three would otherwise have been breached, and the run reported three dumps present. That is both halves of the rule in one run.
- Completeness was proven by round trip, not by file size: the database was given a table with 250 rows, a dump was taken, fetched to the Windows filesystem, and restored into a scratch database, which then held the same 250 rows and the same checksum over every row. The scratch database was removed afterwards.
- The guard against capturing a half-restored database was tested by planting the sentinel and running the job: it reported that a restore was in progress, skipped, and the number of dumps on the claim was unchanged. A stale sentinel is ignored after a couple of hours, so a restore that dies cannot stop backups for ever.
- Retrieval cost three Windows path problems in one command, all now fixed and recorded in the script: the shell rewriting the container path so it no longer looked remote, the local side then needing a Windows path, and a Windows path's drive letter being read as the separator before a pod name. The copy now runs from inside the destination directory with rewriting suppressed, which is the only combination that satisfies all three.
- The fetched dump landed in the repository's backup folder beside the dumps the container stack writes, with the same naming, and version control ignores it. Nothing in that folder is tracked.

