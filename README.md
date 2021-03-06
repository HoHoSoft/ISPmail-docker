# ISPmail-docker
A docker container created from the ISPmail tutorial (https://workaround.org/ispmail/jessie).

## Differences from ISPmail Tutorial

* Junk and Trash folder are next to Inbox instead of subfolders.

## Configuring docker-compose.yml

There is a `docker-compose.yml.example` file with an example configuration:
```
mailserver:
  build: .
#  external_links:
#    - "mysql_db_1:db"
  links:
    - "db:db"
  environment:
    MYSQL_HOST: db
    MYSQL_DB: mailserver
    MYSQL_USER: mailserver
    MYSQL_PASSWORD: password
  volumes:
    - ./certs:/etc/certs
    - ./vmail:/var/vmail
  ports:
    - "143:143"
    - "25:25"
  hostname: mail.example.org
db:
  image: mysql:5.7
  volumes:
    - ./init_mailserver_db.sql:/docker-entrypoint-initdb.d/init_mailserver_db.sql
    - ./mysql/data:/var/lib/mysql
  environment:
    MYSQL_ROOT_PASSWORD: my-secret-pw
	MYSQL_DATABASE: mailserver
    MYSQL_USER: mailserver
    MYSQL_PASSWORD: password
  ports:
    - "3306:3306"
```
You can copy and adjust it to your needs.

## Future Work
* A container for Roundcube
* A container for managing mail users and domains
