# WhatsApp macOS Local Database Interface

## Database Location
`~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite`

SQLite database used by WhatsApp Desktop (macOS).

---

## Important Tables

### ZWAMESSAGE — Messages
Stores every message.

Key fields:

- **Z_PK** — Message ID
- **ZISFROMME** — 1 = sent by you, 0 = received
- **ZMESSAGESTATUS** — Delivery/read state
- **ZMESSAGETYPE** — Type of content
- **ZCHATSESSION** — Chat reference
- **ZGROUPMEMBER** — Group sender reference
- **ZMESSAGEDATE** — Timestamp (Apple epoch)
- **ZFROMJID / ZTOJID** — Sender / recipient IDs
- **ZPUSHNAME** — Cached sender name
- **ZSTANZAID** — WhatsApp message identifier (unique per real message; used to deduplicate)
- **ZTEXT** — Message text
- **ZFLAGS** — Internal flags bitmask (undocumented; meaning varies by version)

**Convert timestamp to normal time:**

unix = ZMESSAGEDATE + 978307200


---

### ZWACHATSESSION — Chats
Each conversation (private or group).

Important fields:

- **Z_PK** — Chat ID
- **ZPARTNERNAME** — Chat display name
- **ZCONTACTJID** — Chat identifier
- **ZSESSIONTYPE** — 1 = group chat
- **ZUNREADCOUNT** — Number shown in unread badge
- **ZLASTMESSAGEDATE** — Last message seen
- **ZARCHIVED** — Archived flag
- **ZHIDDEN** — Hidden flag

---

### ZWAGROUPMEMBER — Group Participants

- **Z_PK** — Member ID
- **ZCHATSESSION** — Chat reference
- **ZMEMBERJID** — Member identifier
- **ZCONTACTNAME** — Group nickname
- **ZFIRSTNAME** — First name

---

### ZWAPROFILEPUSHNAME — Saved Contacts

Important fields:

- **Z_PK** — Row ID (primary key, as with all CoreData tables)
- **ZJID** — Contact identifier (logical unique key)
- **ZPUSHNAME** — Saved contact name

---

### ZWAPROFILEPICTUREITEM — Profile Pictures

Stores profile picture metadata and file paths.

- **Z_PK** — Row ID
- **ZJID** — Contact identifier (may be prefixed with `a_` for device-linking entries)
- **ZPATH** — Either a relative file path (`Media/Profile/<name>`) or base64-encoded protobuf data
- **ZPICTUREID** — Picture version identifier
- **ZREQUESTDATE** — Timestamp of last fetch

**File storage notes:**
- Files on disk have extensions (`.thumb`, `.jpg`) not included in `ZPATH`
- Contact profile pictures use `@lid` JIDs with `Media/Profile/` paths
- `a_`-prefixed JIDs store protobuf device-linking data, not images
- `@s.whatsapp.net` JIDs in this table typically don't have usable image paths
- `@newsletter` JIDs have `Media/Profile/` paths for channel icons

**Profile picture locations on macOS:**

| Location | Format | Naming | Coverage |
|----------|--------|--------|----------|
| `~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Media/Profile/` | `.thumb`, `.jpg` | `<phone_or_lid>-<id>` | Subset of contacts; referenced by `ZPATH` in DB |
| `~/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches/spotlight-profile-v2/` | `.png` | Opaque numeric hash (mapping to JID unknown) | Most contacts; used by Spotlight integration |

The `spotlight-profile-v2` cache contains profile pictures for contacts that may not have entries in `Media/Profile/`, but the filename-to-JID mapping is not stored in the database and uses an unknown hashing scheme (not standard MD5/SHA1/SHA256 of the JID). Currently unusable for programmatic lookup.

---

## Relationships (Implicit)


Message → Chat
ZWAMESSAGE.ZCHATSESSION = ZWACHATSESSION.Z_PK

