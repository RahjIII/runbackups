### runbackups.tcl
Copyright © 2014-2026 Jeff Jahr, Jeffrika Heavy Industries

This TCL script uses ssh rsync to copy remote filesystems into a local backup
partition.  Rsync generally only copies files when they have changed, so the
network load is kept at a minimum.  Revisions inside the local backup partition
are built using hard link copies, which effectively de-dups files that are
unchanged between revisions.

It is meant to be called from a crontab running on a server that hosts a backup
partition that is also exported as a read-only network filesystem, making
online backups available to network users when needed.

It can also be called manually from a removable disk to update an offline
backup.

Generally, its a good idea to keep a copy of the script with its modified
targets in the top level $bkpdir.  If your backup partition is at /srv/backups,
then save this script in /srv/backups/runbackups.tcl and run it from there.

The runbackups script depends on tcl, ssh, rsync, and mount.
