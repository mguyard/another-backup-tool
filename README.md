Another Backup Tool
===================

Avec Another Backup Tool, vous avez un outil simple, rapide a d�ployer, qui vous permet de tout (ou presque) sauvegarder.
Un nombre important de modules sont fournit de base pour sauvegarder des configurations ou des logs.

L'outil fournit un rapport par email pour suivre le resultat de vos sauvegardes.

1) Installation
----------------------------------

L'installation est d�crite pour la distribution Debian. Cependant, en ajustant les commandes � votre distribution, cela ne devrait pas poser de probl�me.
Toutes les commandes pr�c�d�s d'un **#** sont � �x�cuter en **root** alors que les commandes pr�c�d�s d'un **$** sont � �x�cuter en **abt**

### Debian (*recommended*)

Installez les pr�-requis :

    # aptitude install cpanminus git unzip makepatch
    # aptitude install liblog-log4perl-perl libxml-simple-perl libdir-purge-perl libfile-find-rule-perl libmime-lite-perl libconfig-inifiles-perl libparallel-forkmanager-perl libdata-validate-ip-perl libnet-sftp-foreign-perl libnet-openssh-perl libwww-mechanize-perl libnet-appliance-session-perl libnet-scp-expect-perl
    # cpanm File::DirList

T�l�charger les sources :

    # git clone --progress https://github.com/mguyard/another-backup-tool.git /opt/another-backup-tool

Cr�ez l'utilisateur de service ABT

    # useradd -M -d /opt/another-backup-tool -c "Another Backup Tool User" -s /bin/bash abt

Modifiez les autorisations user/group sur le r�pertoire ABT

    # chown -R abt:abt /opt/another-backup-tool

Mettre en place les executions automatiques

    # cp /opt/another-backup-tool/examples/cron/ABT /etc/cron.d/

Mettre en place la configuration a partir de l'exemple fournit et adaptez le � votre besoin

    $ cp /opt/another-backup-tool/configuration.default.ini /opt/another-backup-tool/configuration.ini

2) Mise � jour
----------------------------------

Toutes les commandes pr�c�d�s d'un **#** sont � �x�cuter en **root** alors que les commandes pr�c�d�s d'un **$** sont � �x�cuter en **abt**

    $ git pull --progress