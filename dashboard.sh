#!/bin/bash

# Include config file
[ -r "$HOME/.yastq.conf" ] && source "$HOME/.yastq.conf" || { 
       [ -r "/etc/yastq.conf" ] && source "/etc/yastq.conf" || { echo "Error: loading config file failed" 1>&2; exit 1; }
}

# Include common file
[ -r "$COMMON_SCRIPT_FILE" ] && source "$COMMON_SCRIPT_FILE" || { echo "Error: loading common file failed" 1>&2; exit 1; }

##
## Returns error code 0 and sets RESULT or returns error code
##
## Returns:
##  0 - on getting pid success
##  1 - on getting pid failure
## 
## Exports:
##	RESULT - Tasksqueue pid
##
progress()
{
	local LOG_SOURCE=$1
	local LOG_STATUS=$2
	local LOG_MESSAGE=$3
	if [ $LOG_STATUS -eq 0 ] ; then
		## pure info: neutral or execution imminent (...)
		log_info "$LOG_SOURCE" "$LOG_MESSAGE"
		echo "   $LOG_MESSAGE"
	elif [ $LOG_STATUS -gt 0 ] ; then
		## something worked!
		log_info "$LOG_SOURCE" "$LOG_MESSAGE"
		echo "* $LOG_MESSAGE"
	else
		## something failed!
		log_info "$LOG_SOURCE" "$LOG_MESSAGE"
		echo "! $LOG_MESSAGE"
	fi
}


workers_pids() 
{
	unset -v RESULT

	#log_debug "dashboard" "Getting workers pids ..."
	if ! [ -e "$WORKERS_PID_FILE" ]
	then 
		log_debug "dashboard" "Getting workers pids failed (NO PID FILE)"
		return 1
	fi

	local WORKERS_PIDS
	read -r WORKERS_PIDS 0<"$WORKERS_PID_FILE"
	if ps -p $WORKERS_PIDS 2>/dev/null 1>/dev/null
	then
		RESULT=$WORKERS_PIDS
		log_debug "dashboard" "Getting workers pids ok [$WORKERS_PIDS]"
		return 0
	else
		log_debug "dashboard" "Getting workers pids failed (STALE PROCESSES)"
		return 1
	fi	
}

##
## Starts workers
##
## Returns:
##  0 - on start success
##  1 - on tasksqueue is running
##
workers_start() 
{
	local WORKERS_COUNT=$1

	if ! workers_pids
	then
		local WORKERS_PIDS
		for ((i=1; i<=$WORKERS_COUNT; i++))
		do
			nohup "$WORKER_SCRIPT_FILE" 2>/dev/null 1>/dev/null &
			WORKERS_PIDS="$WORKERS_PIDS $!"
		done

		# Store workers pids into pidfile
		echo $WORKERS_PIDS 1>"$WORKERS_PID_FILE"
		progress "dashboard" +1 "WORKER(S) started OK [$WORKERS_COUNT:$WORKERS_PIDS]"
		return 0
	else
		progress "dashboard" -1 "WORKER NOT started (ALREADY RUNNING)"
		return 1
	fi
}

##
## Stops workers
##
## Returns:
##  0 - on stop success
##  1 - on getting pid failure
##
workers_stop() 
{
	if workers_pids
	then
		local WORKERS_PIDS=$RESULT
		kill -9 $WORKERS_PIDS 1>/dev/null
		while ps -p $WORKERS_PIDS 1>/dev/null
		do
		    sleep .5
		done
		rm -f "$WORKERS_PID_FILE"
		progress "dashboard" 1 "WORKER stopped OK [$WORKERS_PIDS]"
		return 0
	else
		progress "dashboard" -1 "WORKER NOT stopped (NOT RUNNING)"
		return 1
	fi
}

