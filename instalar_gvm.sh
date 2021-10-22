#!/bin/bash
#########################################################################################################
##Script de instalación de Greenbone 											                           ##
##Fecha: 22/10/2021                                                                                    ##
##Versión 1.0:  Permite la instalacion simple de Greenbone versión 21.04.							                   ##
##        Si la instalación de todos los componentes se hace en una misma máquina                      ##
##        queda una versión completamente operativa. Si se instala en diferentes máquinas              ##
##        es necesario modificar la configuración manualmente.                                         ##
##        Instalación completamente automática solo se pide cambio de contraseña al final              ##
##                                                                                                     ##
##Autores:                                                                                             ##
##			Manuel José Beiras Belloso																   ##
##			Rubén Míguez Bouzas										                                   ##
##			Luis Mera Castro										                                   ##
#########################################################################################################

# Comprobación inicial que valida si se es root y si el sistema operativo es Ubutu
function initialCheck() {
	if ! isRoot; then
		echo "El script tiene que ser ejecutado como root"
		exit 1
	fi
}

# Funcion que comprueba que se ejecute el script como root
function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
	checkOS
}

function checkOS() {
	source /etc/os-release
	if [[ $ID == "ubuntu" ]]; then
		OS="ubuntu"
		MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
		if [[ $MAJOR_UBUNTU_VERSION -lt 20 ]]; then
			echo "⚠️ Este script no está probado en tu versión de Ubuntu. ¿Deseas continuar?"
			echo ""
			CONTINUAR='false'
			until [[ $CONTINUAR =~ (y|n) ]]; do
				read -rp "Continuar? [y/n]: " -e CONTINUAR
			done
			if [[ $CONTINUAR == "n" ]]; then
				exit 1
			fi
		fi
		preguntasInstalacion
	else
		echo "Tu sistema operativo no es Ubuntu, en caso de que sea Centos puedes continuar desde aquí. Pulsa [Y]"
		CONTINUAR='false'
		until [[ $CONTINUAR =~ (y|n) ]]; do
			read -rp "Continuar? [y/n]: " -e CONTINUAR
		done
		if [[ $CONTINUAR == "n" ]]; then
			exit 1
		fi
		OS="centos"
		preguntasInstalacion
	fi
}

function preguntasInstalacion() {
  echo -e "¿ Qué deseas hacer ?"
	echo "1. Instalar Greenbone."
	echo "2. Desinstalar Greenbone."
  echo "3. Cambiar Contraseña del admin."
  echo "4. salir."
  read -e CONTINUAR
  if [[ CONTINUAR -eq 1 ]]; then
    instalarGreenbone
  elif [[ CONTINUAR -eq 2 ]]; then
    desinstalarGreenbone
  elif [[ CONTINUAR -eq 3 ]]; then
    cambiarContraseña
  elif [[ CONTINUAR -eq 4 ]]; then
    exit 1
  else
		echo "Opcion no válida!"
    clear
		preguntasInstalacion
	fi
}

