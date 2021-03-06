#! /bin/bash
set -e 
VERSION_RANCHER=v1.6.14
UPDATE=false
DB_USER=rancher
DB_PASSWORD=R1nch3r
DB_ROOT_PWD=R0Ot47TR.98?ko
DOMAIN_URI=admin.domain.fr
AUTO_CERT=true

if [ -n "$1" ]; then 
  VERSION_RANCHER=$1;
fi

if [ -n "$2" ]; then
  UPDATE=$2;
fi

if [ -n "$3" ]; then
  DB_USER=$3;
fi

if [ -n "$4" ]; then
  DB_PASSWORD=$4;
fi

if [ -n "$5" ]; then
  DB_ROOT_PWD=$5;
fi

if [ -n "$6" ]; then
  DOMAIN_URI=$6;
fi

if [ -n "$7" ]; then
  AUTO_CERT=$7;
fi

#Installation de let'sencrypt et generation des certificats
if [ $AUTO_CERT = true ]; then
  echo "=============================================================\n"
  echo " Installation de let's encrypt et génération des certificats\n"
  echo "============================================================="
  ../../letsencrypt/installLetsencrypt.sh "contact@lixtec.fr" $DOMAIN_URI
  rm -rf ./haproxy
  mkdir haproxy
  cat /etc/letsencrypt/live/$DOMAIN_URI/cert.pem > haproxy/certificate.pem
  cat /etc/letsencrypt/live/$DOMAIN_URI/privkey.pem >> haproxy/certificate.pem
fi

#Purge des images et des conteneurs presents. Sauvegarde des volumes.
if [ $UPDATE = true ]; then
  echo "================================\n"
  echo " Purge des conteneurs existants\n"
  echo "================================"
  docker rm -f $(docker ps -a -q);
fi

echo "======================================\n"
echo " Configuration de RANCHER $VERSION_RANCHER\n"
echo "======================================"
#Installation DB
docker run --name rancher-db-$VERSION_RANCHER --restart=always -d -v /var/docker/volume/rancher-db:/var/lib/mysql -v /var/docker/logs/rancher-db:/var/log/mysql -e MYSQL_USER="$DB_USER" -e MYSQL_PASSWORD="$DB_PASSWORD" -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PWD" -e MYSQL_DATABASE="rancher" mysql:5.7 
sleep 30

#Installation APP
docker run --name rancher-app-$VERSION_RANCHER --restart=always -d --link rancher-db-$VERSION_RANCHER -v /var/docker/logs/rancher-app:/var/lib/cattle/logs -v /etc/ssl:/etc/ssl -e CATTLE_DB_CATTLE_MYSQL_HOST="rancher-db-$VERSION_RANCHER" -e CATTLE_DB_CATTLE_MYSQL_PORT=3306 -e CATTLE_DB_CATTLE_MYSQL_NAME="rancher" -e CATTLE_DB_CATTLE_USERNAME="$DB_USER" -e CATTLE_DB_CATTLE_PASSWORD="$DB_PASSWORD" -p 9080:8080 rancher/server:$VERSION_RANCHER


echo "========================\n"
echo " Configuration du proxy\n"
echo "========================"
#Installation PROXY
rm -rf /var/docker/volume/rancher-proxy &&\
mkdir /var/docker/volume/rancher-proxy &&\
rm -rf haproxy.cfg &&\
echo ' global' >> haproxy.cfg &&\
echo '   maxconn 4096' >> haproxy.cfg &&\
echo '   ssl-server-verify none' >> haproxy.cfg &&\
echo '   tune.ssl.default-dh-param 2048' >> haproxy.cfg &&\
echo '   ssl-default-bind-ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE$' >> haproxy.cfg &&\
echo '   ssl-default-server-ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECD$' >> haproxy.cfg &&\
echo '   ssl-default-bind-options no-sslv3 no-tlsv10' >> haproxy.cfg &&\
echo ' ' >> haproxy.cfg &&\
echo ' defaults' >> haproxy.cfg &&\
echo '   log global' >> haproxy.cfg &&\
echo '   mode tcp' >> haproxy.cfg &&\
echo '   option tcplog' >> haproxy.cfg &&\
echo '   option dontlognull' >> haproxy.cfg &&\
echo '   option redispatch' >> haproxy.cfg &&\
echo '   option http-server-close' >> haproxy.cfg &&\
echo '   option forwardfor' >> haproxy.cfg &&\
echo '   retries 3' >> haproxy.cfg &&\
echo '   timeout connect 5000' >> haproxy.cfg &&\
echo '   timeout client 50000' >> haproxy.cfg &&\
echo '   timeout server 50000' >> haproxy.cfg &&\
echo ' ' >> haproxy.cfg &&\
echo ' frontend http-in' >> haproxy.cfg &&\
echo '   bind *:443 ssl crt /usr/local/etc/haproxy/certificate.pem' >> haproxy.cfg &&\
echo '   mode http' >> haproxy.cfg &&\
echo ' ' >> haproxy.cfg &&\
echo "     acl 0_host hdr(host) -i $DOMAIN_URI" >> haproxy.cfg &&\
echo "     acl 0_host hdr(host) -i $DOMAIN_URI:443" >> haproxy.cfg &&\
echo '   use_backend rancher_server if 0_host' >> haproxy.cfg &&\
echo ' ' >> haproxy.cfg &&\
echo ' backend rancher_server' >> haproxy.cfg &&\
echo '   mode http' >> haproxy.cfg &&\
echo "   server rancher-app-$VERSION_RANCHER rancher-app-$VERSION_RANCHER:8080" >> haproxy.cfg &&\
echo '   http-request add-header X-Forwarded-Proto https if { ssl_fc }' >> haproxy.cfg &&\
echo '   http-request set-header X-Forwarded-Port %[dst_port]' >> haproxy.cfg &&\
cp  haproxy.cfg /var/docker/volume/rancher-proxy
cp ./haproxy/* /var/docker/volume/rancher-proxy || echo ''

docker run --name rancher-proxy-$VERSION_RANCHER --restart=always -d --link rancher-app-$VERSION_RANCHER -v /var/docker/volume/rancher-proxy:/usr/local/etc/haproxy:ro -p80:80 -p443:443 haproxy:1.7
