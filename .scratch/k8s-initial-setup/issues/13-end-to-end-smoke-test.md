# 13: Automated end-to-end smoke test

**What to build:** One command exercises the whole path and prints a pass or fail line per check, so the acceptance bar is evidence rather than opinion.

**Blocked by:** 08, 09, 10, 11

**Status:** ready-for-agent

- [ ] One command runs every check, prints one pass or fail line per check, and exits non-zero if any check fails.
- [ ] The checks cover lint and render, install, pod readiness, claim binding, an authenticated client session using the synchronised credential, a row written and read back, that row surviving a pod deletion, surviving a chart upgrade, and the dump job producing a dump that restores.
- [ ] Every reachability check asserts on a real payload rather than on a successful connection or the mere existence of an object.
- [ ] The test is repeatable: two consecutive runs both pass with no manual cleanup between them.
- [ ] Teardown is exercised by the test or by a documented companion command, and the cluster is left running afterwards.
- [ ] The report states the exact command that removes the cluster, so the developer can finish the job in one step.

**Acceptance evidence:** the full run output with one line per check; a second consecutive passing run; a deliberately broken precondition producing a failing line and a non-zero exit; the reported removal command.
