# WhatsMail Bridge

## Overview

A script to bundle all unread WhatsApp messages into one email alert.

## Email Format

The email is sent as **HTML** with a chat-bubble interface. Messages are grouped by chat, each section showing a profile avatar, chat name, message bubbles, and an "Open in WhatsApp" card.

### Visual Layout

Each chat section contains:

1. **Chat name** — displayed above the messages, aligned with bubble text
2. **Profile avatar** — 32px circle, top-aligned with the first message bubble. Uses the contact's actual profile picture (base64-embedded from `ZWAPROFILEPICTUREITEM`) when available; falls back to a grey circle when no picture exists
3. **Vertical line** — 2px line centered on the avatar, starts below the avatar (with a 5px gap), continues through all messages and the card
4. **Message bubbles** — grey rounded rectangles with timestamp and content
5. **"Open in WhatsApp" card** — bordered rectangle at the bottom of each chat section

### Message Bubbles

- **1:1 chats**: bubbles show `[YYYY-MM-DD HH:MM]` + content (no sender name)
- **Group chats**: bubbles show `[YYYY-MM-DD HH:MM] Sender` + content
- **Timestamp grouping**: if consecutive messages in the same chat are less than 10 minutes apart, only the first message shows the timestamp; subsequent messages show only the content

### "Open in WhatsApp" Card

A bordered rounded rectangle containing:

- **Bold chat name**
- **1:1 chats with link**: pill-shaped outlined button linking to `https://wa.me/<chatjid>`
- **Group chats or no link**: plain text "Manually open in WhatsApp to access"

### Link Rules

- **1:1 chats** (`@s.whatsapp.net`): WhatsApp link is built from the chat JID: strip the suffix and prepend `https://wa.me/`
- **1:1 chats** (`@lid`): these use opaque internal IDs, not phone numbers. If `ZPARTNERNAME` starts with `+`, strip non-digit characters and use it as the `wa.me` link. Otherwise, no link is available
- **Group chats or no link available**: no clickable link

### Subject Line

`(DD/MM/YYYY) N unread messages` (singular `message` when N is 1)

### Other Rules

- Chats are ordered by their first unread message timestamp
- Multi-line message content: the query outputs `<NL>` as a newline placeholder; the bridge converts each `<NL>` to `<br>`
- All text is black (`#000`), uniform 13px font size
- Border color `#c8c8c8` is shared across the vertical line, bubble borders, card border, and pill button border
- Profile pictures are looked up from `ZWAPROFILEPICTUREITEM` using the chat's raw `ZCONTACTJID`, resolved to a file in `Media/Profile/` (globbed for extension), and embedded as base64 data URIs. For `@s.whatsapp.net` chats where the DB returns no path (profile pics are stored under `@lid` JIDs), falls back to searching `Media/Profile/<phone_number>-*` on disk

## Script

```bash
#!/bin/bash

# Settings
DB="/path/to/Messages.db"
PROFILE_DIR="/path/to/Media/Profile"
SQL="SELECT ..."   # includes RawChatJID field for profile pic lookup
TO="you@example.com"

# Profile picture lookup: query ZWAPROFILEPICTUREITEM for ZPATH,
# find file on disk (glob for extension), base64-encode as data URI.
# Falls back to grey circle when no picture exists.
get_avatar() { ... }

# Process
DATA=$(sqlite3 "$DB" "$SQL")

if [ -n "$DATA" ]; then
    BODY=$(format_html "$DATA")   # group by chat, build HTML with bubbles + profile pics
    MSG_COUNT=$(echo "$DATA" | wc -l)
    printf "Subject: (%s) %s unread messages\nContent-Type: text/html; charset=UTF-8\nMIME-Version: 1.0\n\n%s" "$(date +%d/%m/%Y)" "$MSG_COUNT" "$BODY" | msmtp "$TO"
fi
```

## Usage

### Manual

```bash
bash whatsmail_bridge.sh
```

### Daily Automation

Use a macOS Launch Agent to run via `launchctl`.
