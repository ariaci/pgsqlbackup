FROM postgres:16

COPY tmp/pgsqlbackup.sh /sbin/pgsqlbackup.sh
COPY tmp/pgsqlbackup_getcfg.sh /sbin/getcfg

RUN mkdir /etc/config
COPY tmp/pgsqlbackup.conf /etc/config/pgsqlbackup.conf

ENV TZ=Europe/Berlin

VOLUME /var/lib/postgresql/backup

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/sbin/pgsqlbackup.sh"]
