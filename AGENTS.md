# Logging

`/usr/bin/log show --predicate 'eventMessage CONTAINS "local.whatsmail"' --last 5m --style compact --info --debug`

Filter by eventMessage, not subsystem.

# Force a manual run immediately to verify

`launchctl kickstart -k gui/$(id -u)/local.whatsmail`
