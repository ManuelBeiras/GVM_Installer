#!/bin/bash
#########################################################################################################
##Greenbone installation script 											                                                 ##
##Date: 22/10/2021                                                                                     ##
##Version 1.0:  Allows simple installation of Greenbone version 21.04.							                   ##
##        If the installation of all components is done on the same machine                            ##
##        a fully operational version remains. If installed on different machines                      ##
##        it is necessary to modify the configuration manually.                                        ##
##        Fully automatic installation only requires a password change at the end if you want.         ##
##                                                                                                     ##
##Authors:                                                                                             ##
##			Manuel José Beiras Belloso																                                     ##
##			Rubén Míguez Bouzas										                                                         ##
##			Luis Mera Castro										                                                           ##
#########################################################################################################

# Initial check if the user is root and the OS is Ubuntu
function initialCheck() {
	if ! isRoot; then
		echo "The script must be executed as a root"
		exit 1
	fi
}

# Check if the user is root
function isRoot() {
    if [ "$EUID" -ne 0 ]; then
		return 1
	fi
	checkOS
}

# Check the operating system
function checkOS() {
    source /etc/os-release
	if [[ $ID == "ubuntu" ]]; then
	    OS="ubuntu"
	    MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
	    if [[ $MAJOR_UBUNTU_VERSION -lt 20 ]]; then
            echo "⚠️ This script it's not tested in your Ubuntu version. You want to continue?"
			echo ""
			CONTINUE='false'
			until [[ $CONTINUE =~ (y|n) ]]; do
			    read -rp "Continue? [y/n]: " -e CONTINUE
			done
			if [[ $CONTINUE == "n" ]]; then
				exit 1
			fi
		fi
		questionsMenu
	else
        echo "Your OS it's not Ubuntu, in the case you are using Centos you can continue from here. Press [Y]"
		CONTINUE='false'
		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "Continue? [y/n]: " -e CONTINUE
		done
		if [[ $CONTINUE == "n" ]]; then
			exit 1
		fi
		OS="centos"
		questionsMenu
	fi
}

function questionsMenu() {
  echo -e "What you want to do ?"
	echo "1. Install Greenbone."
	echo "2. Uninstall Greenbone."
  echo "3. Change admin password"
  echo "0. exit."
  read -e CONTINUE
  if [[ $CONTINUE == 1 ]]; then
    installGreenbone
  elif [[ $CONTINUE == 2 ]]; then
    uninstallGreenbone
  elif [[ $CONTINUE == 3 ]]; then
    changePassword
  elif [[ $CONTINUE == 0 ]]; then
    exit 1
  else
		echo "invalid option !"
    clear
		questionsMenu
	fi
}

