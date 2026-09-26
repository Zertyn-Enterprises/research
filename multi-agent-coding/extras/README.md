<!-- managed-by: multi-agent-coding -->
# Extras — menu-bar widgets

**Not in v0.1. Nothing in this directory is installed by `install.sh`.** This page
describes two macOS widgets so you know what they are, what they would need, and
what the equivalent is on Linux or WSL2. Both are `planned`; see
[../ROADMAP.md](../ROADMAP.md).

The problem they solve: once you run more than two or three agent sessions at once,
the expensive thing is not the tokens, it is finding the session that is waiting for
you. A session blocked on a permission prompt costs you nothing in quota and
everything in wall-clock time, and nothing on screen tells you it happened.

## FleetBar — session index in the menu bar

A macOS menu-bar item that lists every live agent session with its repo, branch and
state (working, waiting for input, idle), and raises the right terminal window when
you pick one.

| Requirement | Why |
|---|---|
| macOS 13.0 or newer | It is a native menu-bar app. There is no cross-platform version. |
| The fleet module | The list comes from the session ledger that module maintains. Without it the widget has nothing to show. |
| tmux | Sessions are addressed as tmux windows; that is what "raise this one" resolves to. |
| Accessibility permission for a terminal it can drive | Raising and focusing a specific window needs the Accessibility API. Currently implemented for Ghostty only; any other terminal needs its own window-addressing path. |

The Accessibility requirement is the honest blocker on portability. Focusing an
arbitrary window in another application is a privileged operation on macOS and a
per-terminal integration everywhere, which is why this is a widget for one terminal
on one operating system rather than a feature of the kit.

## Cost-ledger menu bar (`tokuse` bar)

A second macOS menu-bar item showing today's token use and spend across sessions,
read from the cost ledger.

| Requirement | Why |
|---|---|
| macOS 13.0 or newer | Native Swift menu-bar app. |
| The token and cost ledger module (`tokuse`) | The widget is a read-only view of that store. |
| `python3` | The ledger writer is Python and locks its store with `fcntl`, which is Unix-only. |

It never talks to a vendor API. It reads the local ledger, which is itself written
from the CLI's own session files, so the numbers are as good as those files and no
better.

## The same signal on Linux and WSL2

You do not need a menu bar to know that a session is waiting. Claude Code's
`Notification` hook event fires on `permission_prompt`, `idle_prompt`,
`elicitation_dialog` and `auth_success`
([hooks](https://code.claude.com/docs/en/hooks)), which is exactly the set of
moments a widget would be highlighting.

So once the fleet module ships, the documented Linux and WSL2 path is a
`Notification` hook that turns each event into a desktop notification:

- **Linux desktop:** `notify-send` with the repo and branch in the title, so you
  can tell four sessions apart at a glance.
- **WSL2:** the same hook, routed to a Windows toast. WSL2 can invoke Windows
  executables, so the notification lands on the Windows desktop where you are
  actually looking.
- **Headless or remote:** the same hook, pointed at whatever you already read — a
  chat webhook, a terminal bell, a tmux status flag.

That path has no Accessibility problem and no per-terminal integration, because it
pushes the signal to you instead of pulling your attention to a list. It does not
give you click-to-focus; on Linux and WSL2 you jump with the fleet module's shell
commands instead.

## Why these are extras and not features

They are single-platform, they depend on a module that is not shipped, and one of
them depends on a specific terminal. Shipping them as part of the kit would mean
every installer path, every test, and every OS matrix row carries a macOS-only,
Ghostty-only branch. They stay here, documented and unwired, until the fleet module
lands and the Linux path above is implemented alongside them.
