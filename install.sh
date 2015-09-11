#!/bin/bash
#
# Script d'installation de Postfix, Dovecot et Rainloop
# Auteur : Hardware <contact@meshup.net>
# Version : 1.0.0
# URLs : https://github.com/hardware/mailserver-autoinstall
#        http://mondedie.fr/viewtopic.php?pid=11746
#
# Compatible : Debian 7 "wheezy" & Debian 8 "jessie"
#
# Pré-requis
# Nginx, PHP, MySQL, OpenSSL (Un serveur LEMP fonctionnel)
# Tiré du tutoriel sur mondedie.fr disponible ici:
# http://mondedie.fr/viewtopic.php?id=5302
#
# Installation:
#
# apt-get update && apt-get dist-upgrade
# apt-get install git-core
#
# cd /tmp
# git clone https://github.com/hardware/mailserver-autoinstall.git
# cd mailserver-autoinstall
# chmod a+x install.sh && ./install.sh
#
# Inspiré du script d'installation de rutorrent de Ex_Rat :
# https://bitbucket.org/exrat/install-rutorrent

CSI="\033["
CEND="${CSI}0m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CPURPLE="${CSI}1;35m"
CCYAN="${CSI}1;36m"
CBROWN="${CSI}0;33m"

POSTFIXADMIN_VER="2.92"
DEBIAN_VER=$(sed 's/\..*//' /etc/debian_version)

# ##########################################################################

if [[ $EUID -ne 0 ]]; then
    echo ""
    echo -e "${CRED}/!\ ERREUR: Ce script doit être exécuté en tant que root.${CEND}" 1>&2
    echo ""
    exit 1
fi

# ##########################################################################

smallLoader() {
    echo ""
    echo ""
    echo -ne '[ + + +             ] 3s \r'
    sleep 1
    echo -ne '[ + + + + + +       ] 2s \r'
    sleep 1
    echo -ne '[ + + + + + + + + + ] 1s \r'
    sleep 1
    echo -ne '[ + + + + + + + + + ] Appuyez sur [ENTRÉE] pour continuer... \r'
    echo -ne '\n'

    read -r
}

checkBin() {
    echo -e "${CRED}/!\ ERREUR: '$1' est requis pour cette installation.${CEND}"
}

# Vérification des pré-requis
command -v dpkg > /dev/null 2>&1 || { checkBin dpkg >&2; exit 1; }
command -v apt-get > /dev/null 2>&1 || { checkBin apt-get >&2; exit 1; }
command -v mysql > /dev/null 2>&1 || { checkBin mysql >&2; exit 1; }
command -v mysqladmin > /dev/null 2>&1 || { checkBin mysqladmin >&2; exit 1; }
command -v wget > /dev/null 2>&1 || { checkBin wget >&2; exit 1; }
command -v tar > /dev/null 2>&1 || { checkBin tar >&2; exit 1; }
command -v openssl > /dev/null 2>&1 || { checkBin openssl >&2; exit 1; }
command -v unzip > /dev/null 2>&1 || { checkBin unzip >&2; exit 1; }
command -v strings > /dev/null 2>&1 || { checkBin binutils >&2; exit 1; }
command -v nginx > /dev/null 2>&1 || { checkBin nginx >&2; exit 1; }
command -v git > /dev/null 2>&1 || { checkBin git-core >&2; exit 1; }
command -v curl > /dev/null 2>&1 || { checkBin curl >&2; exit 1; }
command -v dig > /dev/null 2>&1 || { checkBin dnsutils >&2; exit 1; }

# ##########################################################################

dpkg -s postfix | grep "install ok installed" &> /dev/null

# On vérifie que Postfix n'est pas installé
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${CRED}/!\ ERREUR: Postfix est déjà installé sur le serveur.${CEND}" 1>&2
    echo ""
    # exit 1
fi

dpkg -s dovecot-core | grep "install ok installed" &> /dev/null

# On vérifie que Dovecot n'est pas installé
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${CRED}/!\ ERREUR: Dovecot est déjà installé sur le serveur.${CEND}" 1>&2
    echo ""
    exit 1
fi

dpkg -s opendkim | grep "install ok installed" &> /dev/null

# On vérifie que OpenDKIM n'est pas installé
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${CRED}/!\ ERREUR: OpenDKIM est déjà installé sur le serveur.${CEND}" 1>&2
    echo ""
    exit 1
fi

# ##########################################################################

clear

echo ""
echo -e "${CYELLOW}    Installation automatique d'une serveur de mail avec Postfix et Dovecot${CEND}"
echo ""
echo -e "${CCYAN}
███╗   ███╗ ██████╗ ███╗   ██╗██████╗ ███████╗██████╗ ██╗███████╗   ███████╗██████╗
████╗ ████║██╔═══██╗████╗  ██║██╔══██╗██╔════╝██╔══██╗██║██╔════╝   ██╔════╝██╔══██╗
██╔████╔██║██║   ██║██╔██╗ ██║██║  ██║█████╗  ██║  ██║██║█████╗     █████╗  ██████╔╝
██║╚██╔╝██║██║   ██║██║╚██╗██║██║  ██║██╔══╝  ██║  ██║██║██╔══╝     ██╔══╝  ██╔══██╗
██║ ╚═╝ ██║╚██████╔╝██║ ╚████║██████╔╝███████╗██████╔╝██║███████╗██╗██║     ██║  ██║
╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═════╝ ╚═╝╚══════╝╚═╝╚═╝     ╚═╝  ╚═╝

${CEND}"
echo ""

DOMAIN=$(hostname -d 2> /dev/null)   # domain.tld
HOSTNAME=$(hostname -s 2> /dev/null) # hostname
FQDN=$(hostname -f 2> /dev/null)     # hostname.domain.tld
PORT=80

# Récupération de l'adresse IP WAN
WANIP=$(dig o-o.myaddr.l.google.com @ns1.google.com txt +short | sed 's/"//g')

if [[ -z "${WANIP// }" ]]; then
    WANIP=$(curl -s icanhazip.com)
fi

echo -e "${CCYAN}    Configuration du FQDN (Fully qualified domain name) du serveur     ${CEND}"
echo -e "${CCYAN}-----------------------------------------------------------------------${CEND}"
echo ""
echo -e "${CCYAN}[ Votre serveur est actuellement configuré avec les valeurs suivantes ]${CEND}"
echo ""
echo -e "DOMAINE    : ${CGREEN}${DOMAIN}${CEND}"
echo -e "NOM D'HOTE : ${CGREEN}${HOSTNAME}${CEND}"
echo -e "FQDN       : ${CGREEN}${FQDN}${CEND}"
echo -e "IP WAN     : ${CGREEN}${WANIP}${CEND}"
echo -e "PORT WEB   : ${CGREEN}${PORT}${CEND}"
echo ""
echo -e "${CCYAN}-----------------------------------------------------------------------${CEND}"
echo ""

read -rp "Souhaitez-vous les modifier ? o/[N] : " REPFQDN

if [[ "$REPFQDN" = "O" ]] || [[ "$REPFQDN" = "o" ]]; then

echo ""
read -rp "> Veuillez saisir le nom d'hôte : " HOSTNAME
read -rp "> Veuillez saisir le nom de domaine (format: domain.tld) : " DOMAIN
read -rp "> Veuillez saisir le port du serveur web en écoute [Par défaut: 80] : " PORT

if [[ -z "${PORT// }" ]]; then
    PORT=80
fi

FQDN="${HOSTNAME}.${DOMAIN}"

# Modification du nom d'hôte
echo "$HOSTNAME" > /etc/hostname

# Modification du FQDN
cat > /etc/hosts <<EOF
127.0.0.1 localhost.localdomain localhost
${WANIP} ${FQDN}               ${HOSTNAME}
EOF

echo ""
echo -e "${CCYAN}-----------------------------------------------------------------------${CEND}"
echo ""
echo -e "${CCYAN}[ Après un redémarrage du serveur, les valeurs seront les suivantes : ]${CEND}"
echo ""
echo -e "DOMAINE    : ${CGREEN}${DOMAIN}${CEND}"
echo -e "NOM D'HOTE : ${CGREEN}${HOSTNAME}${CEND}"
echo -e "FQDN       : ${CGREEN}${FQDN}${CEND}"
echo -e "IP WAN     : ${CGREEN}${WANIP}${CEND}"
echo -e "PORT WEB   : ${CGREEN}${PORT}${CEND}"
echo ""
echo -e "${CCYAN}-----------------------------------------------------------------------${CEND}"
echo ""