function installGreenbone() {
  if [[ $OS == "ubuntu" ]]; then
    if dpkg -l | grep openvas > /dev/null; then
      echo "Greenbone it's already installed on your system."
      echo "Installation cancelled."
    else
      # Creating a gvm system user and group
      sudo useradd -r -M -U -G sudo -s /usr/sbin/nologin gvm
      # Add root user to gvm group¶
      usermod -aG gvm $USER
      # Adjusting PATH for running gvmd
      export PATH=$PATH:/usr/local/sbin
      # Setting an install prefix environment variable¶
      export INSTALL_PREFIX=/usr/local
      # Choosing a source directory
      export SOURCE_DIR=$HOME/source
      mkdir -p $SOURCE_DIR
      # Choosing a build directory
      export BUILD_DIR=$HOME/build
      mkdir -p $BUILD_DIR
      # Choosing a temporary install directory
      export INSTALL_DIR=$HOME/install
      mkdir -p $INSTALL_DIR
      # Installing common build dependencies
      apt update -y && apt install -y --no-install-recommends --assume-yes build-essential curl cmake pkg-config python3 python3-pip gnupg
      # Importing the Greenbone Community Signing key
      curl -O https://www.greenbone.net/GBCommunitySigningKey.asc
      gpg --import GBCommunitySigningKey.asc
      # Setting the trust level for the Greenbone Community Signing key
      export GVM_VERSION=21.4.3
      # Setting a GVM version as environment variable
      export GVM_LIBS_VERSION=$GVM_VERSION
      # Required dependencies for gvm-libs
      apt install -y libglib2.0-dev libgpgme-dev libgnutls28-dev uuid-dev libssh-gcrypt-dev libhiredis-dev libxml2-dev libpcap-dev libnet1-dev
      # Optional dependencies for gvm-libs
      apt install -y libldap2-dev libradcli-dev
      # Downloading the gvm-libs sources
      curl -f -L https://github.com/greenbone/gvm-libs/archive/refs/tags/v$GVM_LIBS_VERSION.tar.gz -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/gvm-libs/releases/download/v$GVM_LIBS_VERSION/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc
      # Verifying the source file
      gpg --verify $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
      # Building gvm-libs
      mkdir -p $BUILD_DIR/gvm-libs && cd $BUILD_DIR/gvm-libs
      cmake $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var -DGVM_PID_DIR=/run/gvm
      make -j$(nproc)
      # Installing gvm-libs
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Setting the gvmd version to use
      export GVMD_VERSION=21.4.4
      echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
      curl -sL https://www.postgresql.org/media/keys/ACCC4CF8.asc | tee /etc/apt/trusted.gpg.d/pgdg.asc >/dev/null
      apt update -y && apt install -y postgresql-11 postgresql-contrib-11 postgresql-server-dev-11 -y
      # Required dependencies for gvmd
      apt install -y libglib2.0-dev libgnutls28-dev libpq-dev postgresql-server-dev-11 libical-dev xsltproc rsync
      # Optional dependencies for gvmd
      apt install -y --no-install-recommends texlive-latex-extra texlive-fonts-recommended xmlstarlet zip rpm fakeroot dpkg nsis gnupg gpgsm wget sshpass openssh-client socat snmp python3 smbclient python3-lxml gnutls-bin xml-twig-tools
      # Downloading the gvmd sources
      curl -f -L https://github.com/greenbone/gvmd/archive/refs/tags/v$GVMD_VERSION.tar.gz -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/gvmd/releases/download/v$GVMD_VERSION/gvmd-$GVMD_VERSION.tar.gz.asc -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz.asc
      # Verifying the source file
      gpg --verify $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz.asc $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
      # Building gvmd
      mkdir -p $BUILD_DIR/gvmd && cd $BUILD_DIR/gvmd
      cmake $SOURCE_DIR/gvmd-$GVMD_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DLOCALSTATEDIR=/var -DSYSCONFDIR=/etc -DGVM_DATA_DIR=/var -DGVM_RUN_DIR=/run/gvm -DOPENVAS_DEFAULT_SOCKET=/run/ospd/ospd-openvas.sock -DGVM_FEED_LOCK_PATH=/var/lib/gvm/feed-update.lock -DSYSTEMD_SERVICE_DIR=/lib/systemd/system -DDEFAULT_CONFIG_DIR=/etc/default -DLOGROTATE_DIR=/etc/logrotate.d
      make -j$(nproc)
      # Installing gvmd
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Setting the GSA version to use
      export GSA_VERSION=$GVM_VERSION
      # Required dependencies for gsad
      apt install -y libmicrohttpd-dev libxml2-dev libglib2.0-dev libgnutls28-dev
      # Required dependencies for GSA
      apt install -y nodejs yarnpkg
      # Downloading the gsa sources
      curl -f -L https://github.com/greenbone/gsa/archive/refs/tags/v$GSA_VERSION.tar.gz -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/gsa/releases/download/v$GSA_VERSION/gsa-$GSA_VERSION.tar.gz.asc -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz.asc
      # Verifying the source files
      gpg --verify $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz.asc $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
      # Building gsa
      mkdir -p $BUILD_DIR/gsa && cd $BUILD_DIR/gsa
      cmake $SOURCE_DIR/gsa-$GSA_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var -DGVM_RUN_DIR=/run/gvm -DGSAD_PID_DIR=/run/gvm -DLOGROTATE_DIR=/etc/logrotate.d
      make -j$(nproc)
      # Installing gsa
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Required dependencies for openvas-smb
      apt install -y gcc-mingw-w64 libgnutls28-dev libglib2.0-dev libpopt-dev libunistring-dev heimdal-dev perl-base
      # Setting the openvas-smb version to use
      export OPENVAS_SMB_VERSION=21.4.0
      # Downloading the openvas-smb sources
      curl -f -L https://github.com/greenbone/openvas-smb/archive/refs/tags/v$OPENVAS_SMB_VERSION.tar.gz -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/openvas-smb/releases/download/v$OPENVAS_SMB_VERSION/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc
      # Verifying the source file
      gpg --verify $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
      # Building openvas-smb
      mkdir -p $BUILD_DIR/openvas-smb && cd $BUILD_DIR/openvas-smb
      cmake $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release
      make -j$(nproc)
      # Installing openvas-smb
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Setting the openvas-scanner version to use
      export OPENVAS_SCANNER_VERSION=$GVM_VERSION
      # Required dependencies for openvas-scanner
      apt install -y bison libglib2.0-dev libgnutls28-dev libgcrypt20-dev libpcap-dev libgpgme-dev libksba-dev rsync nmap
      # Optional dependencies for openvas-scanner
      apt install -y python3-impacket libsnmp-dev
      # Downloading the openvas-scanner sources
      curl -f -L https://github.com/greenbone/openvas-scanner/archive/refs/tags/v$OPENVAS_SCANNER_VERSION.tar.gz -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/openvas-scanner/releases/download/v$OPENVAS_SCANNER_VERSION/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc
      # Verifying the source file
      gpg --verify $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
      # Building openvas-scanner
      mkdir -p $BUILD_DIR/openvas-scanner && cd $BUILD_DIR/openvas-scanner
      cmake $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var -DOPENVAS_FEED_LOCK_PATH=/var/lib/openvas/feed-update.lock -DOPENVAS_RUN_DIR=/run/ospd
      make -j$(nproc)
      # Installing openvas-scanner
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Setting the ospd and ospd-openvas versions to use
      export OSPD_VERSION=21.4.4
      export OSPD_OPENVAS_VERSION=$GVM_VERSION
      # Required dependencies for ospd-openvas
      apt install -y python3 python3-pip python3-setuptools python3-packaging python3-wrapt python3-cffi python3-psutil python3-lxml python3-defusedxml python3-paramiko python3-redis
      # Downloading the ospd sources
      curl -f -L https://github.com/greenbone/ospd/archive/refs/tags/v$OSPD_VERSION.tar.gz -o $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/ospd/releases/download/v$OSPD_VERSION/ospd-$OSPD_VERSION.tar.gz.asc -o $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz.asc
      # Downloading the ospd-openvas sources
      curl -f -L https://github.com/greenbone/ospd-openvas/archive/refs/tags/v$OSPD_OPENVAS_VERSION.tar.gz -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/ospd-openvas/releases/download/v$OSPD_OPENVAS_VERSION/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc
      # Downloading the ospd-openvas sources
      gpg --verify $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz.asc $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz
      gpg --verify $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
      # Installing ospd
      cd $SOURCE_DIR/ospd-$OSPD_VERSION
      python3 -m pip install . --prefix=$INSTALL_PREFIX --root=$INSTALL_DIR
      # Installing ospd-openvas
      cd $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION
      python3 -m pip install . --prefix=$INSTALL_PREFIX --root=$INSTALL_DIR --no-warn-script-location
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Required dependencies for gvm-tools
      apt install -y python3 python3-pip python3-setuptools python3-packaging python3-lxml python3-defusedxml python3-paramiko
      # Installing gvm-tools for the current user
      python3 -m pip install --user gvm-tools
      # Installing gvm-tools system-wide
      python3 -m pip install --prefix=$INSTALL_PREFIX --root=$INSTALL_DIR --no-warn-script-location gvm-tools
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Installing the Redis server
      apt install -y redis-server
      # Adding configuration for running the Redis server for the scanner¶
      cp $SOURCE_DIR/openvas-scanner-$GVM_VERSION/config/redis-openvas.conf /etc/redis/
      chown redis:redis /etc/redis/redis-openvas.conf
      echo "db_address = /run/redis-openvas/redis.sock" | tee -a /etc/openvas/openvas.conf
      # Start redis with openvas config
      systemctl start redis-server@openvas.service
      # Ensure redis with openvas config is started on every system startup
      systemctl enable redis-server@openvas.service
      # Adding the gvm user to the redis group
      usermod -aG redis gvm
      # Adjusting directory permissions
      chown -R gvm:gvm /var/lib/gvm
      chown -R gvm:gvm /var/lib/openvas
      chown -R gvm:gvm /var/log/gvm
      chown -R gvm:gvm /run/gvm
      chmod -R g+srw /var/lib/gvm
      chmod -R g+srw /var/lib/openvas
      chmod -R g+srw /var/log/gvm
      # Adjusting gvmd permissions
      chown gvm:gvm /usr/local/sbin/gvmd
      chmod 6750 /usr/local/sbin/gvmd
      # Adjusting feed sync script permissions
      chown gvm:gvm /usr/local/bin/greenbone-nvt-sync
      chmod 740 /usr/local/sbin/greenbone-feed-sync
      chown gvm:gvm /usr/local/sbin/greenbone-*-sync
      chmod 740 /usr/local/sbin/greenbone-*-sync
      echo '# allow users of the gvm group run openvas
%gvm ALL = NOPASSWD: /usr/local/sbin/openvas' >> /etc/sudoers
      # Installing the PostgreSQL server
      apt install -y postgresql
      # Starting the PostgreSQL database server
      systemctl start postgresql@11-main
      # Setting up PostgreSQL user and database
      sudo -Hiu postgres createuser -DRS gvm
      sudo -Hiu postgres createdb -O gvm gvmd
      # Setting up database permissions and extensions
      sudo -Hiu postgres psql -c 'create role dba with superuser noinherit;' gvmd
      sudo -Hiu postgres psql -c 'grant dba to gvm;' gvmd
      sudo -Hiu postgres psql -c 'create extension "uuid-ossp";' gvmd
      sudo -Hiu postgres psql -c 'create extension "pgcrypto";' gvmd
      # Creating an administrator user with generated password
      password=$(sudo -u gvm gvmd --create-user=admin)
      # Setting the Feed Import Owner
      sudo -u gvm --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value `gvmd --get-users --verbose | grep admin | awk '{print $2}'`
      # Syncing VTs processed by the scanner
      sudo -u gvm greenbone-nvt-sync
      # Syncing the data processed by gvmd
      sudo -u gvm greenbone-feed-sync --type SCAP
      sudo -u gvm greenbone-feed-sync --type CERT
      sudo -u gvm greenbone-feed-sync --type GVMD_DATA
      # Systemd service file for ospd-openvas
      cat << EOF > $BUILD_DIR/ospd-openvas.service
[Unit]
Description=OSPd Wrapper for the OpenVAS Scanner (ospd-openvas)
Documentation=man:ospd-openvas(8) man:openvas(8)
After=network.target networking.service redis-server@openvas.service
Wants=redis-server@openvas.service
ConditionKernelCommandLine=!recovery

[Service]
Type=forking
User=gvm
Group=gvm
RuntimeDirectory=ospd
RuntimeDirectoryMode=2775
PIDFile=/run/ospd/ospd-openvas.pid
ExecStart=/usr/local/bin/ospd-openvas --unix-socket /run/ospd/ospd-openvas.sock --pid-file /run/ospd/ospd-openvas.pid --log-file /var/log/gvm/ospd-openvas.log --lock-file-dir /var/lib/openvas --socket-mode 0o770
SuccessExitStatus=SIGKILL
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF
      cp $BUILD_DIR/ospd-openvas.service /etc/systemd/system/
      # Systemd service file for gvmd
      cat << EOF > $BUILD_DIR/gvmd.service
[Unit]
Description=Greenbone Vulnerability Manager daemon (gvmd)
After=network.target networking.service postgresql.service ospd-openvas.service
Wants=postgresql.service ospd-openvas.service
Documentation=man:gvmd(8)
ConditionKernelCommandLine=!recovery

[Service]
Type=forking
User=gvm
Group=gvm
PIDFile=/run/gvm/gvmd.pid
RuntimeDirectory=gvm
RuntimeDirectoryMode=2775
ExecStart=/usr/local/sbin/gvmd --osp-vt-update=/run/ospd/ospd-openvas.sock --listen-group=gvm
Restart=always
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
      cp $BUILD_DIR/gvmd.service /etc/systemd/system/
      # Systemd service file for gsad
      cat << EOF > $BUILD_DIR/gsad.service
[Unit]
Description=Greenbone Security Assistant daemon (gsad)
Documentation=man:gsad(8) https://www.greenbone.net
After=network.target gvmd.service
Wants=gvmd.service

[Service]
Type=forking
User=gvm
Group=gvm
PIDFile=/run/gvm/gsad.pid
ExecStart=/usr/local/sbin/gsad --listen=0.0.0.0 --port=9392 --http-only
Restart=always
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
Alias=greenbone-security-assistant.service
EOF
      cp $BUILD_DIR/gsad.service /etc/systemd/system/
      # Making systemd aware of the new service files
      systemctl daemon-reload
      # Ensuring services are run at every system startup
      systemctl enable ospd-openvas
      systemctl enable gvmd
      systemctl enable gsad
      # Finally starting the services
      systemctl start ospd-openvas
      systemctl start gvmd
      systemctl start gsad
      # Opening Greenbone Security Assistant in the browser
      xdg-open "http://0.0.0.0:9392" 2>/dev/null >/dev/null &
      # Ask the user if he want to change the admin password
	    echo "Admin password is: $password"
      CHANGE='false'
	    until [[ $CHANGE =~ (y|n) ]]; do
        read -rp "Do you want to change it ? [y/n] " -e CHANGE
        echo CHANGE
        clear
        if [[ $CHANGE == y ]]; then
          changePassword
        elif [[ $CHANGE == n ]]; then
          exit 0 
        fi
	    done
    fi
  fi
}

function changePassword() {
  echo -e 'We proceed to change admin password: '
  read -e newpassword
  sudo -u gvm gvmd --user=admin --new-password=$newpassword
  echo "Admin password changed successfully: $newpassword"
  echo "If you think you have made a mistake you can change it from the menu."
  questionsMenu
}

function uninstallGreenbone() {
  rm -f /root/build/
  rm -f /root/source/
  rm -f /root/install/
  echo ""
  echo ""
  echo ""
  echo "Greenbone uninstalled."
  echo ""
  echo ""
  echo ""
}

initialCheck