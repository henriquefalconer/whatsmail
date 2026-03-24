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

# Format: group by chat, with dividers and indented content
BODY=""
CURRENT_CHAT=""

while IFS='|' read -r _msgid time chat chatjid sender _isgroup content _status; do
    if [ "$chat" != "$CURRENT_CHAT" ]; then
        if [ -n "$CURRENT_CHAT" ]; then
            BODY+=$'\n'
        fi
        BODY+="========================================"$'\n'
        BODY+="${chat}"$'\n'
        if [ "$_isgroup" = "1" ] || [ -z "$chatjid" ]; then
            BODY+="[Open in WhatsApp to access]"$'\n'
        else
            BODY+="https://wa.me/${chatjid}"$'\n'
        fi
        BODY+="========================================"$'\n'
        CURRENT_CHAT="$chat"
    else
        BODY+=$'\n'
    fi
    time="${time%:*}"
    content="${content//<NL>/$'\n'  }"
    BODY+=$'\n'"[${time}] ${sender}"$'\n'
    BODY+="  ${content}"$'\n'
done <<< "$DATA"

MSG_COUNT=$(echo "$DATA" | wc -l | tr -d ' ')
DATE=$(date +%d/%m/%Y)
if [ "$MSG_COUNT" = "1" ]; then
    SUBJECT="Subject: (${DATE}) 1 unread message"
else
    SUBJECT="Subject: (${DATE}) ${MSG_COUNT} unread messages"
fi

printf "%s\nContent-Type: text/plain; charset=UTF-8\n\n%s" "$SUBJECT" "$BODY" | msmtp --file="$MSMTP_CONFIG" "$TO"
echo "Alert sent to $TO."
