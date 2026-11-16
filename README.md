# MaxNines Menu Bar

A Mac menu bar app for [MaxNines](https://github.com/sfreiberg/maxnines). It shows the
alerts that are firing on your MaxNines server and links to its web interface.

## Setting it up

1. In MaxNines, open **Settings** and make an API key. A viewer key shows alerts. A
   responder key can also acknowledge and silence them.
2. Open the app's settings from its menu bar icon and enter your server's address and
   the key. The key is kept in your Keychain.

## What it shows

The icon says the worst thing happening: plain when nothing is firing, an amber square
and how many when there are only warnings, and a red dot and how many alerts are firing
in all when something is critical. Dimmed and dashed with a question mark, it can't
reach the server, so quiet is never mistaken for fine.

Its menu shows how many hosts are online, the alerts firing, with Acknowledge and
Silence 1 hour, what resolved in the last hour, and the silences running now. If the
server runs checks itself, it also shows how many of them are passing, counting only
checks that aren't paused and have run since the server started.

## Notifications

The app can tell you when a critical alert starts, when a warning starts, and when an
alert resolves, each turned on or off in its settings. Critical alerts and resolved
ones are on to begin with. Alerts that a silence or maintenance window is holding back
never send one, as everywhere else in MaxNines. Nothing that was already firing when
the app started is announced, and more than three at once arrive as one.

A notification about an alert that's started has Acknowledge, which needs a responder
key, and Open in MaxNines.

## Open at login

Turn on **Open at login** in its settings. Move the app to Applications first, as macOS
remembers where it was when you turned it on.

## Building

It needs macOS 14 or later and Swift 6.

```sh
scripts/bundle.sh        # builds it and makes build/MaxNines.app
open build/MaxNines.app
scripts/test.sh          # runs the tests
```

A server reached over plain `http` has to be on your local network, as macOS won't let
the app send the key unencrypted any further.
