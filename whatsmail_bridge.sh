#!/bin/bash

# WhatsMail Bridge
# Sends unread WhatsApp messages as an email alert.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Settings
MSMTP_CONFIG="$SCRIPT_DIR/.msmtp.rc"
TO="${WHATSMAIL_TO:-}"

if [ -z "$TO" ]; then
    echo "Error: set WHATSMAIL_TO to the recipient email address." >&2
    exit 1
fi

# MsgID|Time|Chat|ChatJID|Sender|IsGroup|Content|Status
DATA=$(bash "$SCRIPT_DIR/unread_messages.sh")

if [ -z "$DATA" ]; then
    echo "No unread messages found."
    exit 0
fi

# HTML helper: escape special characters
html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    echo "$s"
}

# Border color used for vertical bar, rectangles, and pill buttons
BC='#c8c8c8'

# Convert "YYYY-MM-DD HH:MM" to epoch seconds
to_epoch() {
    date -d "${1//-//}" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M" "$1" +%s 2>/dev/null || echo 0
}

# Render a row with the vertical line column
# Args: $1=inner html, $2=extra td style (optional)
vline_row() {
    local out=''
    out+='<tr><td>'
    out+='<table width="100%" cellpadding="0" cellspacing="0"><tr>'
    out+='<td width="15" style="border-right:2px solid '"$BC"';vertical-align:top;"></td>'
    out+='<td style="padding-left:25px;'"${2:+$2}"'">'"$1"'</td>'
    out+='</tr></table>'
    out+='</td></tr>'
    echo "$out"
}

# Render the "Open in WhatsApp" card for a chat
# Args: $1=chat name, $2=isgroup, $3=chatjid
render_wa_card() {
    local name_escaped
    name_escaped=$(html_escape "$1")
    local inner=''
    inner+='<table cellpadding="0" cellspacing="0" style="border:1px solid '"$BC"';border-radius:12px;margin-top:2px;margin-bottom:4px;"><tr><td style="padding:8px 8.5px;">'
    inner+='<div style="color:#000;margin-top:2px;"><b>'"$name_escaped"'</b></div>'
    if [ "$2" = "1" ] || [ -z "$3" ]; then
        inner+='<div style="margin-top:6px;margin-bottom:2px;padding-left:1px;color:#000;">Manually open in WhatsApp to access</div>'
    else
        inner+='<div style="margin-top:6px;margin-bottom:2px;"><a href="https://wa.me/'"$3"'" style="display:inline-block;border:1px solid '"$BC"';border-radius:20px;padding:4px 10px;color:#000;text-decoration:none;">Open in WhatsApp</a></div>'
    fi
    inner+='</td></tr></table>'
    echo "$(vline_row "$inner")"
}

# Build HTML email body
FONT='font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;font-size:13px;color:#000;'
BODY='<!DOCTYPE html><html><head><meta charset="UTF-8"></head><body style="margin:0;padding:0;background-color:#eaeaea;'"$FONT"'">'
BODY+='<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#eaeaea;"><tr><td align="center" style="padding:16px 10px;">'
BODY+='<table width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;">'

CURRENT_CHAT=""
CURRENT_ISGROUP=""
CURRENT_CHATJID=""
PREV_EPOCH=0

while IFS='|' read -r _msgid time chat chatjid sender _isgroup content _status; do
    time="${time%:*}"
    content="${content//<NL>/<br>}"
    chat_escaped=$(html_escape "$chat")
    sender_escaped=$(html_escape "$sender")
    content_escaped=$(html_escape "$content")
    content_escaped="${content_escaped//&lt;br&gt;/<br>}"

    cur_epoch=$(to_epoch "$time")

    NEW_CHAT=0
    if [ "$chat" != "$CURRENT_CHAT" ]; then
        NEW_CHAT=1
        # Close previous chat section
        if [ -n "$CURRENT_CHAT" ]; then
            BODY+=$(render_wa_card "$PREV_CHAT" "$CURRENT_ISGROUP" "$CURRENT_CHATJID")
            BODY+='<tr><td style="height:14px;"></td></tr>'
        fi

        PREV_CHAT="$chat"
        CURRENT_CHAT="$chat"
        CURRENT_ISGROUP="$_isgroup"
        CURRENT_CHATJID="$chatjid"
        PREV_EPOCH=0
    fi

    # Decide whether to show timestamp (hide if <10 min from previous in same chat)
    show_time=1
    if [ "$PREV_EPOCH" -gt 0 ] && [ "$cur_epoch" -gt 0 ]; then
        diff=$(( cur_epoch - PREV_EPOCH ))
        if [ "$diff" -ge 0 ] && [ "$diff" -lt 600 ]; then
            show_time=0
        fi
    fi
    PREV_EPOCH=$cur_epoch

    # Build bubble content (sender name only for group chats)
    local_bubble=''
    local_bubble+='<div style="display:inline-block;background-color:#d9d9d9;border:1px solid '"$BC"';border-radius:12px;padding:6px 8px;max-width:85%;color:#000;line-height:1.4;'"$FONT"'">'
    if [ "$show_time" = "1" ]; then
        if [ "$_isgroup" = "1" ]; then
            local_bubble+='['"$time"'] '"$sender_escaped"'<br>'"$content_escaped"
        else
            local_bubble+='['"$time"']<br>'"$content_escaped"
        fi
    else
        local_bubble+="$content_escaped"
    fi
    local_bubble+='</div>'

    if [ "$NEW_CHAT" = "1" ]; then
        # First message row: left column (avatar + gap + line) | right column (name + bubble)
        BODY+='<tr><td>'
        BODY+='<table width="100%" cellpadding="0" cellspacing="0"><tr>'
        # Left column: avatar on top, 5px gap, then vertical line fills rest
        BODY+='<td width="32" style="vertical-align:top;background:linear-gradient('"$BC"','"$BC"') no-repeat center/2px 100%;">'
        BODY+='<div style="height:24px;background-color:#eaeaea;"></div>'
        BODY+='<div style="width:32px;height:32px;border-radius:50%;background-color:#a0a0a0;"></div>'
        BODY+='<div style="height:5px;background-color:#eaeaea;"></div>'
        BODY+='</td>'
        # Right column: chat name then first bubble
        BODY+='<td style="vertical-align:top;padding-left:10px;padding-bottom:2px;">'
        BODY+='<div style="color:#000;padding-bottom:5px;">'"$chat_escaped"'</div>'
        BODY+="$local_bubble"
        BODY+='</td>'
        BODY+='</tr></table>'
        BODY+='</td></tr>'
    else
        BODY+=$(vline_row "$local_bubble" "padding-top:2px;padding-bottom:2px;")
    fi
done <<< "$DATA"

# Close last chat section
if [ -n "$CURRENT_CHAT" ]; then
    BODY+=$(render_wa_card "$CURRENT_CHAT" "$CURRENT_ISGROUP" "$CURRENT_CHATJID")
fi

BODY+='</table></td></tr></table></body></html>'

MSG_COUNT=$(echo "$DATA" | wc -l | tr -d ' ')
DATE=$(date +%d/%m/%Y)
if [ "$MSG_COUNT" = "1" ]; then
    SUBJECT="Subject: (${DATE}) 1 unread message"
else
    SUBJECT="Subject: (${DATE}) ${MSG_COUNT} unread messages"
fi

printf "%s\nContent-Type: text/html; charset=UTF-8\nMIME-Version: 1.0\n\n%s" "$SUBJECT" "$BODY" | msmtp --file="$MSMTP_CONFIG" "$TO"
echo "Alert sent to $TO."