function instalarGreenbone() {
  if [[ $OS == "ubuntu" ]]; then
    if dpkg -l | grep openvas > /dev/null; then
      echo "Greenbone ya está instalado en tu sistema."
      echo "No se continúa con la instalación."
    else
      # Creamos usuario gvm usuario y grupo
      sudo useradd -r -M -U -G sudo -s /usr/sbin/nologin gvm
      # Cofiguración de root al grupo de gvm
      usermod -aG gvm $USER
      # Configuración de la ruta para gmvd
      export PATH=$PATH:/usr/local/sbin
      # Configuración de una variable de entorno de prefijo de instalación
      export INSTALL_PREFIX=/usr/local
      # Elegir el directorio de origen
      export SOURCE_DIR=$HOME/source
      mkdir -p $SOURCE_DIR
      # Elegir un directorio de compilación
      export BUILD_DIR=$HOME/build
      mkdir -p $BUILD_DIR
      # Elegir un directorio de instalación temporal
      export INSTALL_DIR=$HOME/install
      mkdir -p $INSTALL_DIR
      # Instalación de dependencias de compilación comunes
      apt update -y && apt install -y --no-install-recommends --assume-yes build-essential curl cmake pkg-config python3 python3-pip gnupg
      # Importación de la clave de firma de la comunidad de Greenbone
      curl -O https://www.greenbone.net/GBCommunitySigningKey.asc
      gpg --import GBCommunitySigningKey.asc
      # Establecer una versión de GVM como variable de entorno
      export GVM_VERSION=21.4.3
      # Establecer la versión de gvm-libs a utilizar
      export GVM_LIBS_VERSION=$GVM_VERSION
      # Dependencias necesarias para gvm-libs
      apt install -y libglib2.0-dev libgpgme-dev libgnutls28-dev uuid-dev libssh-gcrypt-dev libhiredis-dev libxml2-dev libpcap-dev libnet1-dev
      # Dependencias opcionales para gvm-libs
      apt install -y libldap2-dev libradcli-dev
      # Descarga de las fuentes de gvm-libs
      curl -f -L https://github.com/greenbone/gvm-libs/archive/refs/tags/v$GVM_LIBS_VERSION.tar.gz -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/gvm-libs/releases/download/v$GVM_LIBS_VERSION/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc
      # Verificación del archivo fuente
      gpg --verify $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
      # Compilación de gvm-libs
      mkdir -p $BUILD_DIR/gvm-libs && cd $BUILD_DIR/gvm-libs
      cmake $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var -DGVM_PID_DIR=/run/gvm
      make -j$(nproc)
      # Instalación de gvm-libs
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Establecer la versión de gvmd a utilizar
      export GVMD_VERSION=21.4.4
      # Establecer la versión de gvmd a utilizar
      echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
      curl -sL https://www.postgresql.org/media/keys/ACCC4CF8.asc | tee /etc/apt/trusted.gpg.d/pgdg.asc >/dev/null
      apt update -y && apt install -y postgresql-11 postgresql-contrib-11 postgresql-server-dev-11 -y
      apt install -y libglib2.0-dev libgnutls28-dev libpq-dev postgresql-server-dev-11 libical-dev xsltproc rsync
      # Dependencias opcionales para gvmd
      apt install -y --no-install-recommends texlive-latex-extra texlive-fonts-recommended xmlstarlet zip rpm fakeroot dpkg nsis gnupg gpgsm wget sshpass openssh-client socat snmp python3 smbclient python3-lxml gnutls-bin xml-twig-tools
      # Descarga de las fuentes de gvmd
      curl -f -L https://github.com/greenbone/gvmd/archive/refs/tags/v$GVMD_VERSION.tar.gz -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/gvmd/releases/download/v$GVMD_VERSION/gvmd-$GVMD_VERSION.tar.gz.asc -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz.asc
      # Verificación del archivo fuente
      gpg --verify $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz.asc $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
      # Compilación de gvmd
      mkdir -p $BUILD_DIR/gvmd && cd $BUILD_DIR/gvmd
      cmake $SOURCE_DIR/gvmd-$GVMD_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DLOCALSTATEDIR=/var -DSYSCONFDIR=/etc -DGVM_DATA_DIR=/var -DGVM_RUN_DIR=/run/gvm -DOPENVAS_DEFAULT_SOCKET=/run/ospd/ospd-openvas.sock -DGVM_FEED_LOCK_PATH=/var/lib/gvm/feed-update.lock -DSYSTEMD_SERVICE_DIR=/lib/systemd/system -DDEFAULT_CONFIG_DIR=/etc/default -DLOGROTATE_DIR=/etc/logrotate.d
      make -j$(nproc)
      # Instalación de gvmd
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Establecer la versión GSA a utilizar
      export GSA_VERSION=$GVM_VERSION
      # Dependencias necesarias para gsad
      apt install -y libmicrohttpd-dev libxml2-dev libglib2.0-dev libgnutls28-dev
      # Dependencias necesarias para gsad
      apt install -y nodejs yarnpkg
      # Descarga de las fuentes gsa
      curl -f -L https://github.com/greenbone/gsa/archive/refs/tags/v$GSA_VERSION.tar.gz -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/gsa/releases/download/v$GSA_VERSION/gsa-$GSA_VERSION.tar.gz.asc -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz.asc
      # Verificación de los archivos de origen
      gpg --verify $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz.asc $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
      # Compilación de gsa
      mkdir -p $BUILD_DIR/gsa && cd $BUILD_DIR/gsa
      cmake $SOURCE_DIR/gsa-$GSA_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var -DGVM_RUN_DIR=/run/gvm -DGSAD_PID_DIR=/run/gvm -DLOGROTATE_DIR=/etc/logrotate.d
      make -j$(nproc)
      # Instalación de gsa
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Dependencias necesarias para openvas-smb
      apt install -y gcc-mingw-w64 libgnutls28-dev libglib2.0-dev libpopt-dev libunistring-dev heimdal-dev perl-base
      # Establecer la versión de openvas-smb a utilizar
      export OPENVAS_SMB_VERSION=21.4.0
      # Descarga de las fuentes de openvas-smb
      curl -f -L https://github.com/greenbone/openvas-smb/archive/refs/tags/v$OPENVAS_SMB_VERSION.tar.gz -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/openvas-smb/releases/download/v$OPENVAS_SMB_VERSION/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc
      # Verificación del archivo fuente
      gpg --verify $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
      # Compilación de openvas-smb
      mkdir -p $BUILD_DIR/openvas-smb && cd $BUILD_DIR/openvas-smb
      cmake $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release
      make -j$(nproc)
      # Instalación de openvas-smb
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Establecer la versión de openvas-scanner a utilizar
      export OPENVAS_SCANNER_VERSION=$GVM_VERSION
      # Dependencias necesarias para openvas-scanner
      apt install -y bison libglib2.0-dev libgnutls28-dev libgcrypt20-dev libpcap-dev libgpgme-dev libksba-dev rsync nmap
      # Dependencias opcionales para openvas-scanner
      apt install -y python3-impacket libsnmp-dev
      # Descarga de las fuentes de openvas-scanner
      curl -f -L https://github.com/greenbone/openvas-scanner/archive/refs/tags/v$OPENVAS_SCANNER_VERSION.tar.gz -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/openvas-scanner/releases/download/v$OPENVAS_SCANNER_VERSION/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc
      # Verificación del archivo fuente
      gpg --verify $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
      # Compilación de openvas-scanner
      mkdir -p $BUILD_DIR/openvas-scanner && cd $BUILD_DIR/openvas-scanner
      cmake $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var -DOPENVAS_FEED_LOCK_PATH=/var/lib/openvas/feed-update.lock -DOPENVAS_RUN_DIR=/run/ospd
      make -j$(nproc)
      # Instalación de openvas-scanner
      make DESTDIR=$INSTALL_DIR install
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Setting the ospd and ospd-openvas versions to use
      export OSPD_VERSION=21.4.4
      export OSPD_OPENVAS_VERSION=$GVM_VERSION
      # Configuración de las versiones de ospd y ospd-openvas a utilizar
      apt install -y python3 python3-pip python3-setuptools python3-packaging python3-wrapt python3-cffi python3-psutil python3-lxml python3-defusedxml python3-paramiko python3-redis
      # Descarga de las fuentes de ospd
      curl -f -L https://github.com/greenbone/ospd/archive/refs/tags/v$OSPD_VERSION.tar.gz -o $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/ospd/releases/download/v$OSPD_VERSION/ospd-$OSPD_VERSION.tar.gz.asc -o $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz.asc
      # Downloading the ospd-openvas sources
      curl -f -L https://github.com/greenbone/ospd-openvas/archive/refs/tags/v$OSPD_OPENVAS_VERSION.tar.gz -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
      curl -f -L https://github.com/greenbone/ospd-openvas/releases/download/v$OSPD_OPENVAS_VERSION/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc
      # Descarga de las fuentes de ospd-openvas
      gpg --verify $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz.asc $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz
      gpg --verify $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/ospd-$OSPD_VERSION.tar.gz
      tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
      # Instalación de ospd
      cd $SOURCE_DIR/ospd-$OSPD_VERSION
      python3 -m pip install . --prefix=$INSTALL_PREFIX --root=$INSTALL_DIR
      # Instalación de ospd-openvas
      cd $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION
      python3 -m pip install . --prefix=$INSTALL_PREFIX --root=$INSTALL_DIR --no-warn-script-location
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Dependencias necesarias para gvm-tools
      apt install -y python3 python3-pip python3-setuptools python3-packaging python3-lxml python3-defusedxml python3-paramiko
      # Instalación de gvm-tools para el usuario actual
      python3 -m pip install --user gvm-tools
      # Instalación de gvm-tools en todo el sistema
      python3 -m pip install --prefix=$INSTALL_PREFIX --root=$INSTALL_DIR --no-warn-script-location gvm-tools
      cp -rv $INSTALL_DIR/* /
      rm -rf $INSTALL_DIR/*
      # Instalación del servidor Redis
      apt install -y redis-server
      # Añadir la configuración para ejecutar el servidor Redis para el escáner
      cp $SOURCE_DIR/openvas-scanner-$GVM_VERSION/config/redis-openvas.conf /etc/redis/
      chown redis:redis /etc/redis/redis-openvas.conf
      echo "db_address = /run/redis-openvas/redis.sock" | tee -a /etc/openvas/openvas.conf
      # iniciar redis con openvas config
      systemctl start redis-server@openvas.service
      # asegurar que redis con openvas config se inicia en cada inicio del sistema
      systemctl enable redis-server@openvas.service
      # Añadir el usuario gvm al grupo redis
      usermod -aG redis gvm
      # Ajustar los permisos de los directorios
      chown -R gvm:gvm /var/lib/gvm
      chown -R gvm:gvm /var/lib/openvas
      chown -R gvm:gvm /var/log/gvm
      chown -R gvm:gvm /run/gvm
      chmod -R g+srw /var/lib/gvm
      chmod -R g+srw /var/lib/openvas
      chmod -R g+srw /var/log/gvm
      # Ajuste de los permisos de gvmd
      chown gvm:gvm /usr/local/sbin/gvmd
      chmod 6750 /usr/local/sbin/gvmd
      # Ajuste de los permisos del script de sincronización de la alimentación
      chown gvm:gvm /usr/local/bin/greenbone-nvt-sync
      chmod 740 /usr/local/sbin/greenbone-feed-sync
      chown gvm:gvm /usr/local/sbin/greenbone-*-sync
      chmod 740 /usr/local/sbin/greenbone-*-sync
      echo '# allow users of the gvm group run openvas
%gvm ALL = NOPASSWD: /usr/local/sbin/openvas' >> /etc/sudoers
      # Instalación del servidor PostgreSQL
      apt install -y postgresql
      # Iniciar el servidor de base de datos PostgreSQL
      systemctl start postgresql@11-main
      # Configurar el usuario y la base de datos de PostgreSQL
      sudo -Hiu postgres createuser -DRS gvm
      sudo -Hiu postgres createdb -O gvm gvmd
      # Configurar los permisos de la base de datos y las extensiones
      sudo -Hiu postgres psql -c 'create role dba with superuser noinherit;' gvmd
      sudo -Hiu postgres psql -c 'grant dba to gvm;' gvmd
      sudo -Hiu postgres psql -c 'create extension "uuid-ossp";' gvmd
      sudo -Hiu postgres psql -c 'create extension "pgcrypto";' gvmd
      # Creación de un usuario administrador con la contraseña proporcionada
      password=$(sudo -u gvm gvmd --create-user=admin)
      # Establecer el propietario de la importación de piensos
      sudo -u gvm --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value `gvmd --get-users --verbose | grep admin | awk '{print $2}'`
      # Sincronización de los VT procesados por el escáner
      sudo -u gvm greenbone-nvt-sync
      # Sincronización de los datos procesados por gvmd
      sudo -u gvm greenbone-feed-sync --type SCAP
      sudo -u gvm greenbone-feed-sync --type CERT
      sudo -u gvm greenbone-feed-sync --type GVMD_DATA
      # Archivo de servicio Systemd para ospd-openvas
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
      # Archivo de servicio Systemd para gvmd
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
      # Archivo de servicio Systemd para gsad
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
      # Hacer que systemd conozca los nuevos archivos de servicio
      systemctl daemon-reload
      # Garantizar la ejecución de los servicios en cada inicio del sistema
      systemctl enable ospd-openvas
      systemctl enable gvmd
      systemctl enable gsad
      # Por fin se ponen en marcha los servicios
      systemctl start ospd-openvas
      systemctl start gvmd
      systemctl start gsad
      # Abrir Greenbone Security Assistant en el navegador
      xdg-open "http://0.0.0.0:9392" 2>/dev/null >/dev/null &
      # Preguntamos si cambiamos la contraseña del usuario admin
	    echo "La contraseña del usuario admin es: $password"
      CAMBIAR='false'
	    until [[ $CAMBIAR =~ (y|n) ]]; do
        read -rp "¿ Quieres cambiarla ? [y/n] " -e CAMBIAR
        echo CAMBIAR
        clear
        if [[ $CAMBIAR == y ]]; then
          cambiarContraseña
        elif [[ $CAMBIAR == n ]]; then
          exit 0 
        fi
	    done
    fi
  fi
}

function cambiarContraseña() {
  echo -e 'Vamos a cambiar la contraseña del admin: '
  read -e newpassword
  sudo -u gvm gvmd --user=admin --new-password=$newpassword
  echo "Contraseña cambiada con éxito a: $newpassword"
  echo "Si piensas que te has equivocado puedes cambiarla desde el menú."
  preguntasInstalacion
}

function desinstalarGreenbone() {
  rm -f /root/build/
  rm -f /root/source/
  rm -f /root/install/
  echo ""
  echo ""
  echo ""
  echo "Greenbone desinstalado."
  echo ""
  echo ""
  echo ""
}

initialCheck
