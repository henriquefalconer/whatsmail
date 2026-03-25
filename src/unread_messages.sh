#!/bin/bash

DB_PATH=~/Library/Group\ Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite

if [ ! -f "$DB_PATH" ]; then
    /usr/bin/logger -t WhatsMail "[local.whatsmail] ERROR: WhatsApp Chat database not found: $DB_PATH"
    exit 1
fi

CV_PATH=~/Library/Group\ Containers/group.net.whatsapp.WhatsApp.shared/ContactsV2.sqlite

if [ ! -f "$CV_PATH" ]; then
    /usr/bin/logger -t WhatsMail "[local.whatsmail] ERROR: WhatsApp Contacts database not found: $CV_PATH"
    exit 1
fi

QUERY_RESULT=$(/usr/bin/sqlite3 "$DB_PATH" "
ATTACH DATABASE '$CV_PATH' AS cv;
SELECT
    sub.Z_PK AS MsgID,
    sub.Time,
    sub.Chat,
    sub.ChatJID,
    REPLACE(REPLACE(
        CASE
            WHEN sub.ZISFROMME = 1 THEN 'You'
            ELSE COALESCE(
                NULLIF(gm.ZCONTACTNAME, ''),
                NULLIF(sc2.ZPARTNERNAME, ''),
                NULLIF(sc.ZPARTNERNAME, ''),
                NULLIF(pn.ZPUSHNAME, ''),
                NULLIF(gpn.ZPUSHNAME, ''),
                NULLIF(sub.Chat, 'Unknown Chat'),
                REPLACE(REPLACE(REPLACE(COALESCE(gm.ZMEMBERJID, sub.ZFROMJID),'@s.whatsapp.net',''),'@g.us',''),'@lid',''),
                'Unknown Sender'
            )
        END,
        CHAR(10), '<NL>'), '|', '<PIP>'
    ) AS Sender,
    sub.IsGroup,
    sub.Content,
    COALESCE(
        (SELECT pp.ZPATH FROM ZWAPROFILEPICTUREITEM pp
         WHERE pp.ZJID = sub.RawChatJID AND pp.ZPATH LIKE 'Media/Profile/%'
         ORDER BY pp.ZREQUESTDATE DESC LIMIT 1),
        ''
    ) AS ProfilePicPath,
    sub.RawChatJID,
    sub.ZMESSAGESTATUS AS Status
FROM (
    SELECT
        m.Z_PK,
        datetime(m.ZMESSAGEDATE + 978307200, 'unixepoch', 'localtime') AS Time,
        REPLACE(REPLACE(COALESCE(c.ZPARTNERNAME, 'Unknown Chat'), CHAR(10), '<NL>'), '|', '<PIP>') AS Chat,
        CASE
            WHEN c.ZCONTACTJID LIKE '%@lid' AND c.ZPARTNERNAME LIKE '+%'
            THEN REPLACE(REPLACE(REPLACE(REPLACE(c.ZPARTNERNAME, '+', ''), ' ', ''), '-', ''), '(', '')
            WHEN c.ZCONTACTJID LIKE '%@lid'
            THEN ''
            ELSE REPLACE(REPLACE(c.ZCONTACTJID, '@s.whatsapp.net', ''), '@g.us', '')
        END AS ChatJID,
        c.ZCONTACTJID AS RawChatJID,
        m.ZISFROMME,
        m.ZFROMJID,
        m.ZGROUPMEMBER,
        m.ZSTANZAID,
        m.ZMESSAGEDATE,
        m.ZMESSAGESTATUS,
        m.ZCHATSESSION,
        CASE WHEN c.ZSESSIONTYPE = 1 THEN 1 ELSE 0 END AS IsGroup,
        REPLACE(REPLACE(COALESCE(m.ZTEXT, '[Media or non-text message]'), CHAR(10), '<NL>'), '|', '<PIP>') AS Content,
        ROW_NUMBER() OVER (PARTITION BY m.ZCHATSESSION ORDER BY m.ZMESSAGEDATE DESC) AS rn,
        c.ZUNREADCOUNT
    FROM ZWAMESSAGE m
    JOIN ZWACHATSESSION c ON m.ZCHATSESSION = c.Z_PK
    WHERE
        m.ZISFROMME = 0
        AND c.ZUNREADCOUNT != 0
        AND m.ZMESSAGETYPE != 10
        AND c.ZSESSIONTYPE != 3
) sub
LEFT JOIN ZWAPROFILEPUSHNAME pn ON sub.ZFROMJID = pn.ZJID
LEFT JOIN ZWAGROUPMEMBER gm ON sub.ZGROUPMEMBER = gm.Z_PK
LEFT JOIN ZWAPROFILEPUSHNAME gpn ON gm.ZMEMBERJID = gpn.ZJID
LEFT JOIN ZWACHATSESSION sc ON COALESCE(gm.ZMEMBERJID, sub.ZFROMJID) = sc.ZCONTACTJID
LEFT JOIN cv.ZWAADDRESSBOOKCONTACT abc ON gm.ZMEMBERJID = abc.ZLID
LEFT JOIN ZWACHATSESSION sc2 ON abc.ZWHATSAPPID = sc2.ZCONTACTJID
WHERE sub.rn <= CASE WHEN sub.ZUNREADCOUNT = -1 THEN 1 ELSE sub.ZUNREADCOUNT END
GROUP BY sub.ZCHATSESSION, sub.ZSTANZAID
ORDER BY MAX(sub.ZMESSAGEDATE) OVER (PARTITION BY sub.ZCHATSESSION) DESC, sub.ZMESSAGEDATE ASC;
" 2>&1)
QUERY_EXIT_CODE=$?

if [ $QUERY_EXIT_CODE -ne 0 ]; then
    /usr/bin/logger -t WhatsMail "[local.whatsmail] SQLITE ERROR: $QUERY_RESULT"
    exit 1
fi

echo "$QUERY_RESULT"
