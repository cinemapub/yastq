#!/bin/bash

# Include config file
if [ -r "$HOME/.yastq.conf" ]
then 
	source "$HOME/.yastq.conf"
elif [ -r "/etc/yastq.conf" ]
then 
	source "/etc/yastq.conf"
else 
	echo "Config file not found"
	exit 1
fi

# Include common code
if ! source "$COMMON_SCRIPT_FILE"
then 
	echo "Error including common file"
	exit 1
fi

#
if ! source "$SOURCE_DIR/tasksqueue.sh"
then
	
fi

##
## Sends message to log
##
tasksqueue_log() 
{
	echo "$($DATE +'%F %T') (tasksqueue $$) $1" >> "$TASKSQUEUE_LOG_FILE"
}

##
## Gracefully stops the tasks queue
##
tasksqueue_graceful_stop()
{
	GRACEFUL_STOP=1
	return 0
}

# Handle TERM signal to permit next iteration
trap 'tasksqueue_graceful_stop && tasksqueue_log "Stopping gracefully" || tasksqueue_log "Stopping gracefully failed"' SIGTERM

# Log about starting
tasksqueue_log "Starting"

# Tasks loop
while [ -z "$GRACEFUL_STOP" ]
do
	# Obtain exclusive lock
	{
		"$FLOCK" -x 200
		read -r TASK < "$TASKSQUEUE_TASKS_FILE"
	} 200<"$TASKSQUEUE_TASKS_FILE_LOCK"

	# If read was not success
	if ! [ $? ]
	then
		continue
	fi

	# If read was empty
	if ! [ -n "$TASK" ]
	then
		"$SLEEP" 0.1s
		continue
	fi

	# Send new task to workers over pipe
	if echo "$TASK" > "$TASKSQUEUE_TASKS_PIPE"
	then
		tasksqueue_log "Sending base64 task '$TASK' to pipe ok"
	
		# Obtain exclusive lock
		{
			"$FLOCK" -x 200
			"$SED" -i 1d "$TASKSQUEUE_TASKS_FILE"
		} 200<"$TASKSQUEUE_TASKS_FILE_LOCK"

		# If row was removed
		if [ $? ]
		then
			tasksqueue_log "Removing base64 task '$TASK' from tasks database ok"
		else
			tasksqueue_log "Removing base64 task '$TASK' from tasks database failed" 
		fi
	else
		tasksqueue_log "Sending base64 task '$TASK' to pipe failed"
	fi
done

# Log about exiting
tasksqueue_log "Exiting"
