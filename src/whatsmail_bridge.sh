#!/bin/bash

# WhatsMail Bridge
# Sends unread WhatsApp messages as an email alert.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { /usr/bin/logger -t WhatsMail "[local.whatsmail] $1"; }

cleanup() {
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        log "ERROR: Script exited unexpectedly with code $EXIT_CODE"
    fi
    log "Bridge finished (exit $EXIT_CODE)"
}
trap cleanup EXIT

# Settings
MSMTP_CONFIG="${WHATSMAIL_MSMTP_CONFIG:-}"
if [ -z "$MSMTP_CONFIG" ]; then
    log "ERROR: WHATSMAIL_MSMTP_CONFIG not set"
    exit 1
fi
if [ ! -f "$MSMTP_CONFIG" ]; then
    log "ERROR: WHATSMAIL_MSMTP_CONFIG file not found: $MSMTP_CONFIG"
    exit 1
fi

TO="${WHATSMAIL_TO:-}"
if [ -z "$TO" ]; then
    log "ERROR: WHATSMAIL_TO not set"
    exit 1
fi
if [[ ! "$TO" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    log "ERROR: WHATSMAIL_TO is not a valid email address: $TO"
    exit 1
fi

log "Starting bridge"

# MsgID|Time|Chat|ChatJID|Sender|IsGroup|Content|ProfilePicPath|Status
log "Fetching unread messages..."
if type fetch_unread_logic &>/dev/null; then
    DATA=$(fetch_unread_logic)
else
    DATA=$(bash "$SCRIPT_DIR/unread_messages.sh")
fi
if [ $? -ne 0 ]; then
    log "ERROR: sqlite3 query failed"
    exit 1
fi

if [ -z "$DATA" ]; then
    log "No unread messages found"
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

# WhatsApp container base path
WA_BASE=~/Library/Group\ Containers/group.net.whatsapp.WhatsApp.shared
KV_DB="$WA_BASE/LocalKeyValue.sqlite"
CV_DB="$WA_BASE/ContactsV2.sqlite"
SPOTLIGHT_CACHE=~/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches/spotlight-profile-v2

# Border color used for vertical bar, rectangles, and pill buttons
BC='#c8c8c8'

# CID image attachment tracking (stored in arrays, no temp files)
CID_COUNT=0
declare -a CID_B64S=()
declare -a CID_MIMES=()
AVATAR_RESULT=""

# Register an image file as a CID attachment. Sets AVATAR_RESULT to an <img> tag.
# Returns 0 on success, 1 on failure.
_avatar_from_file() {
    [ -s "$1" ] || return 1
    local b64
    b64=$(base64 -b 76 -i "$1" 2>/dev/null) || return 1
    [ -z "$b64" ] && return 1
    local ext="${1##*.}"
    local mime="image/jpeg"
    [[ "$ext" == "png" ]] && mime="image/png"
    local cid="avatar${CID_COUNT}@whatsmail"
    CID_B64S+=("$b64")
    CID_MIMES+=("$mime")
    CID_COUNT=$((CID_COUNT + 1))
    AVATAR_RESULT='<img src="cid:'"$cid"'" style="width:32px;height:32px;border-radius:50%;object-fit:cover;" />'
}

# Register a pp blob from LocalKeyValue.sqlite as a CID attachment. Sets AVATAR_RESULT.
# Returns 0 on success, 1 on failure.
_avatar_from_pp() {
    local jid="$1"
    local b64
    b64=$(/usr/bin/sqlite3 "$KV_DB" "SELECT hex(ZVALUE) FROM ZWAKEYVALUEELEMENT WHERE ZKEY = '$jid' AND ZNAMESPACE = 'pp' LIMIT 1;" 2>/dev/null | xxd -r -p | base64 -b 76)
    [ -z "$b64" ] && return 1
    local cid="avatar${CID_COUNT}@whatsmail"
    CID_B64S+=("$b64")
    CID_MIMES+=("image/jpeg")
    CID_COUNT=$((CID_COUNT + 1))
    AVATAR_RESULT='<img src="cid:'"$cid"'" style="width:32px;height:32px;border-radius:50%;object-fit:cover;" />'
}

# Build an avatar HTML element using the lookup chain. Sets AVATAR_RESULT.
# L1: ZWAPROFILEPICTUREITEM Media/Profile/ file (from SQL pic_path)
# L2b: pp blob by LID (looked up from ContactsV2)
# L2a: pp blob by raw chat JID
# L3: disk glob Media/Profile/<phone>-<timestamp> (personal only)
# L4: default WhatsApp silhouette (group or personal)
# Args: $1=ProfilePicPath (from SQL), $2=ChatJID (phone number, may be empty), $3=RawChatJID, $4=IsGroup
get_avatar() {
    local pic_path="$1"
    local chatjid="$2"
    local raw_jid="$3"
    local is_group="$4"
    AVATAR_RESULT='<div style="width:32px;height:32px;border-radius:50%;background-color:#a0a0a0;"></div>'

    # L1: DB profile picture file
    if [ -n "$pic_path" ]; then
        local file
        file=$(find "$WA_BASE/$pic_path"* -maxdepth 0 2>/dev/null | head -1)
        if [ -n "$file" ]; then
            _avatar_from_file "$file" && return
        fi
    fi

    # L2b: pp blob by LID (best coverage for @s.whatsapp.net chats)
    if [ -n "$raw_jid" ]; then
        local lid
        lid=$(/usr/bin/sqlite3 "$CV_DB" "SELECT ZLID FROM ZWAADDRESSBOOKCONTACT WHERE ZWHATSAPPID = '$raw_jid' LIMIT 1;" 2>/dev/null)
        if [ -n "$lid" ]; then
            _avatar_from_pp "$lid" && return
        fi
    fi

    # L2a: pp blob by raw JID
    if [ -n "$raw_jid" ]; then
        _avatar_from_pp "$raw_jid" && return
    fi

    # L3: disk glob for personal profile pics
    if [ -n "$chatjid" ]; then
        while IFS= read -r candidate; do
            local basename="${candidate##*/}"
            local after="${basename#"$chatjid"-}"
            if [[ "$after" != *-* ]]; then
                _avatar_from_file "$candidate" && return
                break
            fi
        done < <(find "$WA_BASE/Media/Profile/$chatjid-"* -maxdepth 0 2>/dev/null)
    fi

    # L4: default WhatsApp silhouette
    if [ "$is_group" = "1" ]; then
        local default_img="$SPOTLIGHT_CACHE/GroupChatRound.png"
    else
        local default_img="$SPOTLIGHT_CACHE/PersonalChatRound.png"
    fi
    if [ -f "$default_img" ]; then
        _avatar_from_file "$default_img" && return
    fi
}

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
PREV_SENDER=""

while IFS='|' read -r _msgid time chat chatjid sender _isgroup content pic_path raw_jid _status; do
    time="${time%:*}"
    chat="${chat//<PIP>/|}"
    chat="${chat//<NL>/ }"
    sender="${sender//<PIP>/|}"
    sender="${sender//<NL>/ }"
    content="${content//<PIP>/|}"
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
        PREV_SENDER=""
    fi

    # Decide whether to show timestamp (hide if <10 min from previous in same chat and same sender in groups)
    show_time=1
    if [ "$PREV_EPOCH" -gt 0 ] && [ "$cur_epoch" -gt 0 ]; then
        diff=$(( cur_epoch - PREV_EPOCH ))
        if [ "$diff" -ge 0 ] && [ "$diff" -lt 600 ]; then
            if [ "$_isgroup" = "1" ] && [ "$sender" != "$PREV_SENDER" ]; then
                show_time=1
            else
                show_time=0
            fi
        fi
    fi
    PREV_EPOCH=$cur_epoch
    PREV_SENDER="$sender"

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
        get_avatar "$pic_path" "$chatjid" "$raw_jid" "$_isgroup"
        local_avatar="$AVATAR_RESULT"
        BODY+='<tr><td>'
        BODY+='<table width="100%" cellpadding="0" cellspacing="0"><tr>'
        # Left column: avatar on top, 5px gap, then vertical line fills rest
        BODY+='<td width="32" style="vertical-align:top;background:linear-gradient('"$BC"','"$BC"') no-repeat center/2px 100%;">'
        BODY+='<div style="height:24px;background-color:#eaeaea;"></div>'
        BODY+='<div style="background-color:#eaeaea;">'"$local_avatar"'</div>'
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

log "Attempting to send email to $TO..."

BOUNDARY="whatsmail-$(date +%s)-$$"

{
    printf "%s\n" "$SUBJECT"
    printf "MIME-Version: 1.0\n"
    printf "Content-Type: multipart/related; boundary=\"%s\"\n" "$BOUNDARY"
    printf "\n--%s\n" "$BOUNDARY"
    printf "Content-Type: text/html; charset=UTF-8\n"
    printf "Content-Transfer-Encoding: 7bit\n\n"
    printf "%s\n" "$BODY"

    for i in "${!CID_B64S[@]}"; do
        printf "\n--%s\n" "$BOUNDARY"
        printf "Content-Type: %s\n" "${CID_MIMES[$i]}"
        printf "Content-Transfer-Encoding: base64\n"
        printf "Content-ID: <avatar%s@whatsmail>\n" "$i"
        printf "Content-Disposition: inline\n\n"
        printf "%s\n" "${CID_B64S[$i]}"
    done

    printf "\n--%s--\n" "$BOUNDARY"
} | msmtp --file="$MSMTP_CONFIG" "$TO"

if [ $? -ne 0 ]; then
    log "ERROR: msmtp failed. Check internet connection or .msmtp.rc"
    exit 1
fi
log "Sent $MSG_COUNT message(s) to $TO"
echo "Alert sent to $TO."
