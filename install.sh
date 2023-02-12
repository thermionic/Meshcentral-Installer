#!/usr/bin/env bash
# modified extensively from  the original https://github.com/techahold/Meshcentral-Installer

echo -ne "Enter your preferred domain/dns address ${NC}: "
  read dnsnames
echo -ne "Enter your letsencrypt email address ${NC}: "
  read letsemail
echo -ne "Enter the account username ${NC}: "
  read meshuname
echo -ne "Enter the account email ${NC}: "
  read meshumail
echo -ne "Enter your company name ${NC}: "
  read coname

# Adding public hostname to hosts file
local="127.0.0.1"
printf "%s\t%s\n" "$local" "$dnsnames" | sudo tee -a /etc/hosts > /dev/null

echo "Checking lsb-release"
if ! which lsb_release >/dev/null
  then
  sudo apt-get install -y lsb-core > null
fi

echo "Checking jq"
if ! which jq >/dev/null
  then
  sudo apt-get install -y jq > null
fi

echo "Prep to install mongodb 5"	
wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-5.0.list

echo "Prep to install Nodejs"
curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -  > null


echo "installing mongodb 5"
sudo apt-get update > null
sudo apt-get install -y mongodb-org > null
sudo systemctl enable mongod
sudo systemctl start mongod

echo "installing nodejs"
sudo apt-get install -y nodejs  > null
echo "Updating Nodejs"
sudo npm install -g npm  > null

while ! [[ $CHECK_MONGO_SERVICE ]]; do
    CHECK_MONGO_SERVICE=$(sudo systemctl status mongod.service | grep "Active: active (running)")
    echo -ne "MongoDB is not ready yet...${NC}\n"
    sleep 1
done

sudo useradd -r -d /opt/meshcentral -s /sbin/nologin meshcentral

sudo mkdir -p /opt/meshcentral/meshcentral-data
sudo chown meshcentral:meshcentral -R /opt/meshcentral
cd /opt/meshcentral

echo installing MeshCentral
sudo npm install meshcentral
sudo chown meshcentral:meshcentral -R /opt/meshcentral

echo "creating systemd unit file"
meshservice="$(cat << EOF
[Unit]
Description=MeshCentral Server
After=network.target
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/node /opt/meshcentral/node_modules/meshcentral
Environment=NODE_ENV=production
WorkingDirectory=/opt/meshcentral
User=meshcentral
Group=meshcentral
Restart=always
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
)"
echo "${meshservice}" | sudo tee /etc/systemd/system/meshcentral.service > /dev/null

sudo setcap 'cap_net_bind_service=+ep' `which node`
sudo systemctl daemon-reload
sudo systemctl enable meshcentral.service

echo MeshCentral will now be started to create the initial config and then stopped

sudo systemctl start meshcentral.service
while ! [[ $CHECK_MESH_SERVICE1 ]]; do
  CHECK_MESH_SERVICE1=$(sudo systemctl status meshcentral.service | grep "MeshCentral HTTPS server running on")
  echo -ne "Meshcentral not ready yet...${NC}\n"
  sleep 1
done
sudo systemctl stop meshcentral

echo setup config.json for mongodb
sudo sed -i '/"settings": {/a "MongoDb": "mongodb://127.0.0.1:27017/meshcentral",\n"MongoDbCol": "meshcentral",' /opt/meshcentral/meshcentral-data/config.json

echo "LetsEncrypt"

# DNS/SSL Setup
  sudo sed -i 's|"_letsencrypt": |"letsencrypt": |g' /opt/meshcentral/meshcentral-data/config.json
  sudo sed -i 's|"_redirPort": |"redirPort": |g' /opt/meshcentral/meshcentral-data/config.json
  sudo sed -i 's|"_cert": |"cert": |g' /opt/meshcentral/meshcentral-data/config.json
  sudo sed -i 's|"production": false|"production": true|g' /opt/meshcentral/meshcentral-data/config.json

  cat "/opt/meshcentral/meshcentral-data/config.json" |
  jq " .settings.cert |= \"$dnsnames\" " |
  jq " .letsencrypt.email |= \"$letsemail\" " |
  jq " .letsencrypt.names |= \"$dnsnames\" " > ~/config2.json
  sudo mv ~/config2.json /opt/meshcentral/meshcentral-data/config.json
echo "SSL is configured"

echo "Admin account"

  meshpwd=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
   echo "Creating Admin account"
    sudo -u meshcentral node /opt/meshcentral/node_modules/meshcentral --createaccount $meshuname --pass $meshpwd --email $meshumail
    sleep 3
	sudo -u meshcentral node /opt/meshcentral/node_modules/meshcentral --adminaccount $meshuname
    sleep 3

echo "Choice for other settings"

PS3='Would you like this script to preconfigure other settings: '
OS=("Yes" "No")
select OSOPT in "${OS[@]}"; do
  case $OSOPT in
    "Yes")
        sudo sed -i 's|"_redirPort": |"redirPort": |g' /opt/meshcentral/meshcentral-data/config.json
        sudo sed -i 's|"_title": "MyServer",|"title": "'"${coname}"' Support",|g' /opt/meshcentral/meshcentral-data/config.json
        sudo sed -i 's|"_newAccounts": true,|"newAccounts": false,|g' /opt/meshcentral/meshcentral-data/config.json
        sudo sed -i 's|"_userNameIsEmail": true|"_userNameIsEmail": true,|g' /opt/meshcentral/meshcentral-data/config.json
        sudo sed -i '/ "_userNameIsEmail": true,/a "agentInviteCodes": true,\n "agentCustomization": {\n"displayname": "'"$coname"' Support",\n"description": "'"$coname"' Remote Agent",\n"companyName": "'"$coname"'",\n"serviceName": "'"$coname"'Remote"\n}' /opt/meshcentral/meshcentral-data/config.json
        sudo sed -i '/"settings": {/a "plugins":{\n"enabled": true\n},' /opt/meshcentral/meshcentral-data/config.json
        sudo sed -i '/"settings": {/a "MaxInvalidLogin": {\n"time": 5,\n"count": 5,\n"coolofftime": 30\n},' /opt/meshcentral/meshcentral-data/config.json
      echo "Setting up defaults on MeshCentral"
	     sudo systemctl start meshcentral.service
           while ! [[ $CHECK_MESH_SERVICE2 ]]; do
             CHECK_MESH_SERVICE2=$(sudo systemctl status meshcentral.service | grep "MeshCentral HTTPS server running on")
             echo -ne "Meshcentral not ready yet...${NC}\n"
             sleep 1
          done
        sudo -u meshcentral node node_modules/meshcentral/meshctrl.js --url wss://$dnsnames:443 --loginuser $meshuname --loginpass $meshpwd AddDeviceGroup --name "$coname"
        sudo -u meshcentral node node_modules/meshcentral/meshctrl.js --url wss://$dnsnames:443 --loginuser $meshuname --loginpass $meshpwd EditDeviceGroup --group "$coname" --desc ''"$coname"' Support Group' --consent 71
        sudo -u meshcentral node node_modules/meshcentral/meshctrl.js --url wss://$dnsnames:443 --loginuser $meshuname --loginpass $meshpwd EditUser --userid $meshuname --realname ''"$coname"' Support'
      break
      ;;
    "No")
      break
      ;;
    *) echo "invalid option $REPLY"
	  ;;
  esac
done

echo "You can now go to https://$dnsnames and login "
echo " with $meshuname and $meshpwd"
