# RemindMeet

A macOS menu bar app for people who miss meetings despite calendar notifications.
One minute before each meeting, a full-screen panel covers everything: join, snooze for a minute (twice at most), or skip.
If you haven't clicked by start time, it opens the Google Meet link itself and keeps the panel up until you do.

![The reminder panel, 42 seconds before a meeting](docs/screenshot.png)

It reads events from the macOS Calendar, so add your Google account there. Build with `make run`, or `nix build`.
