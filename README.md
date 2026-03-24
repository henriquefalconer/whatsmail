<!--
 Copyright (c) 2026 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# WhatsMail

Forwards unread WhatsApp messages to your inbox as a daily email digest. Reads from the WhatsApp macOS local SQLite database, groups messages by chat, and sends via `msmtp`.

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

### Daily Cron (9 AM)

```
0 9 * * * WHATSMAIL_TO=you@example.com /bin/bash /path/to/whatsmail_bridge.sh
```

## Specifications

See [`specs/README.md`](specs/README.md) for design documentation.

## License

Proprietary. Copyright (c) 2026 Henrique Falconer. All rights reserved.
