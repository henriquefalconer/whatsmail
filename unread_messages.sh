#!/bin/bash

sqlite3 ~/Library/Group\ Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite "
SELECT
    sub.Z_PK AS MsgID,
    sub.Time,
    sub.Chat,
    sub.ChatJID,
    REPLACE(REPLACE(
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
        END,
        CHAR(10), '<NL>'), '|', '<PIP>'
    ) AS Sender,
    sub.IsGroup,
    sub.Content,
    COALESCE(pp.ZPATH, '') AS ProfilePicPath,
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
        AND c.ZUNREADCOUNT > 0
        AND m.ZMESSAGETYPE != 10
) sub
LEFT JOIN ZWAPROFILEPUSHNAME pn ON sub.ZFROMJID = pn.ZJID
LEFT JOIN ZWAGROUPMEMBER gm ON sub.ZGROUPMEMBER = gm.Z_PK
LEFT JOIN ZWAPROFILEPUSHNAME gpn ON gm.ZMEMBERJID = gpn.ZJID
LEFT JOIN ZWACHATSESSION sc ON COALESCE(gm.ZMEMBERJID, sub.ZFROMJID) = sc.ZCONTACTJID
LEFT JOIN ZWAPROFILEPICTUREITEM pp ON sub.RawChatJID = pp.ZJID AND pp.ZPATH LIKE 'Media/Profile/%'
WHERE sub.rn <= sub.ZUNREADCOUNT
GROUP BY sub.ZSTANZAID
ORDER BY MIN(sub.ZMESSAGEDATE) OVER (PARTITION BY sub.ZCHATSESSION), sub.ZMESSAGEDATE ASC;
"
