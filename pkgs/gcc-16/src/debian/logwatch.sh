#! /bin/bash

# script to trick the build daemons and output something, if there is
# still test/build activity

# $1: primary file to watch. if there is activity on this file, we do nothing
# $2: build dir to search for dejagnu log files
#      if the files are modified or are newly created, then the message
#      is printed on stdout.
#      if nothing is modified, don't output anything (so the buildd timeout
#      hits).

pidfile=logwatch.pid
timeout=1800
message='logwatch still running'

usage()
{
    echo >&2 "usage: `basename $0` [-p <pidfile>] [-t <timeout>] [-m <message>]"
    echo >&2 "           <primary logfile> <build dir>"
    exit 1
}

while [ $# -gt 0 ]; do
    case $1 in
    -p)
	pidfile=$2
	shift
	shift
	;;
    -t)
	timeout=$2
	shift
	shift
	;;
    -m)
	message="$2"
	shift
	shift
	;;
    -*)
	usage
	;;
    *)
	break
    esac
done

[ $# -gt 0 ] || usage

logfile="$1"
shift
builddir="$1"
shift
[ $# -eq 0 ] || usage

cleanup()
{
    rm -f $pidfile
    exit 0
}

#trap cleanup 0 1 3 15

echo $$ > $pidfile

declare -A stamps

find_logs()
{
    for f in $(find $builddir -name '*.log' \
			       ! -name config.log \
			       ! -path '*/ada/acats?/tests/*.log' \
			       ! -path '*/libbacktrace/*.log')
    do
	if [ ! -v stamps[$f] ]; then
	    stamps[$f]=$(date -u -r $f '+%s')
	fi
    done
}

# wait for test startups
sleep 30
find_logs

# activity in the main log file
sleep 10
st_logfile=$(date -u -r $logfile '+%s')

sleep 10

while true; do
    find_logs
    sleep 10
    stamp=$(date -u -r $logfile '+%s')
    if [ $stamp -gt $st_logfile ]; then
	# there is still action in the primary logfile. do nothing.
	st_logfile=$stamp
    else
	activity=0
	for log in "${!stamps[@]}"; do
	    [ -f $log ] || continue
	    stamp=$(date -u -r $log '+%s')
	    if [ $stamp -gt ${stamps[$log]} ]; then
		if [ $activity -eq 0 ]; then
		    echo
		fi
		echo "[$(date -u -r $log '+%T')] $log: $message"
		tail -3 $log
		activity=$(expr $activity + 1)
		stamps[$log]=$stamp
	    fi
	done
	if [ $activity -gt 0 ]; then
	    # already emitted messages above
	    echo
	else
	    # nothing changed in the other log files. maybe a timeout ...
	    :
	fi
    fi
    sleep $timeout
done

exit 0
