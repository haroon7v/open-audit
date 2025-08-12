#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

if eval "ruby -v"; then
  echo "verified ruby installation"
else
  echo "ruby not found. (The command 'sudo ruby -v' failed) Please install ruby to continue with the setup."
  exit
fi

agent_tag=TAG
assetsonar_url=URL
connector_file=connector.tar.gz
config_file=/var/lib/assetsonar-connector/config.ini

rm -rf /opt/assetsonar-connector
crontab -l | grep -v '/opt/assetsonar-connector' | crontab -
tar -xvzf "$connector_file" -C /opt

chmod +x /opt/assetsonar-connector/scripts/execute_discoveries.sh
chmod +x /opt/assetsonar-connector/scripts/force_sync.sh
chmod +x /opt/assetsonar-connector/scripts/sync.sh

chmod +x /opt/assetsonar-connector/bin/assetsonar_syncer

mkdir /var/lib/assetsonar-connector
mkdir /var/log/assetsonar-connector

command_sync="/opt/assetsonar-connector/bin/assetsonar_syncer -s"
command_execute="/opt/assetsonar-connector/bin/assetsonar_syncer -e"

eval "crontab -l | { cat; echo '0 * * * * $command_sync '; } | crontab -"
eval "crontab -l | { cat; echo '0 * * * * $command_execute '; } | crontab -"

#--------------------------------------------------------------------------------
# Config file
#--------------------------------------------------------------------------------
cat <<EOF > $config_file
[Assetsonar]
url = $assetsonar_url
tag = $agent_tag

[OpenAudit]
sync_enabled = true
url = http://localhost/open-audit/index.php
username = admin
password = password
system_id = System1 # If you plan to install multiple instances of Open Audit, make sure this value is unique for each respective installation of the connector application. Do not leave this empty.
EOF
#--------------------------------------------------------------------------------


#--------------------------------------------------------------------------------
# Integration Health Check
#--------------------------------------------------------------------------------
apache_status=$( systemctl is-active apache2 )
open_audit_status=$( [ -d /var/www/html/open-audit ] && echo true || echo false )
health_check_payload=$(cat <<EOF
{
  "api_type": "open_audit",
  "apache_status": "$apache_status",
  "open_audit_installed": "$open_audit_status",
  "itam_access_token": "$agent_tag",
  "source": "install"
}
EOF
)

curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$health_check_payload" \
  "$assetsonar_url/api/api_integration/health_check.api" \
  > /dev/null 2>&1 &
#--------------------------------------------------------------------------------

echo "Installation complete! Please continue with the steps listed in the guide."
