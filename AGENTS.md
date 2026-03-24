# Logging

`/usr/bin/log show --predicate 'eventMessage CONTAINS "local.whatsmail"' --last 5m --style compact --info --debug`

Filter by eventMessage, not subsystem.

# Build & sign

`make`

# Verify binary

`codesign -dv dist/whatsmail_bin`
