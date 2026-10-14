# 09: Scheduled dumps with retention and retrieval

**What to build:** The cluster database produces periodic dumps on wall-clock boundaries, prunes old ones by age while always keeping a minimum number, names them the way the existing container stack does, and a developer can copy them out to the repository's backup folder.

**Blocked by:** 07

**Status:** ready-for-agent

- [ ] A dump appears on schedule with no manual intervention, using the same naming convention the existing container stack produces.
- [ ] Dumps older than the retention window are removed while at least the configured minimum number always remains, shown by seeding more dumps than the window allows.
- [ ] A dump taken from the cluster restores into a scratch database and its rows are present, proving the dump is complete rather than merely written.
- [ ] A documented command copies the newest dump onto the Windows filesystem inside the repository's ignored backup folder, and the copied file is not tracked by version control.
- [ ] Schedule and retention come from values.
- [ ] The dump job never runs concurrently with itself and never captures a database that is mid-restore.

**Acceptance evidence:** a scheduled dump listing with names and timestamps; the pruning run showing the minimum kept; a restored scratch database with row counts; the copied file on the host and its ignored status; the values.
