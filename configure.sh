#!/bin/bash

# Postfix configuration
cat > /etc/postfix/mysql-virtual-mailbox-domains.cf <<EOF
user = $MYSQL_USER
password = $MYSQL_PASSWORD
hosts = $MYSQL_HOST
dbname = $MYSQL_DB
query = SELECT 1 FROM virtual_domains WHERE name='%s'
EOF
postconf virtual_mailbox_domains=mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf

cat > /etc/postfix/mysql-virtual-mailbox-maps.cf <<EOF
user = $MYSQL_USER
password = $MYSQL_PASSWORD
hosts = $MYSQL_HOST
dbname = $MYSQL_DB
query = SELECT 1 FROM virtual_users WHERE email='%s'
EOF
postconf virtual_mailbox_maps=mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf

cat > /etc/postfix/mysql-virtual-alias-maps.cf <<EOF
user = $MYSQL_USER
password = $MYSQL_PASSWORD
hosts = $MYSQL_HOST
dbname = $MYSQL_DB
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOF
cat > /etc/postfix/mysql-email2email.cf <<EOF
user = $MYSQL_USER
password = $MYSQL_PASSWORD
hosts = $MYSQL_HOST
dbname = $MYSQL_DB
query = SELECT email FROM virtual_users WHERE email='%s'
EOF
postconf virtual_alias_maps=mysql:/etc/postfix/mysql-virtual-alias-maps.cf,mysql:/etc/postfix/mysql-email2email.cf

chgrp postfix /etc/postfix/mysql-*.cf
chmod u=rw,g=r,o= /etc/postfix/mysql-*.cf

postconf -vM dovecot/unix='dovecot unix - n n - - pipe flags=DRhu user=vmail:vmail argv=/usr/lib/dovecot/dovecot-lda -f ${sender} -d ${recipient}'
postconf virtual_transport=dovecot
postconf dovecot_destination_recipient_limit=1
postconf myhostname=$HOSTNAME
postconf mydestination=localhost

# Use Dovecot authentication
postconf smtpd_sasl_type=dovecot
postconf smtpd_sasl_path=private/auth
postconf smtpd_sasl_auth_enable=yes

# Enable encryption
postconf smtpd_tls_security_level=may
postconf smtpd_tls_auth_only=yes
postconf smtpd_tls_cert_file=/etc/certs/mailserver.crt
postconf smtpd_tls_key_file=/etc/certs/mailserver.key

# Dovecot configuration
# 10-auth.conf
sed -i 's/!include auth-system.conf.ext/#!include auth-system.conf.ext/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/#!include auth-sql.conf.ext/!include auth-sql.conf.ext/' /etc/dovecot/conf.d/10-auth.conf

# auth-sql.conf.ext
cat > /etc/dovecot/conf.d/auth-sql.conf.ext <<EOF
# Authentication for SQL users. Included from 10-auth.conf.
#
# <doc/wiki/AuthDatabase.SQL.txt>

passdb {
  driver = sql

  # Path for SQL configuration file, see example-config/dovecot-sql.conf.ext
  args = /etc/dovecot/dovecot-sql.conf.ext
}

# "prefetch" user database means that the passdb already provided the
# needed information and there's no need to do a separate userdb lookup.
# <doc/wiki/UserDatabase.Prefetch.txt>
#userdb {
#  driver = prefetch
#}

#userdb {
  #driver = sql
  #args = /etc/dovecot/dovecot-sql.conf.ext
#}

# If you don't have any user-specific settings, you can avoid the user_query
# by using userdb static instead of userdb sql, for example:
# <doc/wiki/UserDatabase.Static.txt>
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/vmail/%d/%n
}
EOF

# 10-mail.conf
sed -i 's!mail_location = mbox:~/mail:INBOX=/var/mail/%u!mail_location = maildir:/var/vmail/%d/%n/Maildir!' /etc/dovecot/conf.d/10-mail.conf

# 10-master.conf
perl -pni -e 'BEGIN{undef $/;} s|  #unix_listener /var/spool/postfix/private/auth \{\n  #  mode = 0666\n  #\}|  unix_listener /var/spool/postfix/private/auth \{\n    mode = 0660\n    user = postfix\n    group = postfix\n  \}|' /etc/dovecot/conf.d/10-master.conf

# 10-ssl.conf
sed -i 's/ssl = no/ssl = yes/' /etc/dovecot/conf.d/10-ssl.conf
sed -i 's!#ssl_cert = </etc/dovecot/dovecot.pem!ssl_cert = </etc/certs/mailserver.crt!' /etc/dovecot/conf.d/10-ssl.conf
sed -i 's!#ssl_key = </etc/dovecot/private/dovecot.pem!ssl_key = </etc/certs/mailserver.key!' /etc/dovecot/conf.d/10-ssl.conf

# 15-lda.conf
sed -i 's/#mail_plugins = $mail_plugins/mail_plugins = $mail_plugins sieve/' /etc/dovecot/conf.d/15-lda.conf
sed -i 's/#postmaster_address =/postmaster_address = postmaster@%d/' /etc/dovecot/conf.d/15-lda.conf
#postmaster_address =

# 15-mailboxes.conf
perl -pni -e 'BEGIN{undef $/;} s|  mailbox Junk \{\n    special_use = \\Junk\n  \}|  mailbox Junk \{\n    auto = subscribe\n    special_use = \\Junk\n  \}|' /etc/dovecot/conf.d/15-mailboxes.conf
perl -pni -e 'BEGIN{undef $/;} s|  mailbox Trash \{\n    special_use = \\Trash\n  \}|  mailbox Trash \{\n    auto = subscribe\n    special_use = \\Trash\n  \}|' /etc/dovecot/conf.d/15-mailboxes.conf

# dovecot-sql.conf.ext
cat >> /etc/dovecot/dovecot-sql.conf.ext <<EOF
driver = mysql
connect = host=$MYSQL_HOST dbname=$MYSQL_DB user=$MYSQL_USER password=$MYSQL_PASSWORD
default_pass_scheme = SHA256-CRYPT
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u';
EOF

chown root:root /etc/dovecot/dovecot-sql.conf.ext
chmod go= /etc/dovecot/dovecot-sql.conf.ext

# SpamAssassin
# Fix Debian bug #739738
sed -i '288s/return if !defined $_[0];/return undef if !defined $_[0];/' /usr/share/perl5/Mail/SpamAssassin/Util.pm

# Enable SpamAssassin in Postfix
postconf smtpd_milters=unix:/spamass/spamass.sock
postconf milter_connect_macros="i j {daemon_name} v {if_name} _"

# /etc/default/spamassassin
sed -i 's/OPTIONS="--create-prefs --max-children 5 --helper-home-dir"/OPTIONS="--create-prefs --max-children 5 --helper-home-dir -x -u vmail"/' /etc/default/spamassassin
sed -i 's/CRON=0/CRON=1/' /etc/default/spamassassin
sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/spamassassin

# Sending spam to the Junk folder
sed -i 's|  #sieve_after =|  sieve_after = /etc/dovecot/sieve-after|' /etc/dovecot/conf.d/90-sieve.conf
mkdir /etc/dovecot/sieve-after
cat > /etc/dovecot/sieve-after/spam-to-folder.sieve <<EOF
require ["fileinto"];

if header :contains "X-Spam-Flag" "YES" {
 fileinto "Junk";
}
EOF
sievec /etc/dovecot/sieve-after/spam-to-folder.sieve
chown -R vmail:vmail /etc/dovecot/sieve-after
