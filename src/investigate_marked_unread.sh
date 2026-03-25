#!/bin/bash
# Investigate where "marked as unread" state is stored in the WhatsApp database.
# Uses a known marked-as-unread group ("H, D, V") as the test case.

DB_PATH=~/Library/Group\ Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite

if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: WhatsApp Chat database not found: $DB_PATH"
    exit 1
fi

CHAT_NAME="H, D, V"

echo "============================================"
echo "Investigating 'marked as unread' for: $CHAT_NAME"
echo "============================================"

echo ""
echo "--- 1. ZWACHATSESSION columns for this chat ---"
echo ""
/usr/bin/sqlite3 -header -column "$DB_PATH" "
SELECT *
FROM ZWACHATSESSION
WHERE ZPARTNERNAME = '$CHAT_NAME';
"

echo ""
echo "--- 2. All ZWACHATSESSION column names ---"
echo ""
/usr/bin/sqlite3 "$DB_PATH" "PRAGMA table_info(ZWACHATSESSION);" | while IFS='|' read -r cid name type notnull dflt pk; do
    echo "  $name ($type)"
done

echo ""
echo "--- 3. Compare with a chat that has real unread messages (ZUNREADCOUNT > 0, not marked) ---"
echo ""
/usr/bin/sqlite3 -header -column "$DB_PATH" "
SELECT Z_PK, ZPARTNERNAME, ZUNREADCOUNT, ZARCHIVED, ZHIDDEN, ZSESSIONTYPE, ZFLAGS,
       ZLASTMESSAGEDATE, ZPROPERTIES
FROM ZWACHATSESSION
WHERE ZUNREADCOUNT > 0
LIMIT 5;
"

echo ""
echo "--- 4. Key fields for '$CHAT_NAME' vs other chats with ZUNREADCOUNT = 0 ---"
echo ""
/usr/bin/sqlite3 -header -column "$DB_PATH" "
SELECT Z_PK, ZPARTNERNAME, ZUNREADCOUNT, ZFLAGS, ZARCHIVED, ZHIDDEN, ZSESSIONTYPE, ZPROPERTIES
FROM ZWACHATSESSION
WHERE ZPARTNERNAME = '$CHAT_NAME'
UNION ALL
SELECT Z_PK, ZPARTNERNAME, ZUNREADCOUNT, ZFLAGS, ZARCHIVED, ZHIDDEN, ZSESSIONTYPE, ZPROPERTIES
FROM ZWACHATSESSION
WHERE ZUNREADCOUNT = 0 AND ZSESSIONTYPE = 1
LIMIT 6;
"

echo ""
echo "--- 5. Check ZPROPERTIES blob for '$CHAT_NAME' (hex dump) ---"
echo ""
/usr/bin/sqlite3 "$DB_PATH" "
SELECT hex(ZPROPERTIES)
FROM ZWACHATSESSION
WHERE ZPARTNERNAME = '$CHAT_NAME';
"

echo ""
echo "--- 6. Check if there's a ZMARKEDASUNREAD or similar column ---"
echo ""
/usr/bin/sqlite3 "$DB_PATH" "PRAGMA table_info(ZWACHATSESSION);" | grep -i -E "unread|mark|badge|flag"

echo ""
echo "--- 7. Last few messages in this chat (status & flags) ---"
echo ""
/usr/bin/sqlite3 -header -column "$DB_PATH" "
SELECT m.Z_PK, m.ZISFROMME, m.ZMESSAGESTATUS, m.ZMESSAGETYPE, m.ZFLAGS,
       datetime(m.ZMESSAGEDATE + 978307200, 'unixepoch', 'localtime') AS Time,
       SUBSTR(COALESCE(m.ZTEXT, '[non-text]'), 1, 40) AS TextPreview
FROM ZWAMESSAGE m
JOIN ZWACHATSESSION c ON m.ZCHATSESSION = c.Z_PK
WHERE c.ZPARTNERNAME = '$CHAT_NAME'
ORDER BY m.ZMESSAGEDATE DESC
LIMIT 10;
"

echo ""
echo "--- 8. ZWACHATSESSION numeric fields comparison ---"
echo "    (marked-as-unread chat vs normal chats with ZUNREADCOUNT=0)"
echo ""
/usr/bin/sqlite3 -header -csv "$DB_PATH" "
SELECT
    c.Z_PK,
    c.ZPARTNERNAME,
    c.ZUNREADCOUNT,
    c.ZFLAGS,
    c.ZARCHIVED,
    c.ZHIDDEN,
    c.ZSESSIONTYPE,
    c.ZREMOVED,
    c.ZSPOTLIGHTSTATUS,
    c.ZLASTMESSAGEDATE,
    c.ZLASTMESSAGERECVDATE,
    length(c.ZPROPERTIES) AS PropertiesLen
FROM ZWACHATSESSION c
WHERE c.ZPARTNERNAME = '$CHAT_NAME'
   OR (c.ZSESSIONTYPE = 1 AND c.ZUNREADCOUNT = 0 AND c.ZPARTNERNAME IS NOT NULL)
ORDER BY (c.ZPARTNERNAME = '$CHAT_NAME') DESC
LIMIT 6;
"

echo ""
echo "--- 9. Check ZWACHATPROPERTIES or similar tables ---"
echo ""
/usr/bin/sqlite3 "$DB_PATH" "
SELECT name FROM sqlite_master
WHERE type='table'
ORDER BY name;
" | grep -i -E "prop|flag|state|pref|setting|config|mark|unread"

echo ""
echo "--- 10. Full table list (for manual inspection) ---"
echo ""
/usr/bin/sqlite3 "$DB_PATH" "
SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
"
