This Windows machine (LAPTOP-UNAIQSPV) is dedicated to Claude: always on,
remote-controlled, nobody at the keyboard. Four always-on agents run here,
each in its own folder: win1 in `C:\data\fearlessBranch1`, win2 in
`fearlessBranch2`, win3 in `fearlessBranch3`, winCoordinator in
`C:\data\winCoordinator` (with `C:\data\fearlessBranch4` as its own working
copy). Marco (marco.servetto@gmail.com) is the human; that address only
identifies him — never author or push as him.

# No history, ever

Skills, CLAUDE.md files, memory, code comments, scripts: describe the
current state and the current rules only. Never write what something used
to be, what changed and when, what a past session did or got wrong, dates of
events, or comparisons with other machines. A reference to a past state is
a bug — delete it, don't reword it. Rationale, when needed, is a timeless
present-tense constraint ("jars aren't byte-reproducible"), never a story.

# Scripts

Building, testing and packaging Fearless is done only by the Java programs
in `Coordinator/test/mainCoordinator/` (see "Fearless" below). The only
non-Java scripts on this machine are `check-claude-usage`'s
`check_usage.ps1` and the scheduled-task machinery in
`C:\data\winCoordinator\scripts` and `C:\data\startup`. Never add a
`.ps1`/`.py`/`.cmd` wrapper for anything else: write the commands in the
skill or CLAUDE.md and run them directly.

# Accounts

- Email: marcoautomation2@outlook.com
- GitHub: https://github.com/marcoautomation2

These are yours: commit, push, open issues and PRs as this identity without
asking. Password, token and 2FA live in the `git-usage` skill, which also
says where PRs go: the upstream parent org (FearlessLang, MarcoServetto),
never the marcoautomation2 fork. Before closing any PR, comment why.
`marcoautomation2` actions on GitHub come from any of the four agents,
never from a human — check the timeline before attributing anything.

# Publishing

Never publish or update anything on the shared-docs site's releases or
download page unless explicitly asked to publish, deploy or release.
Fixing a bug or merging a PR is not a reason to deploy.

# MarcoLeftovers

`C:\Users\sonta\Desktop\MarcoLeftovers` holds Marco's own files. Never read,
move, modify or delete anything in it, elevated or not. Everything else on
the machine is fair game; prefer `C:\data` (short paths, no spaces).

# Elevation

Every agent session runs elevated (the logon tasks are RunLevel Highest).
Install, uninstall, write HKLM and Program Files, manage services, register
tasks — directly, without asking. Anything writing to an agent's
`\\.\pipe\LOCAL\cc-msg-*` pipe must itself run at high integrity.

# Scheduled tasks and messaging

Windows Task Scheduler, never the in-session `CronCreate`:
- `ClaudeAgentSupervisor` (at logon, RunLevel Highest, no time limit) runs
  `C:\data\startup\agent-supervisor.ps1`: waits for the network, then
  launches all four agents — one detached `claude --remote-control <name>
  -n <name>` per agent, each in its own working folder. Each launch is a
  single fire-and-forget process start: if an agent's `claude` later exits
  or crashes, nothing relaunches it until the next logon. Autologon
  (`Autologon64.exe`, LSA secret) makes the logon trigger fire. The same
  script then polls `C:\data\winCoordinator\config\scheduledTasks.txt`
  about once a minute for the rest of the boot: plain `HH:MM, agentName,
  message` lines, one per day, no one-shot entries. When a line's time
  matches, the bare `message` is delivered as-is (no wrapping text) into
  `agentName`'s pipe via `scripts\send-to-session.ps1` — the recipient's
  own CLAUDE.md must document what that message means and that it's an
  autonomous scheduled trigger needing no confirmation. There is no
  lateness tracking: if the machine was asleep or the process was down
  when a line's time hit, that line just doesn't fire that day. If
  `scheduledTasks.txt` goes missing, or the polling loop hits an
  unhandled error, the script sends `winCoordinator` the bare message
  `scheduler_failed` and stops polling for the rest of this boot.
- `ClaudeCleanupWatchdog` runs `cleanup-watchdog.ps1` hourly: kills any
  process not in `scripts\process-whitelist.txt` alive for more than 1 hour
  (add the process name there, no `.exe`, before a build that may run
  long); clears stale `.git\index.lock` files; prunes stale Claude build
  binaries, spilled tool results, Temp, the recycle bin, `claude.exe.old.*`
  backups, and gitignored Fearless output untouched for 7 days (`out`,
  `.out`, `dbgOut`, `gen_java_base`, `fearlessArtefact`,
  `fearlessManagedArtefact`, `.fearless_out`) in every `fearlessBranch*`;
  moves Downloads untouched for 7 days into MarcoLeftovers. It appends to
  `C:\data\winCoordinator\logs\diagnostic.log`; `ATTENTION` lines are for
  the daily review.

