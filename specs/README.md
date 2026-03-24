# WhatsMail Specifications

Design documentation for WhatsMail, a tool that forwards unread WhatsApp messages as email notifications.

## Data Source

| Spec | Purpose |
|------|---------|
| [whatsapp-db-interface.md](./whatsapp-db-interface.md) | WhatsApp macOS local SQLite database schema, unread message detection, sender resolution |

## Email Delivery

| Spec | Purpose |
|------|---------|
| [email-sending-service.md](./email-sending-service.md) | CLI email sending via msmtp with SMTP/TLS configuration |

## Bridge

| Spec | Purpose |
|------|---------|
| [whatsmail-bridge.md](./whatsmail-bridge.md) | Bash script that bundles unread WhatsApp messages into a daily email digest |

## Logging

| Spec | Purpose |
|------|---------|
| [whatsmail-logging.md](./whatsmail-logging.md) | Apple Unified Logging via `logger` for diagnostics |
