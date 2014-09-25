Another Backup Tool
===================

Avec Another Backup Tool, vous avez un outil simple, rapide a déployer, qui vous permet de tout (ou presque) sauvegarder. Une nombre important de modules sont fournit de base pour de la sauvegarde de configuration ainsi que des logs.

L'outil fournit un rapport par email pour suivre le resultat de vos sauvegardes.

1) Installation
----------------------------------

L'installation est décrite pour la distribution Debian. Cependant, en ajustant les commandes à votre distribution, cela ne devrait pas poser de problème.

### Debian (*recommended*)

Installez les pré-requis :

    aptitude install cpanminus git unzip makepatch
    aptitude install liblog-log4perl-perl libxml-simple-perl libdir-purge-perl libfile-find-rule-perl libmime-lite-perl libconfig-inifiles-perl libparallel-forkmanager-perl libdata-validate-ip-perl libnet-sftp-foreign-perl libnet-openssh-perl libwww-mechanize-perl libnet-appliance-session-perl libnet-scp-expect-perl
    cpanm File::DirList

***Configurez CPAN

    root@server-abt# perl -MCPAN -e shell
    cpan> o conf prerequisites_policy follow
    cpan> o conf commit



Télécharger les sources :

    git clone --progress https://github.com/mguyard/another-backup-tool.git /opt/another-backup-tool

Créez l'utilisateur de service ABT

    useradd -M -d /opt/another-backup-tool -c "Another Backup Tool User" -s /bin/bash abt

Modifiez les autorisations user/group sur le répertoire ABT

    chown -R abt:abt /opt/another-backup-tool

