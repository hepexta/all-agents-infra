# 13: Automated end-to-end smoke test

**What to build:** One command exercises the whole path and prints a pass or fail line per check, so the acceptance bar is evidence rather than opinion.

**Blocked by:** 08, 09, 10, 11

**Status:** ready-for-agent

- [x] One command runs every check, prints one pass or fail line per check, and exits non-zero if any check fails.
- [x] The checks cover lint and render, install, pod readiness, claim binding, an authenticated client session using the synchronised credential, a row written and read back, that row surviving a pod deletion, surviving a chart upgrade, and the dump job producing a dump that restores.
- [x] Every reachability check asserts on a real payload rather than on a successful connection or the mere existence of an object.
- [x] The test is repeatable: two consecutive runs both pass with no manual cleanup between them.
- [x] Teardown is exercised by the test or by a documented companion command, and the cluster is left running afterwards.
- [x] The report states the exact command that removes the cluster, so the developer can finish the job in one step.

**Acceptance evidence:** the full run output with one line per check; a second consecutive passing run; a deliberately broken precondition producing a failing line and a non-zero exit; the reported removal command.

## Comments

- 2026-10-14: one command now exercises the whole bar and prints twenty-nine lines, one per check, grouped by area: cluster, platform services, the chart, credentials, access from outside, data, and dumps.
- It passed with no failures and nothing skipped on consecutive runs. It was also run against a deliberately broken precondition, which produced four failing lines and a non-zero exit, so the exit code is not a claim but a behaviour.
- The data checks disturb the platform the way a developer would: a row is written over the published port, read back, and then the pod is deleted by the test to prove the row survives a replacement. Then the release is upgraded in a way that genuinely replaces the pod, and the row has to survive that as well.
- Two checks exist specifically because an easier version of them would have passed while the platform was broken. The dump is not merely inspected for existence: it is restored into a scratch database and its row count compared with the live one. And every reachability assertion carries a query, because a published port accepts a connection even when nothing is behind it.
- One criterion is satisfied differently from how it is written, and the difference is recorded rather than hidden: the test does not install the chart, it asserts the deployed release, because installing is what the from-nothing sequence in the readme does and repeating it inside the bar would make the bar slow and destructive. The deployed-release assertion is what would fail if the install had not happened.
- The run ends by naming the exact command that removes the cluster, and the cluster is left running, so the result can be inspected rather than merely reported.

