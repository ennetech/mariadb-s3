FROM mariadb:10.3

RUN apt-get update && apt-get install -y wget

COPY my.cnf /etc/mysql/conf.d/zz-custom.cnf

RUN chmod 644 /etc/mysql/conf.d/zz-custom.cnf

COPY auto.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/auto.sh

RUN wget https://storage.ennetech.me:9000/assets/mc -O /usr/local/bin/mc

RUN chmod +x /usr/local/bin/mc

ENTRYPOINT ["auto.sh"]
