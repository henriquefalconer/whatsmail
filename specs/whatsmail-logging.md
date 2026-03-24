# WhatsMail Logging

## Apple Unified Logging (AUL)

### 1. Send Logs

```bash
/usr/bin/logger -t WhatsMail "Message here"
```

### 2. View Logs

```bash
/usr/bin/log [show|stream] --predicate 'eventMessage contains "whatsmail"' --info --debug
```
