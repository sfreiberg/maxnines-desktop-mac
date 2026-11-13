# MaxNines Menu Bar

A Mac menu bar app for [MaxNines](https://github.com/sfreiberg/maxnines). It shows the
alerts that are firing on your MaxNines server and links to its web interface.

## Setting it up

1. In MaxNines, open **Settings** and make an API key. A viewer key shows alerts. A
   responder key can also acknowledge and silence them.
2. Open the app's settings from its menu bar icon and enter your server's address and
   the key. The key is kept in your Keychain.

## Building

It needs macOS 14 or later and Swift 6.

```sh
scripts/bundle.sh        # builds it and makes build/MaxNines.app
open build/MaxNines.app
scripts/test.sh          # runs the tests
```

A server reached over plain `http` has to be on your local network, as macOS won't let
the app send the key unencrypted any further.
