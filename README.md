<!--
 Copyright (c) 2026 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# WhatsMail

Forwards unread WhatsApp messages to your inbox as a daily email digest. Reads from the WhatsApp macOS local SQLite database, groups messages by chat, and sends via `msmtp`.

<p align="center">
 <img align="center" src="https://github.com/user-attachments/assets/3a05f996-f47c-4ee6-803e-a032e0e45497" width="620">
</p>

## Requirements

- macOS with WhatsApp Desktop installed
- Xcode Command Line Tools (for `codesign`): `xcode-select --install`
- `shc` (shell script compiler): `brew install shc`
- `msmtp` (SMTP client): `brew install msmtp`

## Setup

### 1. Configure SMTP

```bash
cp .msmtp.rc.example .msmtp.rc
chmod 600 .msmtp.rc
# Edit .msmtp.rc with your SMTP server details
```

### 2. Build & Sign the Binary

Compile the script into a binary and sign it so macOS can remember its permissions:

```bash
shc -f whatsmail_bridge.sh -o whatsmail_bin
codesign --force --identifier "local.whatsmail" -s - whatsmail_bin
```

### 3. Grant Permissions

1. Open **System Settings > Privacy & Security > Full Disk Access**
2. Click **[+]** and select the `whatsmail_bin` file

### 4. Configure the LaunchAgent

Create `~/Library/LaunchAgents/local.whatsmail.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.whatsmail</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/whatsmail_bin</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>WHATSMAIL_TO</key>
        <string>you@example.com</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

### 5. Load the Service

```bash
launchctl load ~/Library/LaunchAgents/local.whatsmail.plist
```

## Manual Usage

```bash
WHATSMAIL_TO=you@example.com bash whatsmail_bridge.sh
```

## Logging

View logs with Apple Unified Logging:

```bash
/usr/bin/log show --predicate 'eventMessage contains "local.whatsmail"' --info --debug
```

## Specifications

See [`specs/README.md`](specs/README.md) for design documentation.

## License

Proprietary. Copyright (c) 2026 Henrique Falconer. All rights reserved.
