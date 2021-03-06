#!/usr/bin/env bash
set -e

if [ "$1" == 'supervisord' ]; then
	################### ################### ###################
	################### general core shared ###################
	################### ################### ###################
	APP_VOLUME=${APP_VOLUME:-/app_sync}
	HOST_VOLUME=${HOST_VOLUME:-/host_sync}
	OWNER_UID=${OWNER_UID:-0}
	GROUP_ID=${GROUP_ID:-0}

	[ ! -d $APP_VOLUME ] && mkdir -p $APP_VOLUME

	# if the user did not set anything particular to use, we use root
	# since this means, no special user has been created on the target container
	# thus it is most probably root to run the daemon and thats a good default then
	if [ -z $OWNER_UID ];then
	   OWNER_UID=0
	fi

	if [ ! -z $GROUP_ID ]; then

	   # If gid doesn't exist on the system
	   if ! cut -d: -f3 /etc/group | grep -q $GROUP_ID; then
	       echo "no group has gid $GROUP_ID"
				 groupadd -g $GROUP_ID dockersync
	   fi
	else
		GROUP_ID=0
	fi

	# if the user with the uid does not exist, create it, otherwise reuse it
	if ! cut -d: -f3 /etc/passwd | grep -q $OWNER_UID; then
		echo "no user has uid $OWNER_UID"

		# If user doesn't exist on the system
		useradd -u $OWNER_UID -g $GROUP_ID dockersync -m
	else
		if [ $OWNER_UID == 0 ]; then
			# in case it is root, we need a special treatment
			echo "user with uid $OWNER_UID already exist and its root"
		else
			# we actually rename the user to unison, since we do not care about
			# the username on the sync container, it will be matched to whatever the target container uses for this uid
			# on the target container anyway, no matter how our user is name here
			echo "user with uid $OWNER_UID already exist"
			existing_user_with_uid=$(awk -F: "/:$OWNER_UID:/{print \$1}" /etc/passwd)
			OWNER=`getent passwd "$OWNER_UID" | cut -d: -f1`
			GROUP=`getent group "$GROUP_ID" | cut -d: -f1`
			mkdir -p /home/$OWNER
			usermod -u $OWNER_UID -g $GROUP_ID $OWNER
			usermod --home /home/$OWNER $OWNER
			chown -R $OWNER /home/$OWNER
			chgrp -R $GROUP /home/$OWNER
		 fi
	fi
	export OWNER_HOMEDIR=`getent passwd $OWNER_UID | cut -f6 -d:`
	# OWNER should actually be dockersync in all cases the user did not match a system user
	export OWNER=`getent passwd "$OWNER_UID" | cut -d: -f1`
	export GROUP=`getent group "$GROUP_ID" | cut -d: -f1`
	chown -R $OWNER $VOLUME
	chgrp -R $GROUP $VOLUME

	# see https://wiki.alpinelinux.org/wiki/Setting_the_timezone
	if [ -n ${TZ} ] && [ -f /usr/share/zoneinfo/${TZ} ]; then
		ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime
		echo ${TZ} > /etc/timezone
	fi

	# Check if a script is available in /docker-entrypoint.d and source it
	for f in /docker-entrypoint.d/*; do
		case "$f" in
			*.sh)     echo "$0: running $f"; . "$f" ;;
			*)        echo "$0: ignoring $f" ;;
		esac
	done
	################### ################### ###################
	################### / general core shared/ ################
	################### ################### ###################

	################### ################### ###################
	###################  now unison specific ###################
	################### ################### ###################
	# Increase the maximum watches for inotify for very large repositories to be watched
	# Needs the privilegied docker option
	[ ! -z $MAX_INOTIFY_WATCHES ] && echo fs.inotify.max_user_watches=$MAX_INOTIFY_WATCHES | tee -a /etc/sysctl.conf && sysctl -p || true
	################### ################### ###################
	################### /now unison specific/ ###################
	################### ################### ###################
    chown -R $OWNER_UID /unison
    chown $OWNER_UID /tmp/unison.log
fi

exec "$@"