##
## Returns error code 0 and sets RESULT or returns error code
##
## Returns:
##  0 - on getting pid success
##  1 - on getting pid failure
## 
## Exports:
##	RESULT - Tasksqueue pid
##
tasksqueue_pid()
{
	unset -v RESULT

	#log_debug "dashboard" "Getting tasksqueue pids ..."
	if ! [ -e "$TASKSQUEUE_PID_FILE" ]
	then 
		log_debug "dashboard" "Getting tasksqueue pids failed (NO PID FILE)"
		return 1
	fi

	local TASKSQUEUE_PID
	read -r TASKSQUEUE_PID 0<"$TASKSQUEUE_PID_FILE"
	if ps -p $TASKSQUEUE_PID 2>/dev/null 1>/dev/null
	then
		RESULT=$TASKSQUEUE_PID
		log_debug "dashboard" "Getting tasksqueue pids ok [$TASKSQUEUE_PID]"
		return 0
	else
		log_debug "dashboard" "Getting tasksqueue pids failed (NO PROCESSES)"
		return 1
	fi
}

##
## Starts tasks queue
##
## Returns:
##  0 - on start success
##  1 - on tasksqueue is running
##
tasksqueue_start()
{
	#log_debug "dashboard" "Starting tasksqueue  ..."
	if ! tasksqueue_pid
	then
		nohup "$TASKSQUEUE_SCRIPT_FILE" 2>/dev/null 1>/dev/null &
		local TASKSQUEUE_PID=$!
		echo $TASKSQUEUE_PID 1>"$TASKSQUEUE_PID_FILE"
		progress "dashboard" 1 "QUEUE started OK [$TASKSQUEUE_PID]"
		return 0
	else
		progress "dashboard" -1 "QUEUE NOT started (ALREADY RUNNING)"
		return 1
	fi
}

##
## Stops tasks queue
##
## Returns:
##  0 - on stop success
##  1 - on getting pid failure
##
tasksqueue_stop()
{
	#log_debug "dashboard" "Stopping tasksqueue  ..."
	if tasksqueue_pid
	then
		local TASKSQUEUE_PID=$RESULT
		kill -s SIGTERM $TASKSQUEUE_PID 1>/dev/null
		while ps -p $TASKSQUEUE_PID 1>/dev/null
		do 
			sleep .5s; 
		done
		rm -f "$TASKSQUEUE_PID_FILE"
		progress "dashboard" 1 "QUEUE stopped OK [$TASKSQUEUE_PID]"
		return 0
	else
		progress "dashboard" -1 "QUEUE NOT stopped (NOT RUNNING)"
		return 1
	fi
}



##
## Prints scripts usage to stdout
##
dashboard_print_usage()
{
	bname=$(basename $0)
	echo "Usage: $bname start|stop|status"
	echo "       $bname add-task task TASK [success SUCCESS] [fail FAIL] [--append-id-task] [--append-id-success] [--append-id-fail]"
	echo "       $bname show-task TASK_ID"
	echo "       $bname remove-task TASK_ID"
}

# Currect action
ACTION=$1
shift

