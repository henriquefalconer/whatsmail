# WhatsMail Bridge

## Overview

A script to bundle all unread WhatsApp messages into one email alert.

## Email Format

Messages are grouped by chat. Each chat is a section with a header, followed by its messages in chronological order.

### Example Output

```
Subject: (24/03/2026) 5 unread messages

========================================
Family Group
[Open in WhatsApp to access]
========================================

[2026-03-24 09:12] Mom
  Hey, are we still on for dinner tonight?

[2026-03-24 09:15] Dad
  Sure, I'll be there by 7.

[2026-03-24 09:47] Mom
  [Media or non-text message]

========================================
Alice
https://wa.me/5511999999999
========================================

[2026-03-24 10:03] Alice
  Can you send me the report?

[2026-03-24 10:05] Alice
  Never mind, found it!
```

### Rules

- Subject line includes the date and message count: `(DD/MM/YYYY) N unread messages` (singular `message` when N is 1)
- Chats are separated by `========` divider lines containing the chat name and a WhatsApp link
- **1:1 chats** (`@s.whatsapp.net`): WhatsApp link is built from the chat JID: strip the suffix and prepend `https://wa.me/`
- **1:1 chats** (`@lid`): these use opaque internal IDs, not phone numbers. If `ZPARTNERNAME` starts with `+`, strip non-digit characters and use it as the `wa.me` link. Otherwise, no link is available
- **Group chats or no link available**: the email shows `[Open in WhatsApp to access]` instead
- Each message shows `[YYYY-MM-DD HH:MM] Sender` on one line, then the content indented by 2 spaces on the next
- Messages within a chat are separated by a blank line
- Chats are ordered by their first unread message timestamp
- Multi-line message content: the query outputs `<NL>` as a newline placeholder; the bridge converts each `<NL>` back to a newline + 2-space indent

## Script

```bash
#!/bin/bash

# Settings
DB="/path/to/Messages.db"
SQL="SELECT ..."
TO="you@example.com"

# Process
DATA=$(sqlite3 "$DB" "$SQL")

if [ -n "$DATA" ]; then
    BODY=$(format "$DATA")   # group by chat, apply template
    MSG_COUNT=$(echo "$DATA" | wc -l)
    printf "Subject: (%s) %s unread messages\nContent-Type: text/plain; charset=UTF-8\n\n%s" "$(date +%d/%m/%Y)" "$MSG_COUNT" "$BODY" | msmtp "$TO"
fi
```

## Usage

### Manual

```bash
bash whatsmail_bridge.sh
```

### Daily Cron

Add to `crontab -e` to run at 9 AM:

```
0 9 * * * /bin/bash /path/to/whatsmail_bridge.sh
```
