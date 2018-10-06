** Backed up from [@hardware](https://github.com/hardware) in the hopes of maintaining it.

**Ce script n'est plus maintenu, merci d'utiliser à la place [mon image docker](https://github.com/hardware/mailserver). Je considère cette méthode beaucoup plus fiable et rapide à mettre en place. Je continuerai d'apporter des mises à jour de sécurité si besoin mais le script décrit ici n'évoluera plus. Merci de votre compréhension.**

Serveur de mail - Installation automatique
==========================================

Ce script permet d'installer de manière automatique un serveur mail complet avec Postfix, Dovecot et Rainloop.
Topic associé : http://mondedie.fr/viewtopic.php?pid=11746

### Pré-requis :

- ``Debian 7 “wheezy” ou Debian 8 “jessie”``
- ``Nginx``
- ``PHP``
- ``MySQL``
- ``OpenSSL``

### Installation

```bash
apt-get update && apt-get dist-upgrade
apt-get install git-core
```

```bash
cd /tmp
git clone https://github.com/hardware/mailserver-autoinstall.git
cd mailserver-autoinstall
chmod +x install.sh && ./install.sh
```

### Désinstallation

Le script de désinstallation permet de supprimer absolument **TOUT** ce qu'à fait le script d'installation. Si vous avez une erreur pendant la configuration du serveur de mail, vous pouvez répartir à zéro avec ce script :

```bash
chmod +x uninstall.sh && ./uninstall.sh
```

Ce script est tiré du tutoriel "Installation sécurisée d'un serveur de mail avec Postfix, Dovecot et Rainloop" : http://mondedie.fr/viewtopic.php?id=5750

Inspiré du script d'installation de rutorrent de ``Ex_Rat`` : https://bitbucket.org/exrat/install-rutorrent

### Support

Si vous avez une question, une remarque ou une suggestion, n'hésitez pas à poster un commentaire sur ce topic : http://mondedie.fr/viewtopic.php?id=5794

### License
MIT. Voir le fichier ``LICENCE`` pour plus de détails
