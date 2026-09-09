# winCoordinator

Home folder of the winCoordinator agent: the scheduled-task scripts, config
and logs, no code. win1, win2 and win3 run in `C:\data\fearlessBranch1..3`;
reach them with `ListAgents` + `SendMessage` (local sessions named win1,
win2, win3), or without spending tokens:
`scripts\send-to-session.ps1 -Name win3 -Message "..."`.

Coordination is the default job: status checks, relaying instructions, the
daily review. A request to look at something and fix it asks for this
session's own fresh judgment: do it directly in `C:\data\fearlessBranch4`
(same four-repo layout and `LocalResources.java` as the other branches;
align it first), and delegate only when asked to coordinate.

# Scheduler

`C:\data\startup\agent-supervisor.ps1`, launched once at logon by the
`ClaudeAgentSupervisor` scheduled task, starts all four agents and then
polls `config\scheduledTasks.txt` about once a minute for the rest of the
boot. Each line is plain text: `HH:MM, agentName, message` — one task per
line, every day, no one-shot support, no state file, no lateness
tracking. When a line's time matches, the bare `message` is sent as-is
into `agentName`'s pipe via `scripts\send-to-session.ps1`; if the machine
or the process was down at that exact minute, the line just doesn't fire
that day. A bare `scheduler_failed` message means the polling loop died
(missing `scheduledTasks.txt` or an unhandled error) and has stopped for
the rest of this boot — nothing else in that file will fire again until
the next logon unless fixed live. Never schedule daily work with the
in-session `CronCreate`. Any task that talks to an agent pipe must run at
RunLevel Highest, because the agents do.

# Daily machine-health review (05:45)

A bare `daily_review` message arriving here is the scheduler's 05:45
trigger — no person is typing, act on it autonomously with no
confirmation. Read `logs\diagnostic.log` since the last `[DAILY REVIEW]`
line — the hourly watchdog writes it, and `ATTENTION` lines are what it
noticed but did not act on — do whatever restores or preserves the
machine's health, autonomously, and append one `[DAILY REVIEW]` line
summarizing it.
