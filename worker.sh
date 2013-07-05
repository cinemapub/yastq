#!/bin/bash

# Include common code
source `dirname $0`/common.sh

# Handle TERM signal for permit next iteration
trap 'CONTINUE=0' 15

log_worker "$$ Worker starting"

# Continue next task after
CONTINUE=1;

# Tasks loop
while [[ $CONTINUE -eq 1 ]]
do
	# Read next task
	TASK=$($CAT $TASKS_QUEUE_PIPE 2>/dev/null)

	if [[ -n "$TASK" ]]; then
		# Log task start
		log_worker "$$ Running task $TASK"

		# Run task
		eval "$TASK &"; wait; 
		CODE=$?
		
		if [[ $CODE -eq 0 ]]; then
			# Put it into completes file
			echo "$TASK" | $TS >> $QUEUE_COMPLETE_FILE
		else 
			# Put it into errors file
			echo "$TASK" | $TS >> $QUEUE_FAILED_FILE
		fi

		# Log task end
		log_worker "$$ Running task finished with code $CODE"
	else
		# Task is empty. Sleep
		sleep 1
	fi
done

log_worker "$$ Worker exiting"