smallLoader
clear

fi
#IF REPFQDN

# ##########################################################################

echo ""
echo -e "${CCYAN}--------------------------------${CEND}"
echo -e "${CCYAN}[ Création des certificats SSL ]${CEND}"
echo -e "${CCYAN}--------------------------------${CEND}"
echo ""

cd /etc/ssl/ || exit

echo -e "${CGREEN}-> Création de l'autorité de certification${CEND}"
openssl genrsa -out mailserver_ca.key 4096
openssl req -x509 -new -nodes -days 3658 -sha256 -key mailserver_ca.key -out mailserver_ca.crt<<EOF
FR
France
Paris
${DOMAIN} Certificate authority
IT
*.${DOMAIN}
admin@${DOMAIN}
EOF

echo -e "\n\n${CGREEN}-> Création du certificat de Postfix${CEND}"
openssl genrsa -out mailserver_postfix.key 4096
openssl req -new -sha256 -key mailserver_postfix.key -out mailserver_postfix.csr<<EOF
FR
France
Paris
Postfix certificate
Mail
*.${DOMAIN}
admin@${DOMAIN}


EOF

echo -e "\n\n${CGREEN}-> Création du certificat de Dovecot${CEND}"
openssl genrsa -out mailserver_dovecot.key 4096
openssl req -new -sha256 -key mailserver_dovecot.key -out mailserver_dovecot.csr<<EOF
FR
France
Paris
Dovecot certificate
Mail
*.${DOMAIN}
admin@${DOMAIN}


EOF

echo -e "\n\n${CGREEN}-> Signature des certificats${CEND}"
openssl x509 -req -days 3658 -sha256 -in mailserver_postfix.csr -CA mailserver_ca.crt -CAkey mailserver_ca.key -CAcreateserial -out mailserver_postfix.crt
openssl x509 -req -days 3658 -sha256 -in mailserver_dovecot.csr -CA mailserver_ca.crt -CAkey mailserver_ca.key -CAcreateserial -out mailserver_dovecot.crt

echo -e "\n${CGREEN}-> Modification des permissions${CEND}"
chmod 400 mailserver_ca.key
chmod 444 mailserver_ca.crt
chmod 400 mailserver_postfix.key
chmod 444 mailserver_postfix.crt
chmod 400 mailserver_dovecot.key
chmod 444 mailserver_dovecot.crt

# Si on a redirigé le port 80 vers un autre port, cela peut vouloir dire que le 443 n'est pas non plus accessible, NAT, VM, ...
# On demande si on veut faire du HTTPS
echo ""
read -rp "Souhaitez-vous utiliser SSL/TLS (HTTPS - port 443) pour les interfaces web ? [O]/n : " SSL_OK

# Valeur par défaut
if [[ -z "${SSL_OK// }" ]]; then
    SSL_OK="O"
fi

if [[ "$SSL_OK" = "O" ]] || [[ "$SSL_OK" = "o" ]]; then

    echo -e "\n${CGREEN}-> Création du certificat de Nginx${CEND}"
    openssl genrsa -out mailserver_nginx.key 4096
    openssl req -new -sha256 -key mailserver_nginx.key -out mailserver_nginx.csr<<EOF
FR
France
Paris
Nginx certificate
Web
*.${DOMAIN}
admin@${DOMAIN}


EOF

    openssl x509 -req -days 3658 -sha256 -in mailserver_nginx.csr -CA mailserver_ca.crt -CAkey mailserver_ca.key -CAcreateserial -out mailserver_nginx.crt

    chmod 400 mailserver_nginx.key
    chmod 444 mailserver_nginx.crt

    mv mailserver_nginx.key private/
    mv mailserver_nginx.crt certs/
fi

echo -e "\n${CGREEN}-> Déplacement des certificats dans /etc/ssl/certs et /etc/ssl/private${CEND}"
mv mailserver_ca.key      private/
mv mailserver_postfix.key private/
mv mailserver_dovecot.key private/
mv mailserver_ca.crt      certs/
mv mailserver_postfix.crt certs/
mv mailserver_dovecot.crt certs/

smallLoader
clear

echo ""
echo -e "${CCYAN}-----------------------------${CEND}"
echo -e "${CCYAN}[  INSTALLATION DE POSTFIX  ]${CEND}"
echo -e "${CCYAN}-----------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Installation de postfix, postfix-mysql et PHP-IMAP ${CEND}"
echo ""

# php5-imap pour Postfixadmin & php5-curl pour rainloop
apt-get install -y postfix postfix-mysql php5-imap php5-curl

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n ${CRED}/!\ FATAL: Une erreur est survenue pendant l'installation de Postfix.${CEND}" 1>&2
    echo ""
    exit 1
fi

smallLoader
clear

echo -e "${CCYAN}-------------------------------------------${CEND}"
echo -e "${CCYAN}[  CREATION DE LA BASE DE DONNEE POSTFIX  ]${CEND}"
echo -e "${CCYAN}-------------------------------------------${CEND}"
echo ""

echo ""
echo -e "${CGREEN}------------------------------------------------------------------${CEND}"
read -rsp "> Veuillez saisir le mot de passe de l'utilisateur root de MySQL : " MYSQLPASSWD
echo ""
echo -e "${CGREEN}------------------------------------------------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Création de la base de donnée Postfix ${CEND}"
until mysqladmin -uroot -p"$MYSQLPASSWD" create postfix &> /tmp/mysql-resp.tmp
do
    fgrep -q "database exists" /tmp/mysql-resp.tmp

    # La base de donnée existe déjà ??
    # Si c'est le cas, on arrête l'installation
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "\n ${CRED}/!\ FATAL: La base de donnée Postfix existe déjà.${CEND}" 1>&2
        echo -e "${CRED}Si une installation a déjà été effectuée merci de${CEND}" 1>&2
        echo -e "${CRED}lancer le script de désinstallation puis de re-tenter${CEND}" 1>&2
        echo -e "${CRED}une installation.${CEND}" 1>&2
        echo ""
        exit 1
    fi

    # La base de donnée n'existe pas donc c'est le mot de passe qui n'est pas bon
    echo -e "${CRED}\n /!\ ERREUR: Mot de passe root incorrect \n ${CEND}" 1>&2
    read -rsp "> Veuillez re-saisir le mot de passe : " MYSQLPASSWD
    echo -e ""
done

echo -e "${CGREEN}-> Génération du mot de passe de l'utilisateur Postfix ${CEND}"
PFPASSWD=$(strings /dev/urandom | grep -o '[1-9A-NP-Za-np-z]' | head -n 10 | tr -d '\n')
SQLQUERY="CREATE USER 'postfix'@'localhost' IDENTIFIED BY '${PFPASSWD}'; \
          GRANT USAGE ON *.* TO 'postfix'@'localhost'; \
          GRANT ALL PRIVILEGES ON postfix.* TO 'postfix'@'localhost';"

echo -e "${CGREEN}-> Création de l'utilisateur Postfix ${CEND}"
mysql -uroot -p"$MYSQLPASSWD" "postfix" -e "$SQLQUERY" &> /dev/null

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n ${CRED}/!\ FATAL: un problème est survenu lors de la création de l'utilisateur 'postfix' dans la BDD.${CEND}" 1>&2
    echo ""
    exit 1
fi

smallLoader
clear

# ##########################################################################

echo -e "${CCYAN}----------------------------------${CEND}"
echo -e "${CCYAN}[  INSTALLATION DE POSTFIXADMIN  ]${CEND}"
echo -e "${CCYAN}----------------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Téléchargement de PostfixAdmin ${CEND}"
echo ""

if [[ ! -d /var/www ]]; then
    mkdir -p /var/www
    chown -R www-data:www-data /var/www
fi

cd /var/www || exit
URLPFA="http://freefr.dl.sourceforge.net/project/postfixadmin/postfixadmin/postfixadmin-${POSTFIXADMIN_VER}/postfixadmin-${POSTFIXADMIN_VER}.tar.gz"

until wget $URLPFA
do
    echo -e "${CRED}\n/!\ ERREUR: L'URL de téléchargement de PostfixAdmin est invalide !${CEND}" 1>&2
    echo -e "${CRED}/!\ Merci de rapporter cette erreur ici :${CEND}" 1>&2
    echo -e "${CCYAN}-> https://github.com/hardware/mailserver-autoinstall/issues${CEND} \n" 1>&2
    echo "> Veuillez saisir une autre URL pour que le script puisse télécharger PostfixAdmin : "
    read -rp "[URL] : " URLPFA
    echo -e ""
done

