<!--
 Copyright (c) 2026 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# WhatsMail

Forwards unread WhatsApp messages to your inbox as a daily email digest. Reads from the WhatsApp macOS local SQLite database, groups messages by chat, and sends via `msmtp`.

<p align="center">
 <img align="center" src="https://github.com/user-attachments/assets/3a05f996-f47c-4ee6-803e-a032e0e45497" width="620">
</p>

## Setup

- macOS with WhatsApp Desktop installed
- `msmtp` (`brew install msmtp`)

```bash
cp .msmtp.rc.example .msmtp.rc
chmod 600 .msmtp.rc
# Edit .msmtp.rc with your SMTP server details
```

## Usage

```bash
WHATSMAIL_TO=you@example.com bash whatsmail_bridge.sh
```

### Scheduled Automation (9 AM)

1. Create `~/Library/LaunchAgents/local.whatsmail.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.whatsmail</string>
    <key>ProcessType</key>
    <string>Background</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/whatsmail_bridge.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>WHATSMAIL_TO</key>
        <string>you@example.com</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

2. Load the task:

```bash
launchctl load ~/Library/LaunchAgents/local.whatsmail.plist
```

## Logging

View logs with Apple Unified Logging:

```bash
/usr/bin/log show --predicate 'eventMessage contains "whatsmail"' --info --debug
```

## Specifications

See [`specs/README.md`](specs/README.md) for design documentation.

## License

Proprietary. Copyright (c) 2026 Henrique Falconer. All rights reserved.
