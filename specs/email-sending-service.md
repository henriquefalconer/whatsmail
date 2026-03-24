# CLI Email Spec

## 1. Setup

```bash
brew install msmtp
touch ~/.msmtprc && chmod 600 ~/.msmtprc
```

## 2. Config (~/.msmtprc.example)

```
account default
host           smtp.example.com
port           587
tls            on
auth           on
from           "Sender Name" <sender@example.com>
password       YOUR_SMTP_KEY
user           username@example.com.br
```

## 3. Use

```bash
printf "Subject: Alert\n\nText" | msmtp --file=.msmtp.rc -t recipient@example.com
```

## 4. Debug

```bash
printf "Subject: Alert\n\nText" | msmtp --pretend --debug --file=.msmtp.rc -t recipient@example.com
```