# On vérifie la présence de l'archive
if [[ ! -f postfixadmin-$POSTFIXADMIN_VER.tar.gz ]]; then
    echo ""
    echo -e "\n ${CRED}/!\ FATAL: L'archive de Postfixadmin est introuvable.${CEND}" 1>&2
    echo ""
    exit 1
fi

echo -e "${CGREEN}-> Décompression de PostfixAdmin ${CEND}"
tar -xzf postfixadmin-$POSTFIXADMIN_VER.tar.gz

echo -e "${CGREEN}-> Création du répertoire /var/www/postfixadmin ${CEND}"
mv postfixadmin-$POSTFIXADMIN_VER postfixadmin
rm -rf postfixadmin-$POSTFIXADMIN_VER.tar.gz

echo -e "${CGREEN}-> Modification des permissions ${CEND}"
chown -R www-data:www-data postfixadmin

PFACONFIG="/var/www/postfixadmin/config.inc.php"

echo -e "${CGREEN}-> Modification du fichier de configuration de PostfixAdmin ${CEND}"
sed -i -e "s|\($CONF\['configured'\].*=\).*|\1 true;|"                 \
       -e "s|\($CONF\['default_language'\] =\).*|\1 'fr';|"            \
       -e "s|\($CONF\['database_type'\].*=\).*|\1 'mysqli';|"          \
       -e "s|\($CONF\['database_host'\].*=\).*|\1 'localhost';|"       \
       -e "s|\($CONF\['database_user'\].*=\).*|\1 'postfix';|"         \
       -e "s|\($CONF\['database_password'\].*=\).*|\1 '${PFPASSWD}';|" \
       -e "s|\($CONF\['database_name'\].*=\).*|\1 'postfix';|"         \
       -e "s|\($CONF\['admin_email'\].*=\).*|\1 'admin@${DOMAIN}';|"   \
       -e "s|\($CONF\['domain_path'\].*=\).*|\1 'YES';|"               \
       -e "s|\($CONF\['domain_in_mailbox'\].*=\).*|\1 'NO';|"          \
       -e "s|\($CONF\['fetchmail'\].*=\).*|\1 'NO';|" $PFACONFIG

echo ""
echo -e "${CCYAN}-----------------------------------------------------------${CEND}"
read -rp "> Sous-domaine de PostfixAdmin [Par défaut : postfixadmin] : " PFADOMAIN
read -rp "> Chemin du fichier PASSWD [Par défaut : /etc/nginx/passwdfile] : " PASSWDPATH
echo -e "${CCYAN}-----------------------------------------------------------${CEND}"
echo ""

if [[ -z "${PFADOMAIN// }" ]]; then
    PFADOMAIN="postfixadmin"
fi

if [[ -z "${PASSWDPATH// }" ]]; then
    PASSWDPATH="/etc/nginx/passwdfile"
fi

if [[ ! -s "$PASSWDPATH" ]] || [[ ! -f "$PASSWDPATH" ]]; then

    USERAUTH="admin"
    PASSWDAUTH="1234"

    echo -e "${CCYAN}-----------------------------------------------------------${CEND}"
    echo -e "${CCYAN}Le fichier ${PASSWDPATH} est vide ou n'existe pas.${CEND}"
    echo -e "${CCYAN}Veuillez entrer les informations suivantes :${CEND}"
    read -rp "> Nom d'utilisateur [Par défaut : Admin] : " USERAUTH
    read -rsp "> Mot de passe [Par défaut : 1234] : " PASSWDAUTH
    echo -e "${CCYAN}-----------------------------------------------------------${CEND}"
    # printf "${USERAUTH}:$(openssl passwd -crypt ${PASSWDAUTH})\n" >> $PASSWDPATH - crypt() Max 8 caractères
    printf "${USERAUTH}:$(openssl passwd -apr1 ${PASSWDAUTH})\n" >> $PASSWDPATH # apr1 (Apache MD5) encryption

    smallLoader
    echo ""

fi

echo -e "${CGREEN}-> Ajout du vhost postfixadmin ${CEND}"
if [[ "$SSL_OK" = "O" ]] || [[ "$SSL_OK" = "o" ]]; then
cat > /etc/nginx/sites-enabled/postfixadmin.conf <<EOF
server {
    listen          ${PORT};
    server_name     ${PFADOMAIN}.${DOMAIN};
    return 301      https://\$server_name\$request_uri; # enforce https
}