To message a live agent without spending tokens:
`C:\data\winCoordinator\scripts\send-to-session.ps1 -Name win2 -Message "..."`
(needs `crossSessionInbound: accept` in `~\.claude\settings.json`, set).

# Finding files

Never run a recursive search from `/`, `C:\` or `/c`: it runs for an hour
and the watchdog kills it. Content roots:
- `C:\data\fearlessBranch1..4` — the Fearless working copies (win1, win2,
  win3, winCoordinator).
- `C:\data\tools` — Eclipse, and the `shared-docs` checkout.
- `C:\data\winCoordinator` — scripts, config, logs.
- `C:\data\startup` — the agent launch chain.
- `C:\Users\sonta\.claude` — skills, settings, memory.
Anything else: ask, or search one subtree with `-maxdepth`.

# Opening programs

GUI apps: `Start-Process <exe> -ArgumentList <args>` (never `-Wait`).
Console-bound commands (a REPL, `ssh`, a prompt reading stdin):
`Start-Process powershell.exe -ArgumentList '-NoExit','-Command','<cmd>'`,
or hand them to Marco as `! <cmd>`. Notepad++ is at
`C:\Program Files\Notepad++`; `notepad.exe` is the fallback.

# Fearless

Seven sibling repos per working copy, each with `origin` = the
marcoautomation2 fork and `upstream` = the parent org: `FearlessLang/<name>`
for Commons, Frontend, Coordinator, StandardLibrary, EclipsePlugin;
`MarcoServetto/<name>` for ZeroToHero, FearlessTour. Never commit a
CLAUDE.md or any Claude-local config into them.

At the start of new work in a `fearlessBranch*` folder, reset all seven to
upstream — the folder is scratch, local commits are disposable:
```powershell
foreach ($r in 'Commons','Frontend','Coordinator','StandardLibrary','EclipsePlugin','ZeroToHero','FearlessTour'){ git -C $r fetch upstream main --quiet; git -C $r reset --hard upstream/main }
```
A later push of that branch needs `git push --force-with-lease origin <branch>`.
`Coordinator\test\mainCoordinator\LocalResources.java` (gitignored,
machine-specific: `LocalResourcesTemplate.java` with `prefix` set to the
branch folder) must exist in each working copy.

Full guide: `C:\data\tools\shared-docs\fearless\development-guide.txt`
(https://marcoautomation2.github.io/shared-docs/fearless/development-guide.txt).

## Java

JDK 26 at `C:\Program Files\Java\jdk-26.0.2` — quote the path and use the
call operator: `& "C:\Program Files\Java\jdk-26.0.2\bin\java.exe" -ea ...`.
`JAVA_HOME` is unset. Assertions are always on: always pass `-ea`.

## The five programs

All in `Coordinator/test/mainCoordinator/`, run from `Coordinator\test`
via `java`'s source-launch, bootstrapped by the checked-in `Commons\Commons.jar`:
```powershell
& "C:\Program Files\Java\jdk-26.0.2\bin\java.exe" --module-path ..\..\Commons\Commons.jar --add-modules Commons mainCoordinator\<Name>.java
```
- `TestAllFrontend` — Commons + Frontend tests. Fast.
- `TestAllFrontendCoordinator` — + Coordinator, minus `integrationTests`. Fast.
- `TestAllFrontendCoordinatorIntegration` — everything. Minutes.
- `DeployPortableFearless` / `DeployManagedFearless` — build the portable
  compiler / the manager GUI app-image into `StandardLibrary\fearlessArtefact`
  / `StandardLibrary\fearlessManagedArtefact`.

Everything compiles as real JPMS modules with
`-Xlint:all,-auxiliaryclass,-missing-explicit-ctor -Werror`. While iterating
use the two fast ones; run the integration suite, the deploys, or the
`full-manual-checks` skill only when asked — never "to be safe".

`Commons\Commons.jar` is a manually updated snapshot that no build
overwrites. When `Commons/src` has changed, compare the regenerated
`<workspace>\out\modular\mods\Commons.jar` against it by entry contents
(timestamps differ on every build); if it differs, copy it over, commit and
PR it.

The portable binary needs a project folder as its argument; with none it
opens a welcome GUI and never exits.

## StandardLibrary API docs

Compiling a Fearless package writes `<pkg>.txt` next to `<pkg>.html`: a
plain-text rendering of types, signatures and doc comments meant for
agents. Read it before grepping `.fear` sources:
`StandardLibrary\dbgOut\baseCache\base.txt` for `base` (written by the
integration suite or a deploy), `<appDir>\stdLib\baseCache\base.txt` inside
an app-image, `<project>\.fearless_out\gen_java\<pkg>.txt` for any other
compiled project.

## Commons

Prefer `Commons\src\{utils,offensiveUtils,tools}` over rolling your own;
read the source. `utils`: `Bug` (`unreachable`/`todo`/`of`/`err`), `OneOr`
(exactly one stream element — use it instead of `findFirst` whenever one
result is assumed), `Join`, `Push`, `Pop`, `Range`, `Box`, `GetO`, `Mapper`,
`DistinctBy`, `Streams`/`Zipper2`/`Zipper3` (same-length asserted zips),
`Err` (test matcher with `[###]` holes), `Pos`, `ThrowingConsumer`/
`ThrowingFunction`, `UriSort`. `offensiveUtils`: `Require` (`check` is the
one unconditional guard; the rest compose inside `assert`),
`EqTransparent`/`@NeverAsKey`. `tools`: `Fs` (filesystem, `runTool`, the
`allowed` character set), `JavacTool`, `JavaTool` (child JVM),
`PortableApp`, `SourceOracle`, `Zips`, `ReadZip`, `ZipWalk`.

# Coding rules

## Offensive programming

Offensive programming is good, defensive programming is bad — including
implicit offensive programming (letting a bad input fail loudly on its own
rather than guarding against it). Expect non-null: call methods on it
directly. Expect a positive number where a negative one would only produce
nonsense: `assert`, with no message. "This may be A or B, I'll handle both
so the code flexibly adapts" is bad: one branch is dead, untested code. All
code that can't reliably be made to run shouldn't exist; the exceptions are
`Bug.unreachable()` and checks inside `assert consistent()` that may accept
early. A `zip` that silently ignores elements past the shorter input hides
errors — assert equal length. `stream.findFirst()` often hides an
assumption of a single result — use `OneOr`. Don't check "does any valid
option exist" when only one is ever valid on this OS. Offensive assertions
need no message: `return Objects.requireNonNull(image);` or just `return
image;`, not `assert image != null: "load() runs first"`. Graceful
degradation is the enemy: immediate hard failures, via assertions when
reasonable.

## Style

If a condition is longish, pull it into a local variable. Always brace
`if`/`for`/`while`; keep short ifs on one line: `if (toBeCut){ cutIt(); return; }`.
No blank lines splitting a method into sections. No ALL_CAPS names —
CamelCase for constants and enums too. Only these characters:
```java
public static final String allowed=
  "0123456789" +
  "abcdefghijklmnopqrstuvwxyz" +
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
  "+-*/=<>,.;:()[]{}" +
  "`'\"!?@#$%^&_|~\\" +
  " \n";
```
(mirrored in `Fs.allowed`). Modern Java: streams, lambdas, optionals; no
long inline lambdas — declare a method (`this::foo`, or
`(a,b)->foo(a,b,c,d)`); a lambda needing several statements or returns is
too big. Switch expressions, but factor out a sub-method instead of `yield`.

## No self-justification, no comments

Never pad anything — code, comments, error messages, docs, chat — with
asides justifying a choice by pointing at it being requested, fixed or
changed, or noting what could or couldn't be tested this session. Rationale
goes in the chat reply or the PR description, never in the deliverable.
This applies doubly to what Claude rereads every session (skills, CLAUDE.md,
memory): every aside costs tokens on every read.

In Java: never add a comment, and never remove one — Marco adds and removes
comments, often to flag something LLMs keep misreading. The one exception is
a comment capturing something that took real thinking to work out. A comment
that would read differently had the task gone differently ("this JVM runs on
Windows, so ... not something this suite re-proves") describes the session,
not the code, and is wrong.

## Minimality

Code must be as small as possible; readability is not a concern. Small code
means the whole codebase can be read — when reasonable, read all of it
before a task. Don't pass generated data: pass one unit of information and
regenerate locally. Invert ifs to favour early returns and errors, erasing
`then` branches. After code is generated and tested, do a second pass
purely to shrink it: remove abstractions and indirections that didn't earn
their place; a generalization is worth it only if the current codebase gets
smaller in actual lines. Duplication is far cheaper than the wrong
abstraction; a new concept (a type, an interface method) must earn its
value, not break even. Test code is near-free to duplicate; production code,
and especially a shared interface's public surface, is expensive — weigh
where the lines live. Duplication between fearlessPortable and
fearlessManager is fine. `public static boolean hasConsoleFlag(){ return
LauncherProps.hasConsoleFlag(); }` is pointless code.

## Moving or merging code on request

"Move X into Y, this removes the need for Z" must shrink the diff and
remove Z. If your answer adds a type, wrapper record, parameter, boolean
flag or file, you have misread it. If the literal request would grow the
code (a package-private type needs widening, a file needs splitting), stop
and ask, stating the tradeoff plainly. If it cannot be done without breaking
a constraint you weren't told to relax, say exactly what blocks it and ask —
never pick a side silently or invent an abstraction that pretends to comply.
A structural move keeps formatting and behavior unchanged; if that's
impossible, call out what changed.

## Conventions

Most code out there is bad code; conventions are only sometimes right. In
Marco's projects going against convention is deliberate — embrace the
unconventional setup rather than drifting toward "normal" code. Java is a
tool: rely on its formal semantics, not on its recommended usage.

## Names, messages, tests

- Never put Marco's name — or any real person's — in code, tests, mock data
  or commit messages; the codebase's placeholder users are `ada` and `bob`.
  Grep every repo for `marco` before finishing (the language-author credit
  in `InitialSupportGuiMain.java` is the one legitimate hit).
- Name things by what they are or their format, never by one downstream
  consumer (`junit_xml`, not `eclipse_junit_xml`).
- Keep a field typed as the concrete collection (`ArrayList<T>`) when it is
  statically always that type; widening to `List<T>` is not a goal.
- Every message factory in `Coordinator/src/userMessages/Violation.java`
  and `Report.java` has a test asserting its complete text (no `Err.hole`)
  with realistic, self-consistent mock inputs, added in the same PR as the
  message. Never refer to a file or folder by an undefined role ("its
  program folder"): give the real absolute path (`UserError.path`) or say
  nothing. Fearless is a language, not "a program": say "this copy of
  Fearless" or name the app.
- When a test's full expected value is known, assert it exactly, once
  (`assertEquals` on the whole, normalizing only the genuinely
  non-deterministic part), not with several `contains` samples.
- Manager GUI: whether a widget is enabled or selected is a pure function of
  the model, recomputed in `FolderInfo.refresh()`; a listener writes the
  model and returns, never `setEnabled`/`setSelected` on a sibling. Anything
  the GUI writes must read back: round-trip new fields through `InfoData` in
  a test with a real value shape.

# Working with Marco

- Design and review threads are discussion: answer in prose with a
  recommendation; no code and no menus of options until asked. Don't reopen
  settled policy.
- An exhaustive instruction ("read all", "check every") is completed in
  full, or the concrete blocker is named — never silently narrowed.
- Lead with the concrete example or outcome; mechanism comes after, as
  evidence. A reason given for skipping something must actually argue for
  skipping it.
- One task, one PR: push follow-ups to the existing PR; a new PR only for a
  separately scoped task.
- Explanatory prose about Fearless semantics in guides (ZeroToHero) is
  co-written with Marco: leave a placeholder note with the key facts to
  cover, don't draft it.
- A rule that holds for every branch goes in this file, not in a branch
  CLAUDE.md.
- winCoordinator asked to look at something and fix it does the work itself
  in `fearlessBranch4`; it delegates to win1/2/3 only when asked to
  coordinate them.
- Subagents get no wake-up for their own background commands: tell them to
  run slow commands inline and wait. Read a subagent's result before
  treating "completed" as done, and verify any claim about what a human did.
- The browser (Brave) is Claude's: close every tab on the way out; never
  force-kill it.
- Windows Explorer drag-and-drop cannot be simulated with synthetic input
  here; test Swing DnD through a fake `Transferable` plus the click-driven
  path.

# shared-docs site

Checkout `C:\data\tools\shared-docs` (`marcoautomation2/shared-docs`, no
upstream): commit directly to `main`. `index.html` is a homepage — one link
and one short clause per evergreen entry; dated reports and bug reports go
in their own sub-index (`bug-reports/index.html`) or a cross-link from the
page they belong to. Reusable how-tos go in `fearless/setup-cheatsheet.txt`.
When a published fact goes stale, fix it in place; remove a page only when
nothing on it is true or useful any more.
