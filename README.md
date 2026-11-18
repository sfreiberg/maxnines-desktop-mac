# MaxNines Menu Bar

A Mac menu bar app for [MaxNines](https://github.com/sfreiberg/maxnines). It shows the
alerts that are firing on your MaxNines server and links to its web interface.

## Setting it up

1. Click its menu bar icon, enter your server's address, and choose **Sign in**.
2. Your browser opens MaxNines. Sign in there if you aren't already, choose the role
   the app gets, and choose **Allow**. A viewer sees alerts. A responder can also
   acknowledge and silence them, which is what the app asks for. You can't give it
   more than your own role.
3. The browser says you're signed in, and the menu shows your server's alerts. You can
   close the tab. The app's settings say who it's signed in as.

The app stays signed in for up to 90 days after it was last used, and keeps what it
needs for that in your Keychain. To sign it out, choose **Sign out** in its settings.
In MaxNines, **Settings**, then **Signed-in apps**, lists it with the Mac's name, and
you can revoke it there too. If it's revoked or runs out, the menu says so, with a
button to sign in again. To use another server, sign out in its settings first.

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
alert resolves, each turned on or off in its settings. All three are on to begin with.
Alerts that a silence or maintenance window is holding back never send one, as
everywhere else in MaxNines, and one still firing when its silence ends sends one then.
Nothing that was already firing when the app started is announced, and more than three
at once arrive as one.

Each starts with the circle MaxNines uses in Discord: red for critical, yellow for a
warning, and green once it's resolved. A resolved one says where things stand, such as
"web-1 is back online", and how long the problem lasted.

A notification about an alert that's started has Acknowledge, which needs the
responder role, and Open in MaxNines.

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

The bottom of its settings says exactly which build it is: the version, the commit it
was built from, ending in `-dirty` if there were uncommitted changes, and when it was
built.

A server reached over plain `http` has to be on your local network, as macOS won't let
the app send its sign in unencrypted any further.