server {
    listen          443 ssl;
    server_name     ${PFADOMAIN}.${DOMAIN};
    root            /var/www/postfixadmin;
    index           index.php;
    charset         utf-8;

    ## SSL settings
    ssl_certificate           /etc/ssl/certs/mailserver_nginx.crt;
    ssl_certificate_key       /etc/ssl/private/mailserver_nginx.key;
    ssl_protocols             TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers               "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK";
    ssl_prefer_server_ciphers on;
    ssl_session_cache         shared:SSL:10m;
    ssl_session_timeout       10m;
    ssl_ecdh_curve            secp384r1;

    add_header Strict-Transport-Security max-age=31536000;

    auth_basic "PostfixAdmin - Connexion";
    auth_basic_user_file ${PASSWDPATH};

    location / {
        try_files \$uri \$uri/ index.php;
    }

    location ~* \.php$ {
        include       /etc/nginx/fastcgi_params;
        fastcgi_pass  unix:/var/run/php5-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
else
cat > /etc/nginx/sites-enabled/postfixadmin.conf <<EOF
server {
    listen          ${PORT};
    server_name     ${PFADOMAIN}.${DOMAIN};
    root            /var/www/postfixadmin;
    index           index.php;
    charset         utf-8;

    auth_basic "PostfixAdmin - Connexion";
    auth_basic_user_file ${PASSWDPATH};

    location / {
        try_files \$uri \$uri/ index.php;
    }

    location ~* \.php$ {
        include       /etc/nginx/fastcgi_params;
        fastcgi_pass  unix:/var/run/php5-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
fi

echo -e "${CGREEN}-> Redémarrage de PHP-FPM.${CEND}"
service php5-fpm restart

echo -e "${CGREEN}-> Redémarrage de nginx pour prendre en compte le nouveau vhost.${CEND}"
service nginx restart

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "${CRED}/!\ ECHEC: un problème est survenu lors du redémarrage de Nginx.${CEND}" 1>&2
    echo -e "${CRED}/!\ Ouvrez une nouvelle session dans un autre terminal et${CEND}" 1>&2
    echo -e "${CRED}/!\ consultez le fichier de log :${CEND} ${CCYAN}/var/log/nginx/errors.log${CEND}" 1>&2
    echo -e "${CRED}/!\ Une fois le problème résolu, appuyez sur [ENTRÉE]...${CEND}" 1>&2
    smallLoader
    echo ""
fi

echo ""
echo -e "${CBROWN}---------------------------------------------------------------------------${CEND}"
echo -e "${CBROWN}Ajoutez la ligne ci-dessous dans le fichier Hosts de votre pc"
echo -e "${CBROWN}si votre nom de domaine n'est pas encore configuré pour"
echo -e "${CBROWN}le sous-domaine${CEND} ${CYELLOW}${PFADOMAIN}.${DOMAIN}${CEND}"
echo ""
echo -e "${CYELLOW}  ${WANIP}     ${PFADOMAIN}.${DOMAIN}${CEND}"
echo ""
echo -e "${CBROWN} - Windows : c:\windows\system32\driver\etc\hosts ${CEND}"
echo -e "${CBROWN} - Linux/MAC : /etc/hosts ${CEND}"
echo ""
echo -e "${CBROWN}Pour finaliser l'installation de PostfixAdmin, allez à l'adresse suivante : ${CEND}"
echo ""
echo -e "${CYELLOW}> http://${PFADOMAIN}.${DOMAIN}/setup.php${CEND}"
echo ""
echo -e "${CBROWN}Veuillez vous assurer que tous les pré-requis ont été validés.${CEND}"
echo -e "${CBROWN}Une fois votre compte administrateur créé, saisissez le hash généré.${CEND}"
echo ""
read -rp "> Veuillez saisir le hash généré par le setup : " PFAHASH
echo ""
echo -e "${CBROWN}---------------------------------------------------------------------------${CEND}"
echo ""

# Le hash généré par PFA à une taille de 73 caractères :
# MD5(salt) : SHA1( MD5(salt) : PASSWORD );
#    32     1              40
# Exemple : ffdeb741c58db80d060ddb170af4623a:54e0ac9a55d69c5e53d214c7ad7f1e3df40a3caa
while [ ${#PFAHASH} -ne 73 ]; do
    echo -e "${CRED}\n/!\ HASH invalide !${CEND}" 1>&2
    read -rp "> Veuillez saisir de nouveau le hash généré par le setup : " PFAHASH
    echo -e ""
done

echo -e "${CGREEN}-> Ajout du hash dans le fichier config.inc.php ${CEND}"
sed -i "s|\($CONF\['setup_password'\].*=\).*|\1 '${PFAHASH}';|" $PFACONFIG

echo ""
echo -e "${CBROWN}---------------------------------------------------------------------------${CEND}"
echo -e "${CBROWN}Vous pouvez dès à présent vous connecter à PostfixAdmin avec votre compte administrateur.${CEND}"
echo ""
echo -e "${CYELLOW}> http://${PFADOMAIN}.${DOMAIN}/login.php${CEND}"
echo ""
echo -e "${CBROWN}Veuillez ajouter au minimum les éléments ci-dessous :${CEND}"
echo -e "${CBROWN} - Votre domaine :${CEND} ${CGREEN}${DOMAIN}${CEND}"
echo -e "${CBROWN} - Une adresse email :${CEND} ${CGREEN}admin@${DOMAIN}${CEND}"
echo -e "${CBROWN}---------------------------------------------------------------------------${CEND}"
echo ""

echo ""
echo -e "${CRED}-----------------------------------------------------------------------------------${CEND}"
echo -e "${CRED} /!\ N'APPUYEZ PAS SUR ENTREE AVANT D'AVOIR EFFECTUÉ TOUT CE QUI EST AU DESSUS /!\ ${CEND}"
echo -e "${CRED}-----------------------------------------------------------------------------------${CEND}"
echo ""

smallLoader
clear

# ##########################################################################

echo -e "${CCYAN}------------------------------${CEND}"
echo -e "${CCYAN}[  CONFIGURATION DE POSTFIX  ]${CEND}"
echo -e "${CCYAN}------------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Mise en place du fichier /etc/postfix/master.cf${CEND}"
sed -i -e "0,/#\(.*smtp\([^s]\).*inet.*n.*smtpd.*\)/s/#\(.*smtp\([^s]\).*inet.*n.*smtpd.*\)/\1/" \
       -e "s/#\(.*submission.*inet.*n.*\)/\1/" \
       -e "s/#\(.*syslog_name=postfix\/submission\)/\1/" \
       -e "s/#\(.*smtpd_tls_security_level=encrypt\)/\1/" \
       -e "0,/#\(.*smtpd_sasl_auth_enable=yes\)/s/#\(.*smtpd_sasl_auth_enable=yes\)/\1/" /etc/postfix/master.cf

sed -i '/\(.*syslog_name=postfix\/submission\)/a \ \ -o smtpd_tls_dh1024_param_file=${config_directory}/dh2048.pem' /etc/postfix/master.cf

echo -e "${CGREEN}-> Génération des paramètres Diffie–Hellman${CEND}"
echo -e "${CRED}\n/!\ INFO: Merci d'être patient, cette étape peut prendre plusieurs dizaines de minutes sur certains serveurs.${CEND}" 1>&2
echo ""
openssl dhparam -out /etc/postfix/dh2048.pem 2048
openssl dhparam -out /etc/postfix/dh512.pem 512

echo -e "${CGREEN}-> Mise en place du fichier /etc/postfix/main.cf ${CEND}"
cat > /etc/postfix/main.cf <<EOF
#######################
## GENERALS SETTINGS ##
#######################

smtpd_banner         = \$myhostname ESMTP \$mail_name (Debian/GNU)
biff                 = no
append_dot_mydomain  = no
readme_directory     = no
delay_warning_time   = 4h
mailbox_command      = procmail -a "\$EXTENSION"
recipient_delimiter  = +
disable_vrfy_command = yes
message_size_limit   = 502400000
mailbox_size_limit   = 1024000000

inet_interfaces = all
inet_protocols = ipv4

myhostname    = ${FQDN}
myorigin      = ${FQDN}
mydestination = localhost localhost.\$mydomain
mynetworks    = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
relayhost     =

alias_maps     = hash:/etc/aliases
alias_database = hash:/etc/aliases

####################
## TLS PARAMETERS ##
####################

# SMTP ( OUTGOING / Client )
# ----------------------------------------------------------------------
smtp_tls_loglevel            = 1
smtp_tls_security_level      = may
smtp_tls_CAfile              = /etc/ssl/certs/mailserver_ca.crt
smtp_tls_protocols           = !SSLv2, !SSLv3
smtp_tls_mandatory_protocols = !SSLv2, !SSLv3
smtp_tls_mandatory_ciphers   = high
smtp_tls_exclude_ciphers     = aNULL, eNULL, EXPORT, DES, 3DES, RC2, RC4, MD5, PSK, SRP, DSS, AECDH, ADH
smtp_tls_note_starttls_offer = yes

# SMTPD ( INCOMING / Server )
# ----------------------------------------------------------------------
smtpd_tls_loglevel            = 1
smtpd_tls_auth_only           = yes
smtpd_tls_security_level      = may
smtpd_tls_received_header     = yes
smtpd_tls_protocols           = !SSLv2, !SSLv3
smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3
smtpd_tls_mandatory_ciphers   = medium

# Infos (voir : postconf -d)
# Medium cipherlist = aNULL:-aNULL:ALL:!EXPORT:!LOW:+RC4:@STRENGTH
# High cipherlist   = aNULL:-aNULL:ALL:!EXPORT:!LOW:!MEDIUM:+RC4:@STRENGTH

# smtpd_tls_exclude_ciphers   = NE PAS modifier cette directive pour des raisons de compatibilité
#                               avec les autres serveurs de mail afin d'éviter une erreur du type
#                               "no shared cipher" ou "no cipher overlap" puis un fallback en
#                               plain/text...
# smtpd_tls_cipherlist        = Ne pas modifier non plus !

smtpd_tls_CAfile              = \$smtp_tls_CAfile
smtpd_tls_cert_file           = /etc/ssl/certs/mailserver_postfix.crt
smtpd_tls_key_file            = /etc/ssl/private/mailserver_postfix.key
smtpd_tls_dh1024_param_file   = \$config_directory/dh2048.pem
smtpd_tls_dh512_param_file    = \$config_directory/dh512.pem

smtp_tls_session_cache_database  = btree:\${data_directory}/smtp_scache
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
lmtp_tls_session_cache_database  = btree:\${data_directory}/lmtp_scache

tls_preempt_cipherlist = yes
tls_random_source      = dev:/dev/urandom

# ----------------------------------------------------------------------

#####################
## SASL PARAMETERS ##
#####################

smtpd_sasl_auth_enable          = yes
smtpd_sasl_type                 = dovecot
smtpd_sasl_path                 = private/auth
smtpd_sasl_security_options     = noanonymous
smtpd_sasl_tls_security_options = \$smtpd_sasl_security_options
smtpd_sasl_local_domain         = \$mydomain
smtpd_sasl_authenticated_header = yes

broken_sasl_auth_clients = yes

##############################
## VIRTUALS MAPS PARAMETERS ##
##############################

virtual_uid_maps        = static:5000
virtual_gid_maps        = static:5000
virtual_minimum_uid     = 5000
virtual_mailbox_base    = /var/mail
virtual_transport       = lmtp:unix:private/dovecot-lmtp
virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf
virtual_mailbox_maps    = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
virtual_alias_maps      = mysql:/etc/postfix/mysql-virtual-alias-maps.cf
relay_domains           = mysql:/etc/postfix/mysql-relay-domains.cf

######################
## ERRORS REPORTING ##
######################

# notify_classes = bounce, delay, resource, software
notify_classes = resource, software

error_notice_recipient     = admin@domain.tld
# delay_notice_recipient   = admin@domain.tld
# bounce_notice_recipient  = admin@domain.tld
# 2bounce_notice_recipient = admin@domain.tld

##################
## RESTRICTIONS ##
##################

smtpd_recipient_restrictions =
     permit_mynetworks,
     permit_sasl_authenticated,
     reject_non_fqdn_recipient,
     reject_unauth_destination,
     reject_unknown_recipient_domain,
     reject_rbl_client zen.spamhaus.org

smtpd_helo_restrictions =
     permit_mynetworks,
     permit_sasl_authenticated,
     reject_invalid_helo_hostname,
     reject_non_fqdn_helo_hostname
     # reject_unknown_helo_hostname

smtpd_client_restrictions =
     permit_mynetworks,
     permit_inet_interfaces,
     permit_sasl_authenticated
     # reject_plaintext_session,
     # reject_unauth_pipelining

smtpd_sender_restrictions =
     reject_non_fqdn_sender,
     reject_unknown_sender_domain
EOF

if [[ "$DEBIAN_VER" = "8" ]]; then

cat >> /etc/postfix/main.cf <<EOF

smtpd_relay_restrictions =
     permit_mynetworks,
     reject_unknown_sender_domain,
     permit_sasl_authenticated,
     reject_unauth_destination
EOF

fi

echo ""
echo -e "${CGREEN}-> Création du fichier mysql-virtual-mailbox-domains.cf ${CEND}"

cat > /etc/postfix/mysql-virtual-mailbox-domains.cf <<EOF
hosts = 127.0.0.1
user = postfix
password = ${PFPASSWD}
dbname = postfix

query = SELECT domain FROM domain WHERE domain='%s' and backupmx = 0 and active = 1
EOF

echo -e "${CGREEN}-> Création du fichier mysql-virtual-mailbox-maps.cf ${CEND}"

cat > /etc/postfix/mysql-virtual-mailbox-maps.cf <<EOF
hosts = 127.0.0.1
user = postfix
password = ${PFPASSWD}
dbname = postfix

query = SELECT maildir FROM mailbox WHERE username='%s' AND active = 1
EOF

echo -e "${CGREEN}-> Création du fichier mysql-virtual-alias-maps.cf ${CEND}"

cat > /etc/postfix/mysql-virtual-alias-maps.cf <<EOF
hosts = 127.0.0.1
user = postfix
password = ${PFPASSWD}
dbname = postfix

query = SELECT goto FROM alias WHERE address='%s' AND active = 1
EOF

echo -e "${CGREEN}-> Création du fichier mysql-relay-domains.cf ${CEND}"

cat > /etc/postfix/mysql-relay-domains.cf <<EOF
hosts = 127.0.0.1
user = postfix
password = ${PFPASSWD}
dbname = postfix

query = SELECT domain FROM domain WHERE domain='%s' and backupmx = 1
EOF

smallLoader
clear

echo -e "${CCYAN}-----------------------------${CEND}"
echo -e "${CCYAN}[  INSTALLATION DE DOVECOT  ]${CEND}"
echo -e "${CCYAN}-----------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Installation de dovecot-core, dovecot-imapd, dovecot-lmtpd et dovecot-mysql ${CEND}"
echo ""
apt-get install -y dovecot-core dovecot-imapd dovecot-lmtpd dovecot-mysql

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n ${CRED}/!\ FATAL: Une erreur est survenue pendant l'installation de Dovecot.${CEND}" 1>&2
    echo ""
    smallLoader
fi

echo ""
echo -e "${CGREEN}-> Création du conteneur MAILDIR ${CEND}"
mkdir -p /var/mail/vhosts/"${DOMAIN}"

echo -e "${CGREEN}-> Création d'un nouvel utilisateur nommé vmail avec un UID/GID de 5000 ${CEND}"
groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/mail
chown -R vmail:vmail /var/mail

echo -e "${CGREEN}-> Positionnement des droits sur le répertoire /etc/dovecot ${CEND}"
chown -R vmail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

echo ""
echo -e "${CGREEN}-> Mise en place du fichier /etc/dovecot/dovecot.conf ${CEND}"
cat > /etc/dovecot/dovecot.conf <<EOF
!include_try /usr/share/dovecot/protocols.d/*.protocol
protocols = imap lmtp
listen = *
!include conf.d/*.conf
EOF

echo -e "${CGREEN}-> Mise en place du fichier /etc/dovecot/conf.d/10-mail.conf ${CEND}"
cat > /etc/dovecot/conf.d/10-mail.conf <<EOF
mail_location = maildir:/var/mail/vhosts/%d/%n/mail
maildir_stat_dirs=yes

namespace inbox {
    inbox = yes
}

mail_uid = 5000
mail_gid = 5000

first_valid_uid = 5000
last_valid_uid = 5000

mail_privileged_group = vmail
EOF

echo -e "${CGREEN}-> Mise en place du fichier /etc/dovecot/conf.d/10-auth.conf ${CEND}"
cat > /etc/dovecot/conf.d/10-auth.conf <<EOF
disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-sql.conf.ext
EOF

echo -e "${CGREEN}-> Mise en place du fichier /etc/dovecot/conf.d/auth-sql.conf.ext ${CEND}"
cat > /etc/dovecot/conf.d/auth-sql.conf.ext <<EOF
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}

userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}
EOF

echo -e "${CGREEN}-> Mise en place du fichier /etc/dovecot/dovecot-sql.conf.ext ${CEND}"
cat > /etc/dovecot/dovecot-sql.conf.ext <<EOF
# Paramètres de connexion
driver = mysql
connect = host=127.0.0.1 dbname=postfix user=postfix password=${PFPASSWD}

# Permet de définir l'algorithme de hachage.
# Pour plus d'information: http://wiki2.dovecot.org/Authentication/PasswordSchemes
# /!\ ATTENTION : ne pas oublier de modifier le paramètre \$CONF['encrypt'] de PostfixAdmin
default_pass_scheme = MD5-CRYPT

# Requête de récupération du mot de passe du compte utilisateur
password_query = SELECT password FROM mailbox WHERE username = '%u'
EOF

echo -e "${CGREEN}-> Mise en place du fichier /etc/dovecot/conf.d/10-master.conf ${CEND}"
cat > /etc/dovecot/conf.d/10-master.conf <<EOF
service imap-login {

    inet_listener imap {
        port = 143
    }

    inet_listener imaps {
        port = 993
        ssl = yes
    }

    service_count = 0

}

service imap {

}

service lmtp {

    unix_listener /var/spool/postfix/private/dovecot-lmtp {
        mode = 0600
        user = postfix
        group = postfix
    }

}

service auth {

    unix_listener /var/spool/postfix/private/auth {
        mode = 0666
        user = postfix
        group = postfix
    }

    unix_listener auth-userdb {
        mode = 0600
        user = vmail
        group = vmail
    }

    user = dovecot

}

service auth-worker {

    user = vmail

}
EOF

echo -e "${CGREEN}-> Mise en place du fichier /etc/dovecot/conf.d/10-ssl.conf ${CEND}"
cat > /etc/dovecot/conf.d/10-ssl.conf <<EOF
ssl = required
ssl_cert = </etc/ssl/certs/mailserver_dovecot.crt
ssl_key = </etc/ssl/private/mailserver_dovecot.key
ssl_protocols = !SSLv2 !SSLv3
ssl_cipher_list = ALL:!aNULL:!eNULL:!LOW:!MEDIUM:!EXP:!RC2:!RC4:!DES:!3DES:!MD5:!PSK:!SRP:!DSS:!AECDH:!ADH:@STRENGTH
EOF

if [[ "$DEBIAN_VER" = "8" ]]; then

cat >> /etc/dovecot/conf.d/10-ssl.conf <<EOF
ssl_prefer_server_ciphers = yes
ssl_dh_parameters_length = 2048
EOF

fi

smallLoader
clear

# ##########################################################################

echo -e "${CCYAN}-----------------------------${CEND}"
echo -e "${CCYAN}[  INSTALLATION D'OPENDKIM  ]${CEND}"
echo -e "${CCYAN}-----------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Installation de opendkim et opendkim-tools ${CEND}"
echo ""
apt-get install -y opendkim opendkim-tools

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n ${CRED}/!\ FATAL: Une erreur est survenue pendant l'installation d'OpenDKIM.${CEND}" 1>&2
    echo ""
    exit 1
fi

echo ""
echo -e "${CGREEN}-> Mise en place du fichier /etc/opendkim.conf ${CEND}"
cat > /etc/opendkim.conf <<EOF
AutoRestart             Yes
AutoRestartRate         10/1h
UMask                   002
Syslog                  Yes
SyslogSuccess           Yes
LogWhy                  Yes

OversignHeaders         From
AlwaysAddARHeader       Yes

Canonicalization        relaxed/simple

ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable

Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256

UserID                  opendkim:opendkim

Socket                  local:/var/spool/postfix/opendkim/opendkim.sock
EOF

echo -e "${CGREEN}-> Création du répertoire /var/spool/postfix/opendkim${CEND}"
mkdir /var/spool/postfix/opendkim
chown opendkim: /var/spool/postfix/opendkim
usermod -aG opendkim postfix

echo -e "${CGREEN}-> Mise à jour du fichier de configuration de Postfix ${CEND}"
cat >> /etc/postfix/main.cf <<EOF

#############
## MILTERS ##
#############

milter_protocol = 6
milter_default_action = accept
smtpd_milters = unix:/opendkim/opendkim.sock
non_smtpd_milters = unix:/opendkim/opendkim.sock
EOF

echo -e "${CGREEN}-> Création du répertoire /etc/opendkim ${CEND}"
mkdir -p /etc/opendkim/keys

echo -e "${CGREEN}-> Mise en place du fichier /etc/opendkim/TrustedHosts ${CEND}"
cat > /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
::1
*.${DOMAIN}
EOF

echo -e "${CGREEN}-> Mise en place du fichier /etc/opendkim/KeyTable ${CEND}"
cat > /etc/opendkim/KeyTable <<EOF
mail._domainkey.${DOMAIN} ${DOMAIN}:mail:/etc/opendkim/keys/${DOMAIN}/mail.private
EOF

echo -e "${CGREEN}-> Mise en place du fichier /etc/opendkim/SigningTable ${CEND}"
cat > /etc/opendkim/SigningTable <<EOF
*@${DOMAIN} mail._domainkey.${DOMAIN}
EOF

echo ""
echo -e "${CPURPLE}-----------------------------------${CEND}"
echo -e "${CPURPLE}[  CREATION DES CLÉS DE SÉCURITÉ  ]${CEND}"
echo -e "${CPURPLE}-----------------------------------${CEND}"
echo ""

cd /etc/opendkim/keys || exit

echo -e "${CGREEN}-> Création du répertoire /etc/opendkim/keys/${DOMAIN} ${CEND}"
mkdir "$DOMAIN" && cd "$DOMAIN" || exit

echo -e "${CGREEN}-> Génération des clés de chiffrement ${CEND}"
opendkim-genkey -s mail -d "$DOMAIN" -b 1024

echo -e "${CGREEN}-> Modification des permissions des clés ${CEND}"
chown opendkim:opendkim mail.private
chmod 400 mail.private mail.txt

smallLoader
clear

# ##########################################################################

if [[ "$DEBIAN_VER" = "8" ]]; then

echo -e "${CCYAN}------------------------------${CEND}"
echo -e "${CCYAN}[  INSTALLATION D'OPENDMARC  ]${CEND}"
echo -e "${CCYAN}------------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Installation de opendmarc ${CEND}"
echo ""
apt-get install -y opendmarc

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n ${CRED}/!\ FATAL: Une erreur est survenue pendant l'installation d'OpenDMARC.${CEND}" 1>&2
    echo ""
    exit 1
fi

echo ""
echo -e "${CGREEN}-> Mise en place du fichier /etc/opendmarc.conf ${CEND}"
cat > /etc/opendmarc.conf <<EOF
AutoRestart             Yes
AutoRestartRate         10/1h
UMask                   0002
Syslog                  true

AuthservID              "${FQDN}"
TrustedAuthservIDs      "${FQDN}"
IgnoreHosts             /etc/opendkim/TrustedHosts

RejectFailures          false

UserID                  opendmarc:opendmarc
PidFile                 /var/run/opendmarc.pid
Socket                  local:/var/spool/postfix/opendmarc/opendmarc.sock
EOF

echo -e "${CGREEN}-> Création du répertoire /var/spool/postfix/opendmarc${CEND}"
mkdir /var/spool/postfix/opendmarc
chown opendmarc: /var/spool/postfix/opendmarc
usermod -aG opendmarc postfix

echo -e "${CGREEN}-> Modification du fichier /etc/postfix/main.cf${CEND}"
postconf -e smtpd_milters="unix:/opendkim/opendkim.sock, unix:/opendmarc/opendmarc.sock"

smallLoader
clear

fi

# ##########################################################################

echo -e "${CCYAN}----------------------------------${CEND}"
echo -e "${CCYAN}[  INSTALLATION DE SPAMASSASSIN  ]${CEND}"
echo -e "${CCYAN}----------------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Installation de spamassassin et spamc${CEND}"
echo ""
apt-get install -y spamassassin spamc

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n ${CRED}/!\ FATAL: Une erreur est survenue pendant l'installation de Spamassassin.${CEND}" 1>&2
    echo ""
    exit 1
fi

echo -e "${CGREEN}-> Modification du fichier /etc/postfix/master.cf${CEND}"
sed -i '/\(.*smtp\([^s]\).*inet.*n.*smtpd.*\)/a \ \ -o content_filter=spamassassin' /etc/postfix/master.cf
sed -i '/\(.*submission.*inet.*n.*smtpd.*\)/a \ \ -o content_filter=spamassassin' /etc/postfix/master.cf

cat >> /etc/postfix/master.cf <<EOF
spamassassin unix -     n       n       -       -       pipe
  user=debian-spamd argv=/usr/bin/spamc -f -e /usr/sbin/sendmail -oi -f \${sender} \${recipient}
EOF

echo -e "${CGREEN}-> Modification du fichier /etc/spamassassin/local.cf${CEND}"
cat > /etc/spamassassin/local.cf <<EOF
rewrite_header Subject *****SPAM*****
report_safe 0
whitelist_from *@${DOMAIN}

add_header all Report _REPORT_
add_header spam Flag _YESNOCAPS_
add_header all Status _YESNO_, score=_SCORE_ required=_REQD_ tests=_TESTS_ autolearn=_AUTOLEARN_ version=_VERSION_
add_header all Level _STARS(*)_
add_header all Checker-Version SpamAssassin _VERSION_ (_SUBVERSION_) on _HOSTNAME_
EOF

echo -e "${CGREEN}-> Modification du fichier /etc/default/spamassassin${CEND}"
sed -i "s|\(CRON.*=\).*|\11|" /etc/default/spamassassin

if [[ "$DEBIAN_VER" = "7" ]]; then
    # ENABLED=1 pour les systèmes qui utilisent sysvinit
    sed -i "s|\(ENABLED.*=\).*|\11|" /etc/default/spamassassin
fi

if [[ "$DEBIAN_VER" = "8" ]]; then
    # ENABLED=0 pour les systèmes qui utilisent systemd
    sed -i "s|\(ENABLED.*=\).*|\10|" /etc/default/spamassassin
fi

echo -e "${CGREEN}-> Modification du crontab${CEND}"
(crontab -l ; echo "20 02 * * * /usr/bin/sa-update") | crontab -

smallLoader
clear

# ##########################################################################

echo -e "${CCYAN}--------------------------${CEND}"
echo -e "${CCYAN}[  INSTALLATION DE SIEVE ]${CEND}"
echo -e "${CCYAN}--------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Installation de dovecot-sieve et dovecot-managesieved${CEND}"
echo ""
apt-get install -y dovecot-sieve dovecot-managesieved

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n ${CRED}/!\ FATAL: Une erreur est survenue pendant l'installation de Sieve.${CEND}" 1>&2
    echo ""
    exit 1
fi

echo -e "${CGREEN}-> Modification du fichier /etc/dovecot/dovecot.conf${CEND}"
sed -i -e "s|\(protocols.*=\).*|\1 imap lmtp sieve|" /etc/dovecot/dovecot.conf

echo -e "${CGREEN}-> Modification du fichier /etc/dovecot/conf.d/20-lmtp.conf${CEND}"
cat > /etc/dovecot/conf.d/20-lmtp.conf <<EOF
protocol lmtp {

  postmaster_address = postmaster@${DOMAIN}
  mail_plugins = $mail_plugins sieve

}
EOF

echo -e "${CGREEN}-> Modification du fichier /etc/dovecot/conf.d/90-sieve.conf${CEND}"
cat > /etc/dovecot/conf.d/90-sieve.conf <<EOF
plugin {

    sieve = /var/mail/vhosts/%d/%n/.dovecot.sieve
    sieve_default = /var/mail/sieve/default.sieve
    sieve_dir = /var/mail/vhosts/%d/%n/sieve
    sieve_global_dir = /var/mail/sieve

}
EOF

echo -e "${CGREEN}-> Création du répertoire /var/mail/sieve${CEND}"
mkdir /var/mail/sieve
touch /var/mail/sieve/default.sieve && chown -R vmail:vmail /var/mail/sieve

echo -e "${CGREEN}-> Création d'une règle pour les spams${CEND}"
cat > /var/mail/sieve/default.sieve <<EOF
require ["fileinto"];

if header :contains "Subject" "*****SPAM*****" {

    fileinto "Junk";

}
EOF

echo -e "${CGREEN}-> Compilation des règles sieve${CEND}"
sievec /var/mail/sieve/default.sieve

smallLoader
clear

# ##########################################################################

echo -e "${CCYAN}------------------------------${CEND}"
echo -e "${CCYAN}[  INSTALLATION DE RAINLOOP  ]${CEND}"
echo -e "${CCYAN}------------------------------${CEND}"
echo ""

URLRAINLOOP="http://repository.rainloop.net/v2/webmail/rainloop-latest.zip"

until wget $URLRAINLOOP
do
    echo -e "${CRED}\n/!\ ERREUR: L'URL de téléchargement de Rainloop est invalide !${CEND}" 1>&2
    echo -e "${CRED}/!\ Merci de rapporter cette erreur ici :${CEND}" 1>&2
    echo -e "${CCYAN}-> https://github.com/hardware/mailserver-autoinstall/issues${CEND} \n" 1>&2
    echo "> Veuillez saisir une autre URL pour que le script puisse télécharger Rainloop : "
    read -rp "[URL] : " URLRAINLOOP
    echo -e ""
done

echo -e "${CGREEN}-> Création du répertoire /var/www/rainloop ${CEND}"
mkdir /var/www/rainloop

echo -e "${CGREEN}-> Décompression de Rainloop dans le répertoire /var/www/rainloop ${CEND}"
unzip rainloop-latest.zip -d /var/www/rainloop > /dev/null

rm -rf rainloop-latest.zip
cd /var/www/rainloop || exit

echo -e "${CGREEN}-> Modification des permissions ${CEND}"
find . -type d -exec chmod 755 {} \;
find . -type f -exec chmod 644 {} \;
chown -R www-data:www-data .

echo ""
echo -e "${CCYAN}-------------------------------------------------${CEND}"
read -rp "> Sous-domaine de Rainloop [Par défaut : webmail] : " RAINLOOPDOMAIN
echo -e "${CCYAN}-------------------------------------------------${CEND}"
echo ""

if [[ -z "${RAINLOOPDOMAIN// }" ]]; then
    RAINLOOPDOMAIN="webmail"
fi

echo -e "${CGREEN}-> Ajout du vhost rainloop ${CEND}"
if [[ "$SSL_OK" = "O" ]] || [[ "$SSL_OK" = "o" ]]; then
cat > /etc/nginx/sites-enabled/rainloop.conf <<EOF
server {
    listen 	      ${PORT};
    server_name   ${RAINLOOPDOMAIN}.${DOMAIN};
    return 301 	  https://\$server_name\$request_uri; # enforce https
}

server {
    listen        443 ssl;
    server_name   ${RAINLOOPDOMAIN}.${DOMAIN};
    root          /var/www/rainloop;
    index         index.php;
    charset       utf-8;

    ## SSL settings
    ssl_certificate           /etc/ssl/certs/mailserver_nginx.crt;
    ssl_certificate_key       /etc/ssl/private/mailserver_nginx.key;
    ssl_protocols             TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers               "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK";
    ssl_prefer_server_ciphers on;
    ssl_session_cache         shared:SSL:10m;
    ssl_session_timeout       10m;
    ssl_ecdh_curve            secp384r1;

    add_header Strict-Transport-Security max-age=31536000;

    auth_basic "Webmail - Connexion";
    auth_basic_user_file ${PASSWDPATH};

    location ^~ /data {
        deny all;
    }

    location / {
        try_files \$uri \$uri/ index.php;
    }

    location ~* \.php$ {
        include       /etc/nginx/fastcgi_params;
        fastcgi_pass  unix:/var/run/php5-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
else
cat > /etc/nginx/sites-enabled/rainloop.conf <<EOF
server {
    listen 	     ${PORT};
    server_name  ${RAINLOOPDOMAIN}.${DOMAIN};

    root         /var/www/rainloop;
    index        index.php;
    charset      utf-8;

    add_header Strict-Transport-Security max-age=31536000;

    auth_basic "Webmail - Connexion";
    auth_basic_user_file ${PASSWDPATH};

    location ^~ /data {
        deny all;
    }

    location / {
        try_files \$uri \$uri/ index.php;
    }

    location ~* \.php$ {
        include       /etc/nginx/fastcgi_params;
        fastcgi_pass  unix:/var/run/php5-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
fi

echo -e "${CGREEN}-> Redémarrage de PHP-FPM.${CEND}"
service php5-fpm restart
echo -e "${CGREEN}-> Redémarrage de nginx pour prendre en compte le nouveau vhost.${CEND}"
service nginx restart

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "${CRED}/!\ ECHEC: un problème est survenu lors du redémarrage de Nginx.${CEND}" 1>&2
    echo -e "${CRED}/!\ Ouvrez une nouvelle session dans un autre terminal et${CEND}" 1>&2
    echo -e "${CRED}/!\ consultez le fichier de log :${CEND} ${CCYAN}/var/log/nginx/errors.log${CEND}" 1>&2
    echo -e "${CRED}/!\ Une fois le problème résolu, appuyez sur [ENTRÉE]...${CEND}" 1>&2
    smallLoader
    echo ""
fi

smallLoader
clear

# ##########################################################################

echo -e "${CCYAN}------------------------------${CEND}"
echo -e "${CCYAN}[  REDÉMARRAGE DES SERVICES  ]${CEND}"
echo -e "${CCYAN}------------------------------${CEND}"
echo ""

echo -n "-> Redémarrage de Postfix."
service postfix restart

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n${CRED}/!\ FATAL: un problème est survenu lors du redémarrage de Postfix.${CEND}" 1>&2
    echo -e "${CRED}/!\ Consultez le fichier de log /var/log/mail.log${CEND}\n\n" 1>&2
    echo -e "${CRED}POSTFIX: $(service postfix status)${CEND}"  1>&2
    echo ""
    exit 1
fi

echo -e " ${CGREEN}[OK]${CEND}"

echo -n "-> Redémarrage de Dovecot."
service dovecot restart

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n${CRED}/!\ FATAL: un problème est survenu lors du redémarrage de Dovecot.${CEND}" 1>&2
    echo -e "${CRED}/!\ Consultez le fichier de log /var/log/mail.log${CEND}\n\n" 1>&2
    echo -e "${CRED}DOVECOT: $(service dovecot status)${CEND}"  1>&2
    echo ""
    exit 1
fi

echo -e " ${CGREEN}[OK]${CEND}"

echo -n "-> Redémarrage d'OpenDKIM."
service opendkim restart

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n${CRED}/!\ FATAL: un problème est survenu lors du redémarrage d'OpenDKIM.${CEND}\n\n" 1>&2
    echo -e "${CRED}OPENDKIM: $(service opendkim status)${CEND}"  1>&2
    echo ""
    exit 1
fi

echo -e " ${CGREEN}[OK]${CEND}"

if [[ "$DEBIAN_VER" = "8" ]]; then

    echo -n "-> Redémarrage d'OpenDMARC."
    service opendmarc restart

    if [[ $? -ne 0 ]]; then
        echo ""
        echo -e "\n${CRED}/!\ FATAL: un problème est survenu lors du redémarrage d'OpenDMARC.${CEND}\n\n" 1>&2
        echo -e "${CRED}OPENDMARC: $(service OpenDMARC status)${CEND}"  1>&2
        echo ""
        exit 1
    fi

fi

echo -e " ${CGREEN}[OK]${CEND}"

echo -n "-> Redémarrage de SpamAssassin."
service spamassassin restart

if [[ $? -ne 0 ]]; then
    echo ""
    echo -e "\n${CRED}/!\ FATAL: un problème est survenu lors du redémarrage de SpamAssassin.${CEND}\n\n" 1>&2
    echo -e "${CRED}SPAMASSASSIN: $(service spamassassin status)${CEND}"  1>&2
    echo ""
    exit 1
fi

echo -e " ${CGREEN}[OK]${CEND}"

if [[ "$DEBIAN_VER" = "8" ]]; then

    echo -e "\n${CGREEN}-> Activation des services via Systemd\n${CEND}"
    systemctl enable postfix.service
    systemctl enable dovecot.service
    systemctl enable opendkim.service
    systemctl enable opendmarc.service
    systemctl enable spamassassin.service

fi

echo ""
echo -e "${CGREEN}-----------------------------------------${CEND}"
echo -e "${CGREEN}[  INSTALLATION EFFECTUÉE AVEC SUCCÈS ! ]${CEND}"
echo -e "${CGREEN}-----------------------------------------${CEND}"

smallLoader
clear

# ##########################################################################

echo -e "${CCYAN}-----------------${CEND}"
echo -e "${CCYAN}[ RÉCAPITULATIF ]${CEND}"
echo -e "${CCYAN}-----------------${CEND}"

echo ""
echo -e "${CBROWN}---------------------------------------------------------------------------${CEND}"
echo -e "${CBROWN}Votre serveur mail est à présent opérationnel, félicitation ! =D${CEND}"
echo ""
echo -e "${CBROWN}Ajoutez la ligne ci-dessous dans le fichier Hosts de votre pc"
echo -e "${CBROWN}si votre nom de domaine n'est pas encore configuré pour"
echo -e "${CBROWN}le sous-domaine${CEND} ${CYELLOW}${RAINLOOPDOMAIN}.${DOMAIN}${CEND}"
echo ""
echo -e "${CYELLOW}  ${WANIP}     ${RAINLOOPDOMAIN}.${DOMAIN}${CEND}"
echo ""
echo -e "${CBROWN}Il ne vous reste plus qu'à configurer Rainloop en ajoutant votre domaine.${CEND}"
echo -e "${CBROWN}Vous pouvez accéder à l'interface d'administration via cette URL :${CEND}"
echo ""
if [[ "$PORT" = "80" ]]; then
	echo -e "${CYELLOW}> http://${RAINLOOPDOMAIN}.${DOMAIN}/?admin${CEND}"
else
	echo -e "${CYELLOW}> http://${RAINLOOPDOMAIN}.${DOMAIN}:${PORT}/?admin${CEND}"
fi
echo ""
echo -e "${CBROWN}Par défaut les identifiants sont :${CEND} ${CGREEN}admin${CEND} ${CBROWN}et${CEND} ${CGREEN}12345${CEND}"
echo -e "${CBROWN}Allez voir le tutoriel pour savoir comment rajouter un domaine à Rainloop :${CEND}"
echo ""
echo -e "${CYELLOW}> http://mondedie.fr/viewtopic.php?id=5750${CEND}"
echo ""
echo -e "${CBROWN}Une fois que Rainloop sera correctement configuré, vous pourrez accéder${CEND}"
echo -e "${CBROWN}à votre boîte mail via cette URL :${CEND}"
echo ""
if [[ "$PORT" = "80" ]]; then
	echo -e "${CYELLOW}> http://${RAINLOOPDOMAIN}.${DOMAIN}/${CEND}"
else
	echo -e "${CYELLOW}> http://${RAINLOOPDOMAIN}.${DOMAIN}:${PORT}/${CEND}"
fi
echo -e "${CBROWN}---------------------------------------------------------------------------${CEND}"
echo ""

smallLoader
clear

echo -e "${CCYAN}-------------------------------------${CEND}"
echo -e "${CCYAN}[ PARAMÈTRES DE CONNEXION IMAP/SMTP ]${CEND}"
echo -e "${CCYAN}-------------------------------------${CEND}"
echo ""

echo -e "${CGREEN}-> Utilisez les paramètres suivants pour configurer le client mail de votre choix.${CEND}"
echo -e "${CGREEN}-> Le tutoriel indiqué ci-dessous explique comment configurer Outlook, MailBird et eM Client.${CEND}"
echo ""

echo -e "${CYELLOW}> http://mondedie.fr/viewtopic.php?pid=11727#p11727${CEND}"

echo ""
echo -e "${CBROWN}---------------------------------------------------------------------------${CEND}"
echo -e "${CBROWN} - Adresse email :${CEND} ${CGREEN}admin@${DOMAIN}${CEND}"
echo -e "${CBROWN} - Nom d'utilisateur IMAP/SMTP :${CEND} ${CGREEN}admin@${DOMAIN}${CEND}"
echo -e "${CBROWN} - Mot de passe IMAP/SMTP :${CEND} ${CGREEN}Celui que vous avez mis dans PostfixAdmin${CEND}"
echo -e "${CBROWN} - Serveur entrant IMAP :${CEND} ${CGREEN}${FQDN}${CEND}"
echo -e "${CBROWN} - Serveur sortant SMTP :${CEND} ${CGREEN}${FQDN}${CEND}"
echo -e "${CBROWN} - Port IMAP :${CEND} ${CGREEN}993${CEND}"
echo -e "${CBROWN} - Port SMTP :${CEND} ${CGREEN}587${CEND}"
echo -e "${CBROWN} - Protocole de chiffrement IMAP :${CEND} ${CGREEN}TLS${CEND}"
echo -e "${CBROWN} - Protocole de chiffrement SMTP :${CEND} ${CGREEN}STARTTLS${CEND}"
echo -e "${CBROWN}---------------------------------------------------------------------------${CEND}"
echo ""

smallLoader
clear

echo -e "${CCYAN}----------------------------${CEND}"
echo -e "${CCYAN}[ CONFIGURATION DE VOS DNS ]${CEND}"
echo -e "${CCYAN}----------------------------${CEND}"

echo ""
echo -e "${CBROWN}Maintenant ajoutez votre nom d'hôte et vos deux sous-domaines :${CEND}"
echo ""
echo -e "${CCYAN}----------------------------------------------------------${CEND}"
echo -e "${CYELLOW}@                      IN      A         ${WANIP}${CEND}"
echo -e "${CYELLOW}${HOSTNAME}            IN      A         ${WANIP}${CEND}"
echo -e "${CYELLOW}${PFADOMAIN}           IN      CNAME     ${FQDN}.${CEND}"
echo -e "${CYELLOW}${RAINLOOPDOMAIN}      IN      CNAME     ${FQDN}.${CEND}"
echo -e "${CCYAN}----------------------------------------------------------${CEND}"

echo ""
echo -e "${CRED}Vous devez impérativement ajouter un enregistrement de type MX à votre nom de domaine !${CEND}"
echo -e "${CRED}Si cet enregistrement est pas ou mal défini, vous ne reçevrez JAMAIS d'emails.${CEND}"
echo -e "${CRED}Exemple (le point à la fin est IMPORTANT !!) :${CEND}"
echo ""
echo -e "${CCYAN}----------------------------------------------------------${CEND}"
echo -e "${CYELLOW}@    IN    MX    10    ${FQDN}.   ${CEND}"
echo -e "${CCYAN}----------------------------------------------------------${CEND}"

echo ""
echo -e "${CBROWN}Ensuite ajoutez votre enregistrement DKIM :${CEND}"
echo ""
echo -e "${CCYAN}----------------------------------------------------------${CEND}"
cat /etc/opendkim/keys/"$DOMAIN"/mail.txt
echo -e "${CCYAN}----------------------------------------------------------${CEND}"
echo ""
echo -e "${CRED}Pour des raisons de compatibilité avec certains registrars, la taille${CEND}"
echo -e "${CRED}de la clé DKIM est de 1024 bits, vous pouvez générer une nouvelle clé${CEND}"
echo -e "${CRED}si besoin avec la commande suivante :${CEND}"
echo ""
echo -e "${CYELLOW}opendkim-genkey -s mail -d ${DOMAIN} -b 2048${CEND}"
echo ""

echo -e "${CBROWN}Enregistrements SPF :${CEND}"
echo ""
echo -e "${CCYAN}----------------------------------------------------------${CEND}"
echo -e "${CYELLOW}@    IN    TXT    \"v=spf1 a mx ip4:${WANIP} ~all\"     ${CEND}"
echo -e "${CYELLOW}@    IN    SPF    \"v=spf1 a mx ip4:${WANIP} ~all\"     ${CEND}"
echo -e "${CCYAN}----------------------------------------------------------${CEND}"
echo ""

echo -e "${CBROWN}Et pour finir vos enregistrements DMARC :${CEND}"
echo ""
echo -e "${CCYAN}----------------------------------------------------------${CEND}"
echo -e "${CYELLOW}_dmarc    IN    TXT    \"v=DMARC1; p=reject; rua=mailto:postmaster@${DOMAIN}; ruf=mailto:admin@${DOMAIN}; fo=0; adkim=s; aspf=s; pct=100; rf=afrf; sp=reject\"${CEND}"
echo -e "${CCYAN}----------------------------------------------------------${CEND}"
echo ""
echo -e "${CRED}Il faut mettre cet enregistrement uniquement si vous êtes sûr${CEND}"
echo -e "${CRED}du fonctionnement des enregistrements DKIM/SPF (voir plus haut).${CEND}"
echo ""

echo -e "${CCYAN}-----------------${CEND}"
echo -e "${CCYAN}[ FIN DU SCRIPT ]${CEND}"
echo -e "${CCYAN}-----------------${CEND}"

exit 0
