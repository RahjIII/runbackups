#!/usr/bin/tclsh

# runbackups.tcl
# Copyright © 2014-2026 Jeff Jahr, Jeffrika Heavy Industries

# This script uses ssh rsync to copy remote filesystems into a local backup
# partition.  Rsync generally only copies files when they have changed, so the
# network load is kept at a minimum.  Revisions inside the local backup
# partition are built using hard link copies, which effectively de-dups files
# that are unchanged between revisions.

# To enable backups at 3am, call this script from root's contab on the backup
# system by running `crontab -e` as root:
#  MAILTO=admin@example.com
#  0 3 * * * /srv/backups/runbackups.tcl
#
# You need to set up passwordless auth on the targets being backed up, or you
# get prompted for the root password.
#
# On the server runing this script:
# As root on the server system running this script and doing the backups:
#  `ssh-keygen -f /root/.ssh/id_rsa`
# Hit return when prompted for a password.  If prompted to overwrite, DONT.  It
# means you've already done this step, and you don't want to do it twice.
#
# For each target system being backed up:
# Append the contents of /root/.ssh/id_rsa.pub from the server to the file
# named /root/.ssh/authorized_keys on the target client system that is being
# backed up. This also applies to the server.   Use vi, cut and paste, append,
# `ssh-copy-id -i /root/.ssh/id_rsa.pub root@target`, or whatever.

# This is the mount point for the local backup storage partition.  It will be
# remounted read-write for the backup, then back to read-only after.  This is
# to lower the odds that someone or something will inadvertantly modify the
# online backup set outside of the backup window.  
set bkpdir /srv/backups

# Add the list of target locations here.  Each target is a hostname for rsync
# followed by a directory to recursively back up.

# I like to use the unqualified hostname for the localhost backup, instead of,
# say, "localhost".
lappend targets { moirai /home }
lappend targets { moirai /root }
lappend targets { moirai /etc }

# I like to use the fqdn for the network hosts being backed up, but an
# unqualified hostname works fine too.
lappend targets { clothos.subdomain.example.com /var/www }
lappend targets { clothos.subdomain.example.com /home }
lappend targets { clothos.subdomain.example.com /var/lib/mysql }
lappend targets { clothos.subdomain.example.com /var/lib/weewx }
lappend targets { clothos.subdomain.example.com /usr/share/weewx }
lappend targets { clothos.subdomain.example.com /usr/local }
lappend targets { clothos.subdomain.example.com /etc }
lappend targets { clothos.subdomain.example.com /root }
lappend targets { clothos.subdomain.example.com /srv/mp3 }
lappend targets { clothos.subdomain.example.com /srv/nextcloud }

lappend targets { lachesis.example.com /home }
lappend targets { lachesis.example.com /root }
lappend targets { lachesis.example.com /etc }
lappend targets { lachesis.example.com /srv/mudserver }

lappend targets { atropos.subdomain.example.com /home }
lappend targets { atropos.subdomain.example.com /root }
lappend targets { atropos.subdomain.example.com /etc }

# How many link-copy revisions should be kept?  If run daily, 7 implies a
# week's worth.  The link copy revisions will be kept under a numbered dot
# directory, with 0 being the most recent version.  For example, if the backup
# for target { moirai /home } is "/srv/backups/moirai/home", then the first
# link copy will be "/srv/backups/moirai/.home.0".
set maxbackups 7

# Set this to 1 on the very first run to keep from making the backup directory
# paths by hand.  Can be safely set to 0 afterwards as another safety check, or
# just left at 1.
set automakedir 1

# -------- No parameters below this line. ------------

cd $bkpdir

proc bkpname { dir number } {
	set name [file dirname $dir]
	append name "/."
	append name [file tail $dir]
	append name "."
	append name $number
	return $name
}
	

set iam [lindex [exec id] 0]
if { [lsearch $iam "uid=0(root)"] == -1 } {
	puts "Yer gonna need to be root instead of $iam."
	puts "Run me with sudo."
	exit 0
}


puts "Backup process begins [clock format [clock seconds]]"
puts ""


# remount bkpdir rw.
if { [catch { exec mount -o remount,rw $bkpdir } err] } {
	puts "Oops!"
	puts [string repeat "*" 70]
	puts "HEY.. tried to remount $bkpdir as read-write, but it failed."
	puts "Problem was: $err"
	puts [string repeat "*" 70]
}
	

set donetargets ""
foreach target $targets {
	set host [lindex $target 0]
	set dir [lindex $target 1]

	set local "${host}${dir}"
	set remote "root@${host}:${dir}"

	puts -nonewline "Backing up ${remote}... "
	flush stdout
	set starttime [clock seconds]

	if { ![file exists $local] } {
		if { $automakedir == 1 } {
			puts "Creating directory $local which did not exist."
			file mkdir $local
		} else {
			puts "Oops!"
			puts [string repeat "*" 70]
			puts "HEY.. $local doesn't exist in [pwd] and that seems wierd."
			puts "You'll need to create it with `mkdir -p [file join [pwd] $local]` first."
			puts "Until then, I'm gonna skip backing that one up."
			puts [string repeat "*" 70]
			continue
		}
	}

	set bkp [bkpname $local $maxbackups]
	if { [file exists $bkp ] } {
		# puts "Removing $bkp"
		file delete -force $bkp
	}

	for { set no $maxbackups } { $no > 0 } { incr no -1 } {
		set from [bkpname $local [expr $no - 1]]
		set to [bkpname $local $no]
		if { [file exists $from] } {
			# puts "Renaming $from to $to"
			file rename $from $to
		}
	}

	set to [bkpname $local 0]
	if { [catch { exec cp -al $local $to } err] } {
		puts "Oops!"
		puts [string repeat "*" 70]
		puts "There was a problem While doing a link copy of $local to $to"
		puts "Problem was: $err"
		puts "The rsync is being SKIPPED, this backup is NOT DONE."
		puts [string repeat "*" 70]
		continue
	}

	if { [ catch { exec rsync -a --exclude-from=excludelist --delete "${remote}/" "${local}/" 2>@1 } err ] } {
		puts "Oops!"
		puts [string repeat "*" 70]
		puts "While running the rsync from $remote"
		puts "Problem was: $err"
		puts "This backup is NOT DONE."
		puts [string repeat "*" 70]
		continue
	} 

	lappend donetargets $local	
	puts "took [expr [clock seconds] - $starttime] seconds."
}

catch { exec sync }

# remount bkpdir ro.
if { [catch { exec mount -o remount,ro $bkpdir } err] } {
	puts "Oops!"
	puts [string repeat "*" 70]
	puts "HEY.. tried to remount $bkpdir as read-only, but it failed."
	puts "Problem was: $err"
	puts [string repeat "*" 70]
}

puts ""
puts "[exec df -h $bkpdir]"
puts ""
foreach location $donetargets {
	puts "[exec du -h -s $location]"
}

puts ""
puts "Backup process complete [clock format [clock seconds]]"
