#!/bin/bash

chown -R vmail:vmail /var/vmail

/configure.sh

service rsyslog start
service postfix start
service dovecot restart
systemctl enable spamassassin
service spamassassin start
service spamass-milter start

tail -f /var/log/mail.log
