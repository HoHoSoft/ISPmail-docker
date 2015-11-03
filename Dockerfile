FROM debian:jessie

RUN apt-get -y update && apt-get -y upgrade
run echo "postfix postfix/main_mailer_type string Internet site" > preseed.txt
run echo "postfix postfix/mailname string mail.example.com" >> preseed.txt
run debconf-set-selections preseed.txt
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    dovecot-imapd \
    dovecot-managesieved \
    dovecot-mysql \
    postfix \
    postfix-mysql \
    rsyslog \
    spamassassin \
    spamass-milter

RUN groupadd -g 5000 vmail
RUN useradd -g vmail -u 5000 vmail -d /var/vmail -m
RUN adduser spamass-milter debian-spamd

ADD ./configure.sh /
ADD ./start.sh /
RUN chmod +x /configure.sh /start.sh

#RUN ln -sf /dev/stdout /var/log/mail.log

VOLUME /var/mail

EXPOSE 143 25

CMD ["/start.sh"]