case $ACTION in 
	"start")
		if workers_pids 
		then 
			progress "dashboard" -1 "Workers are already running"
		else
			if tasksqueue_start 
			then
				#progress "dashboard" +1 "Starting tasks queue ok"
				sleep .5
			else 
				progress "dashboard" -1 "Starting tasks queue failed" 
			fi

			if workers_start "$PARALLEL_TASKS"
			then
				#progress "dashboard" +1 "Starting [$PARALLEL_TASKS] workers ok" 
				sleep .5	
			else 
				progress "dashboard" -1 "Starting [$PARALLEL_TASKS] workers failed" 
			fi	
		fi
		
		;;
	"stop")
		if workers_pids 
		then 
			if tasksqueue_stop 
			then 
				#progress "dashboard" +1 "Stopping tasks queue ok" 
				sleep .5
			else
				progress "dashboard" -1 "Stopping tasks queue failed" 
			fi
		
			if workers_stop 
			then
				#progress "dashboard" +1 "Stopping workers ok" 
				sleep .5
			else
				progress "dashboard" -1 "Stopping workers failed" 
			fi
		else
			progress "dashboard" -1 "No workers running" 
		fi
		;;
	"status")
		status_ok=1
		if workers_pids 
		then 
			progress "dashboard" 1 "WORKER(S): running" 
		else 
			progress "dashboard" -1 "WORKER(S): stopped" 
			status_ok=0
		fi

		if tasksqueue_pid
		then 
			progress "dashboard" 1 "QUEUE: running" 
		else
			progress "dashboard" -1 "QUEUE: stopped" 
			status_ok=0
		fi
		if [ $status_ok == 1 ] ; then
			progress "dashboard" 1  "STATUS: ALL_RUNNING"
			exit 0
		else
			progress "dashboard" -1 "STATUS: NOT_RUNNING"
			exit 2
		fi
		;;
	"add-task")
		TASK_SUCC=false
		TASK_FAIL=false
		unset -v TASK_OPTIONS

		while [ -n "$1" ]
		do
			case $1 in 
				"task")
					TASK_GOAL=$2; shift; shift
					;;
				"success")
					TASK_SUCC=$2; shift; shift
					;;
				"fail")
					TASK_FAIL=$2; shift; shift
					;;
				"--append-id-task")
					TASK_OPTIONS=( "${TASK_OPTIONS[@]}" "APPEND_ID_TASK" ); shift
					;;
				"--append-id-success")
					TASK_OPTIONS=( "${TASK_OPTIONS[@]}" "APPEND_ID_SUCC" ); shift
					;;
				"--append-id-fail")
					TASK_OPTIONS=( "${TASK_OPTIONS[@]}" "APPEND_ID_FAIL" ); shift
					;;
				*)		
					dashboard_print_usage
					exit 1
					;;
			esac
		done

		TASK_OPTIONS=$(IFS=:; echo "${TASK_OPTIONS[*]}")

		if ! [ -n "$TASK_GOAL" -a -n "$TASK_SUCC" -a -n "$TASK_FAIL" ]
		then
			dashboard_print_usage
			exit 1
		fi
		
		#log_info "dashboard" "Adding task [$TASK_GOAL][$TASK_SUCC][$TASK_FAIL] with options [$TASK_OPTIONS] ..." 
		if queuedb_push "$TASK_GOAL" "$TASK_SUCC" "$TASK_FAIL" "$TASK_OPTIONS"
		then
			TASK_ID=$RESULT
			progress "dashboard"  1 "Adding task [$TASK_GOAL][$TASK_SUCC][$TASK_FAIL] with options [$TASK_OPTIONS] ok (Task added with id [$TASK_ID])"
			exit 0
		else
			progress "dashboard" -1 "Adding task [$TASK_GOAL][$TASK_SUCC][$TASK_FAIL] with options [$TASK_OPTIONS] failed (Push failed with code [$?])"
			exit 2
		fi
		;;
	"remove-task")
		TASK_ID=$1
		if ! [ -n "$TASK_ID" ]
		then
			dashboard_print_usage
			exit 1
		fi

		log_info "dashboard" "Removing task [$TASK_ID] ..."
		if queuedb_remove "$TASK_ID"
		then
			log_info "dashboard" "Removing task [$TASK_ID] ok" 
			echo "Removing task [$TASK_ID] ok" 
			exit 0
		else
			log_info "dashboard" "Removing task [$TASK_ID] failed (Remove failed with code [$?])" 
			echo "Removing task [$TASK_ID] failed (Remove failed with code [$?])"
			exit 2
		fi
		;;
	"show-task")
		TASK_ID=$1
		if ! [ -n "$TASK_ID" ]
		then
			dashboard_print_usage
			exit 1
		fi

		log_info "dashboard" "Showing task [$TASK_ID] ..."
		if queuedb_find "$TASK_ID"
		then
			log_info "dashboard" "Showing task [$TASK_ID] ok" 
			echo "Task '$TASK_ID': [${RESULT[1]}] success [${RESULT[2]}] fail [${RESULT[3]}]"
			exit 0
		else
			log_info "dashboard" "Showing task [$TASK_ID] failed (Find failed with code [$?])"
			echo "Task '$TASK_ID': Not found"
			exit 1
		fi
		;;
	"list-tasks")

		if queuedb_list
		then
			log_info "dashboard" "Showing task [$TASK_ID] ok" 
			echo $RESULT
			exit 0
		else
			log_info "dashboard" "Showing task [$TASK_ID] failed (Find failed with code [$?])"
			echo "No tasks found"
			exit 1
		fi
		;;
	*)
		dashboard_print_usage
		;;
esac
