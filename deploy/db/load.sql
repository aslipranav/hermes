CREATE DATABASE ebms;
CREATE USER 'corvus'@'%' IDENTIFIED BY 'corvus';
GRANT ALL ON ebms.* TO 'corvus'@'%';
USE ebms;
SOURCE /build/ebms.sql

CREATE DATABASE as2;
GRANT ALL ON as2.* TO 'corvus'@'%';
USE as2;
SOURCE /build/as2.sql