Message → Group Sender
ZWAMESSAGE.ZGROUPMEMBER = ZWAGROUPMEMBER.Z_PK

Private Sender → Contact Name (via private sender JID from message)
ZWAMESSAGE.ZFROMJID = ZWAPROFILEPUSHNAME.ZJID

Group Sender → Member → Contact Name (via group member JID from group record)
ZWAGROUPMEMBER.ZMEMBERJID = ZWAPROFILEPUSHNAME.ZJID

Chat → Profile Picture (via chat JID)
ZWACHATSESSION.ZCONTACTJID = ZWAPROFILEPICTUREITEM.ZJID


---

## Sender Name Priority

1. Saved contact name (from `ZWAPROFILEPUSHNAME`)
2. Group nickname
3. Chat partner name (from sender's `ZWACHATSESSION.ZPARTNERNAME`)
4. Phone number from JID
5. "Unknown Sender"

> **Note:** `ZWAMESSAGE.ZPUSHNAME` is _not_ a display name in current DB versions — it stores base64-encoded protobuf metadata (timestamps, message hashes). It must not be used for sender resolution.

---

## Message Status Meaning (ZMESSAGESTATUS, Inferred from observed behavior)

| Value | Meaning |
|------|---------|
| 0 | System / service message |
| 1 | Outgoing sent (read receipt not yet processed) |
| 5 | Media processing / transient |
| 6 | Delivered to you (candidate unread) |
| 7 | Expired / disappearing |
| 8 | **Read** |
| 13 | Special rare event |

### Message Lifecycle (Observed, Typical)

Incoming:

6 → 8
(delivered → read)


Outgoing:

1 → 8
(sent → read receipt processed)

Some media and system messages use different transitions (e.g., media processing, reactions, deleted messages, failed sends may skip states or use different codes). Common status values are listed in the table above; other values may exist.


---

## SQL — Get Unread Incoming Messages

Standalone script: [`unread_messages.sh`](../unread_messages.sh)

```sql
SELECT
    sub.Z_PK AS MsgID,
    sub.Time,
    sub.Chat,
    sub.ChatJID,
    CASE
        WHEN sub.ZISFROMME = 1 THEN 'You'
        ELSE COALESCE(
            NULLIF(pn.ZPUSHNAME, ''),
            NULLIF(gpn.ZPUSHNAME, ''),
            NULLIF(gm.ZCONTACTNAME, ''),
            NULLIF(sc.ZPARTNERNAME, ''),
            NULLIF(sub.Chat, 'Unknown Chat'),
            REPLACE(REPLACE(REPLACE(COALESCE(gm.ZMEMBERJID, sub.ZFROMJID),'@s.whatsapp.net',''),'@g.us',''),'@lid',''),
            'Unknown Sender'
        )
    END AS Sender,
    sub.IsGroup,
    sub.Content,
    sub.ZMESSAGESTATUS AS Status
FROM (
    SELECT
        m.Z_PK,
        datetime(m.ZMESSAGEDATE + 978307200, 'unixepoch', 'localtime') AS Time,
        COALESCE(c.ZPARTNERNAME, 'Unknown Chat') AS Chat,
        REPLACE(REPLACE(REPLACE(c.ZCONTACTJID, '@s.whatsapp.net', ''), '@g.us', ''), '@lid', '') AS ChatJID,
        m.ZISFROMME,
        m.ZFROMJID,
        m.ZGROUPMEMBER,
        m.ZSTANZAID,
        m.ZMESSAGEDATE,
        m.ZMESSAGESTATUS,
        m.ZCHATSESSION,
        CASE WHEN c.ZSESSIONTYPE = 1 THEN 1 ELSE 0 END AS IsGroup,
        REPLACE(COALESCE(m.ZTEXT, '[Media or non-text message]'), CHAR(10), '<NL>') AS Content,
        ROW_NUMBER() OVER (PARTITION BY m.ZCHATSESSION ORDER BY m.ZMESSAGEDATE DESC) AS rn,
        c.ZUNREADCOUNT
    FROM ZWAMESSAGE m
    JOIN ZWACHATSESSION c ON m.ZCHATSESSION = c.Z_PK
    WHERE
        m.ZISFROMME = 0
        AND c.ZUNREADCOUNT > 0
        AND m.ZMESSAGETYPE != 10
) sub
LEFT JOIN ZWAPROFILEPUSHNAME pn ON sub.ZFROMJID = pn.ZJID
LEFT JOIN ZWAGROUPMEMBER gm ON sub.ZGROUPMEMBER = gm.Z_PK
LEFT JOIN ZWAPROFILEPUSHNAME gpn ON gm.ZMEMBERJID = gpn.ZJID
LEFT JOIN ZWACHATSESSION sc ON COALESCE(gm.ZMEMBERJID, sub.ZFROMJID) = sc.ZCONTACTJID
WHERE sub.rn <= sub.ZUNREADCOUNT
GROUP BY sub.ZSTANZAID
ORDER BY MIN(sub.ZMESSAGEDATE) OVER (PARTITION BY sub.ZCHATSESSION), sub.ZMESSAGEDATE ASC;
```

## Unread Logic

Unread detection is approximated using three layers:

1. **Message-level state** → `ZMESSAGESTATUS`
2. **Chat-level badge counter** → `ZUNREADCOUNT`
3. **Message position** relative to the chat's read boundary in the message timeline

Unread candidates are the most recent `ZUNREADCOUNT` incoming messages per chat:

    m.ZISFROMME = 0
    AND c.ZUNREADCOUNT > 0
    AND ROW_NUMBER() OVER (PARTITION BY chat ORDER BY timestamp DESC) <= ZUNREADCOUNT

Note: `ZMESSAGESTATUS` alone is not reliable for unread detection — WhatsApp may leave old messages stuck at status 6 even after they have been read in the UI. The chat-level `ZUNREADCOUNT` badge is the source of truth for how many messages are unread; combined with descending timestamp order, it identifies which messages those are.

### Multi-line Messages

Message text may contain newlines, which would break the pipe-delimited row format of `sqlite3` output. The query replaces newlines with `<NL>` in the `Content` field so each result row stays on a single line. Downstream consumers must convert `<NL>` back to real newlines when displaying.

### Duplicate Messages

WhatsApp may store the same message multiple times with different `Z_PK` values. Duplicates share the same `ZSTANZAID` (WhatsApp's internal message identifier). Queries must deduplicate by `ZSTANZAID` to avoid returning the same message more than once.

## Version Information

This interface was documented using the following versions.

### WhatsApp Application Version

`26.10.74`

Obtained from the app bundle:

```bash
defaults read /Applications/WhatsApp.app/Contents/Info.plist CFBundleShortVersionString
```

### Database Model Version (CoreData)

From table `Z_METADATA`:

- **Model Version (Z_VERSION):** 1
- **Database UUID (Z_UUID):** B5F00064-B760-44A1-801F-FE205D8C7D3F

Command used:

```bash
sqlite3 ~/Library/Group\ Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite "
SELECT Z_VERSION, Z_UUID FROM Z_METADATA;
"
```

### SQLite Schema Revisions

```
PRAGMA user_version   = 0
PRAGMA schema_version = 74
```

Command used:

```bash
sqlite3 ~/Library/Group\ Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite "
PRAGMA user_version;
PRAGMA schema_version;
"
```

### Notes

- `Z_VERSION` identifies the CoreData object model version.
- `Z_UUID` uniquely identifies this database instance.
- `schema_version` changes when the database structure is modified.
- These values help determine compatibility across WhatsApp updates.

---

## Notes
- Database uses Apple CoreData (no explicit foreign keys)
- Schema may change between app versions
- Timestamps use Apple epoch
- Flags are internal and version-dependent
