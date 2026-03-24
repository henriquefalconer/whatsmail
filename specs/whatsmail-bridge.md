# WhatsMail Bridge

Bundles unread WhatsApp messages into one HTML email alert, grouped by chat.

## Subject Line

`(DD/MM/YYYY) N unread messages` (singular `message` when N is 1)

## Email Layout

Each chat section contains, in order:

1. **Chat name** — above messages, aligned with bubble text
2. **Profile avatar** — 32px circle, top-aligned with first bubble; actual profile picture (base64-embedded) or grey circle fallback
3. **Vertical line** — 2px, centered on avatar, 5px gap below it, continues through all messages and the card
4. **Message bubbles** — grey rounded rectangles
   - 1:1 chats: `[YYYY-MM-DD HH:MM]` + content
   - Group chats: `[YYYY-MM-DD HH:MM] Sender` + content
   - Consecutive messages < 10 min apart: only the first shows the timestamp
5. **"Open in WhatsApp" card** — bordered rounded rectangle with bold chat name and link (or fallback text)

## Link Rules

| Chat type | Link |
|-----------|------|
| `@s.whatsapp.net` | `https://wa.me/<phone>` (strip suffix from JID) |
| `@lid` with `ZPARTNERNAME` starting `+` | `https://wa.me/<digits>` (strip non-digits) |
| `@lid` without `+` / group chats | No link — "Manually open in WhatsApp to access" |

## Profile Pictures

Resolved via a layered lookup chain, embedded as base64 data URIs:

1. **L1** — `ZWAPROFILEPICTUREITEM` DB path → `Media/Profile/` file (globbed for extension). Best for `@lid` chats.
2. **L2b** — `pp` blob by LID: resolve LID via `ContactsV2.sqlite` (`ZWAADDRESSBOOKCONTACT.ZLID` matched on `ZWHATSAPPID`), then fetch JPEG from `LocalKeyValue.sqlite` (`ZNAMESPACE = 'pp'`, `ZKEY` = LID). Best coverage for `@s.whatsapp.net` chats.
3. **L2a** — `pp` blob by raw JID: fetch JPEG from `LocalKeyValue.sqlite` (`ZNAMESPACE = 'pp'`, `ZKEY` = raw `ZCONTACTJID`).
4. **L3** — Disk glob `Media/Profile/<phone>-*`, filtering out group files (suffix with extra dashes).
5. **L4** — Grey circle fallback.

## Styling

- All text black (`#000`), 13px font
- Border color `#c8c8c8` shared across vertical line, bubbles, card, and pill button
- Chats ordered by first unread message timestamp
- Placeholders from query: `<NL>` → `<br>`, `<PIP>` → `|`

## Script Pseudocode

```bash
#!/bin/bash
set -u; set -o pipefail

log() { /usr/bin/logger -t WhatsMail "[local.whatsmail] $1"; }
trap '[ $? -ne 0 ] && log "ERROR: exited with code $?"' EXIT

TO="$WHATSMAIL_TO"

DATA=$(bash unread_messages.sh) || { log "ERROR: unread_messages.sh failed"; exit 1; }

if [ -n "$DATA" ]; then
    BODY=$(format_html "$DATA")   # group by chat, build HTML with bubbles + profile pics
    MSG_COUNT=$(echo "$DATA" | wc -l)
    printf "Subject: ...\nContent-Type: text/html; charset=UTF-8\n\n%s" "$BODY" \
        | msmtp "$TO" || { log "ERROR: msmtp failed"; exit 1; }
fi
```

## Usage

- **Manual**: `WHATSMAIL_TO=you@example.com bash whatsmail_bridge.sh`
- **Build**: `make` (compiles with `shc`, signs with `codesign`)
- **Scheduled**: macOS Launch Agent (`local.whatsmail.plist`) runs the binary daily at 9 AM via `launchctl`
