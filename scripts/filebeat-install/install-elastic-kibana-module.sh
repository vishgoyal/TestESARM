#!/bin/bash


export DEBIAN_FRONTEND=noninteractive

help()
{
    echo "This script installs filebeat service on Ubuntu and configures it"
    echo ""
    echo "Options:"
    echo "    -A      bootstrap password" 
    echo "    -T      base64 encoded PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the transport layer"
    echo "    -W      password for PKCS#12 archive (.p12/.pfx) containing the CA key and certificate used to secure the transport layer"

    echo "    -h      view this help content"
}

# Custom logging with time so we can easily relate running times, also log to separate file so order is guaranteed.
# The Script extension output the stdout/err buffer in intervals with duplicates.
log()
{
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1"
    echo \[$(date +%d%m%Y-%H:%M:%S)\] "$1" >> /var/log/arm-install.log
}

SSL_PATH=/etc/elasticsearch/ssl
TRANSPORT_CACERT_PEM_FILENAME=elasticsearch-transport-ca.pem
TRANSPORT_CACERT_FILENAME=elasticsearch-transport-ca.p12
TRANSPORT_CACERT_PEM_PATH=$SSL_PATH/$TRANSPORT_CACERT_PEM_FILENAME
TRANSPORT_CACERT_PATH=$SSL_PATH/$TRANSPORT_CACERT_FILENAME
TRANSPORT_CACERT=""
TRANSPORT_CACERT_PASSWORD=""

#Loop through options passed
while getopts :n:m:v:A:R:M:K:S:F:Z:p:a:k:L:C:B:E:H:G:T:W:V:J:N:D:O:P:xyzldjh optname; do
  log "Option $optname set"
  case $optname in
    B) #bootstrap password
      BOOTSTRAP_PASSWORD="${OPTARG}"
      log "$BOOTSTRAP_PASSWORD"
      ;;
    T) #Transport CA cert blob
      TRANSPORT_CACERT="${OPTARG}"
      log "$TRANSPORT_CACERT"
      ;;
    W) #Transport CA cert password
      TRANSPORT_CACERT_PASSWORD="${OPTARG}"
      log "$TRANSPORT_CACERT_PASSWORD"
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

log "Install filebeat deb package"
curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-7.3.0-amd64.deb
sudo dpkg -i filebeat-7.3.0-amd64.deb

log "Enable modules and copy configs"
sed -i "s/password_string_to_replace/$BOOTSTRAP_PASSWORD/g" filebeat.yml
cp filebeat.yml /etc/filebeat/
hostname=$(hostname)
if [[ $hostname == *"data"* ]]; then
    filebeat modules enable elasticsearch
    cp elasticsearch.yml /etc/filebeat/modules.d/ 
else
    echo "$(hostname -I)kibana" >> /etc/hosts
    filebeat modules enable kibana
    cp kibana.yml /etc/filebeat/modules.d/
fi

if [ ! -f "$TRANSPORT_CACERT_PATH" ]; then
    log "Saving CA cert to file system"
    mkdir -p /etc/elasticsearch/ssl
    echo ${TRANSPORT_CACERT} | base64 -d | tee $TRANSPORT_CACERT_PATH
fi

log "converting CA certificate to pfx"
echo "$TRANSPORT_CACERT_PASSWORD" | openssl pkcs12 -in $TRANSPORT_CACERT_PATH -out $TRANSPORT_CACERT_PEM_PATH -nodes -passin stdin

log "Setup and start filebeat"
filebeat setup -e
# this needs offloading to a later time, as kibana is not ready when this is running
# filebeat setup --dashboards 
service filebeat start
