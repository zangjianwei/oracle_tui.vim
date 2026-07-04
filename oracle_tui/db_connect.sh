################################################################################
#                     Create a connection to the database                      #
#Author: Zang Jianwei                                                          #
################################################################################
if [ $# -ne 1 -a $# -ne 3 ];then
	echo "Usage:`basename $0` vimpid [username] [password]"
	exit 1
fi

lc_all=`locale|grep LC_all|awk -F"=" '{gsub(/"/, "", $2);print $2}'`

lc_utf_flag=`locale|grep LC_CTYPE|sed 's/"//g'|awk -F"=" '{print $2}'|awk -F. '{
		if (tolower($2) ~/utf/)
			print 1
		else
			print 0
	}'`

tui_lc_utf_flag=`echo $TUI_LC_CTYPE|awk -F. '{
		if (tolower($2) ~/utf/)
			print 1
		else
			print 0
	}'`

nls_lang_utf_flag=`echo $NLS_LANG|awk -F. '{
		if (tolower($2) ~/utf/)
			print 1
		else
			print 0
	}'`

tui_nls_lang_utf_flag=`echo $TUI_NLS_LANG|awk -F. '{
		if (tolower($2) ~/utf/)
			print 1
		else
			print 0
	}'`

if [ $nls_lang_utf_flag -eq 0 ];then
	if [ $tui_nls_lang_utf_flag -eq 0 ];then
		echo "Please set the environment variable TUI_NLS_LANG to UTF-8 encoding" 
		exit 1
	else
		export NLS_LANG="$TUI_NLS_LANG"
	fi
fi

if [ $lc_utf_flag -eq 0 ];then
	if [ $tui_lc_utf_flag -ne 1 ];then
		echo "Please set the environment variable TUI_LC_CTYPE to UTF-8 encoding" 
		exit 1
	else
		if [ "$lc_all" != "" ];then
			export LC_ALL="$TUI_LC_CTYPE"
		else
			export LC_CTYPE="$TUI_LC_CTYPE"
		fi
	fi
fi

vimpid=$1
if [ $# -eq 3 ];then
	dbuser=$2
	dbpass=$3
fi

pipe_in=~/.dbtmp/.pipe_in.$vimpid
pipe_out=~/.dbtmp/.pipe_out.$vimpid
sqlplus_pid_file=~/.dbtmp/.sqlplus_pid.$vimpid
start_log=~/.dbtmp/start_$vimpid.log
rm -f $start_log
cur_pid=$$
SQL_END=SQL_END_$cur_pid

ChkVimPid()
{
	trap "" 2 3
	
	while true
	do
		#pid=`ps -ef|awk -v vimpid=$vimpid '{if ($2 == vimpid) print $2}'`
		#if [ "$pid" = "" ];then
		if ! kill -0 "$vimpid" 2>/dev/null; then
			db_disconnect.sh $vimpid
			exit
		fi
		sleep  200
	done
}

ReadPipe()
{
	while read -r line
	do
		#echo "line=[$line]"
		echo "$line"|grep "^ORA-" > /dev/null 2>&1 
		if [ $? -eq 0 ];then
			echo "$line" > $start_log
			break
		fi

		if [[ "$line" = "$SQL_END" ]];then
			break
		fi
	done < $pipe_out 
}

if [ ! -f $sqlplus_pid_file ];then
	#retvalue=`echo ""|sqlplus -s $DBUSER/$DBPASS 2>&1`
	#if [ "$retvalue" != "" ];then
	#	echo "Database connection failed"
	#	echo "$retvalue"
	#	#sleep 3
	#	exit 1
	#fi

	rm -f $pipe_in
	rm -f $pipe_out

	mkfifo $pipe_in
	mkfifo $pipe_out

	#Must be in -S mode.
	#-R must use 1 or not use -R at all; otherwise,spool file cannot be executed
	#tail -f $pipe_in|sqlplus -S $DBUSER/$DBPASS > $pipe_out &

	#ReadPipe&
	#read_pid=$!
	if  command -v setsid > /dev/null 2>&1 ;then
		if [ $# -eq 3 ];then
			setsid db_pipe_conn.sh $pipe_in $pipe_out $dbuser $dbpass&
		else
			setsid db_pipe_conn.sh $pipe_in $pipe_out &
		fi
	else  
		if set -m 2>/dev/null; then
			if [ $# -eq 3 ];then
				db_pipe_conn.sh $pipe_in $pipe_out $dbuser $dbpass&
			else
				db_pipe_conn.sh $pipe_in $pipe_out &
			fi
			set +m
		else
			echo "This Unix environment does not support job control"
			exit 1
		fi
	fi
	#Enable job control so that the process group ID (pgid) of the child process differs from that of the parent process, thereby preventing the child process from receiving interrupt signals.
	    
	ppid=$!

	ChkVimPid&
	chkvim_pid=$!
	
	ReadPipe&
	#sleep 0.2
	read_pid=$!
	(
		echo "SQL_START"
		echo "set echo off;"
		echo "set linesize 5000;"
		echo "set feedback on;"
		#echo "set trimout on;"
		echo "set heading on;"
		echo "set pagesize 50000;"
		echo "set autocommit off;"
		#Without adding 'format wrapped', dbms_output.put_line('    AAA'); will strip the leading spaces from the line when output.
		echo "set serveroutput on format wrapped;"
		#set recsep wrap
		#If a column of data is wrapped to a new line because it is too long, the record separator will be printed after that line.
		#off: Do not display record separators between lines.
		echo "set recsep off;"
		echo "set numwidth 17;"
		echo "set long 3000;"
		#echo "set trimspool on;"
		echo "set termout off;"
		echo "set timing on;"
		echo "alter session set nls_date_format='yyyy-mm-dd hh24:mi:ss';"
		echo "alter session set NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24:MI:SSXFF TZR';"
		echo "alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SSXFF';"
		echo "SET ESCAPE '\'"
		echo "prompt $SQL_END;"
	) > $pipe_in
	wait $read_pid

	awk_pid=`ps -ef|grep awk|awk -v ppid=$ppid '{if ($3 == ppid) print $2}'`
	if [ "$awk_pid" = "" ];then
		echo "awk process does not exist,Database connection failed"
		rm -f $pipe_in $pipe_out
		exit 1
	fi

	if [ -s $start_log ];then
		echo "Database connection failed"
		cat $start_log
		rm -f $start_log
		rm -f $pipe_in $pipe_out
		kill -9 $awk_pid > /dev/null 2>&1
		exit 1
	fi

	sqlplus_pid=`ps -ef|grep -v awk|awk -v ppid=$ppid '{if ($3 == ppid) print $2}'`
	if [ "$sqlplus_pid" = "" ];then
		echo "sqlplus process does not exist,Database connection failed"
		rm -f $pipe_in $pipe_out
		exit 1
	fi

	if [ "$chkvim_pid" = "" ];then
		echo "chkvim process does not exist,Database connection failed"
		rm -f $pipe_in $pipe_out
		exit 1
	fi

	echo "$sqlplus_pid $awk_pid $chkvim_pid" > $sqlplus_pid_file
else
	sqlplus_pid=`cat $sqlplus_pid_file|awk '{print $1}'`
	#pid2=`ps -ef|awk -v pid=$sqlplus_pid '{if ($2 == pid) print $2}'`
	#if [ "$pid2" = "$sqlplus_pid" ];then
	if ! kill -0 $sqlplus_pid 2>/dev/null; then
		awk_pid2=`cat $sqlplus_pid_file|awk '{print $2}'`
		kill -9 $awk_pid2 > /dev/null 2>&1

		chkvim_pid2=`cat $sqlplus_pid_file|awk '{print $3}'`
		kill -9 $chkvim_pid2 > /dev/null 2>&1

		rm -f $pipe_in
		rm -f $pipe_out

		mkfifo $pipe_in
		mkfifo $pipe_out

		if  command -v setsid > /dev/null 2>&1 ;then
			if [ $# -eq 3 ];then
				setsid db_pipe_conn.sh $pipe_in $pipe_out $dbuser $dbpass&
			else
				setsid db_pipe_conn.sh $pipe_in $pipe_out &
			fi
		else  
			if set -m 2>/dev/null; then
				if [ $# -eq 3 ];then
					db_pipe_conn.sh $pipe_in $pipe_out $dbuser $dbpass&
				else
					db_pipe_conn.sh $pipe_in $pipe_out &
				fi
				set +m
			else
				echo "This Unix environment does not support job control"
				exit 1
			fi
		fi
		    
		ppid=$!

		ChkVimPid&
		chkvim_pid=$!
		
		ReadPipe&
		#sleep 0.2
		read_pid=$!
		(
			echo "SQL_START"
			echo "set echo off;"
			echo "set linesize 5000;"
			echo "set feedback on;"
			#echo "set trimout on;"
			echo "set heading on;"
			echo "set pagesize 50000;"
			echo "set autocommit off;"
			echo "set serveroutput on format wrapped;"
			echo "set recsep off;"
			echo "set numwidth 17;"
			echo "set long 3000;"
			#echo "set trimspool on;"
			echo "set termout off;"
			echo "set timing on;"
			echo "alter session set nls_date_format='yyyy-mm-dd hh24:mi:ss';"
			echo "alter session set NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24:MI:SSXFF TZR';"
			echo "alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SSXFF';"
			echo "SET ESCAPE '\'"
			echo "prompt $SQL_END;"
		) > $pipe_in
		wait $read_pid

		awk_pid=`ps -ef|grep awk|awk -v ppid=$ppid '{if ($3 == ppid) print $2}'`
		if [ "$awk_pid" = "" ];then
			echo "awk process does not exist,Database connection failed"
			rm -f $pipe_in $pipe_out
			exit 1
		fi

		if [ -s $start_log ];then
			echo "Database connection failed"
			cat $start_log
			rm -f $start_log
			rm -f $pipe_in $pipe_out
			kill -9 $awk_pid > /dev/null 2>&1
			exit 1
		fi

		sqlplus_pid=`ps -ef|grep -v awk|grep -v awk|awk -v ppid=$ppid '{if ($3 == ppid) print $2}'`
		if [ "$sqlplus_pid" = "" ];then
			echo "sqlplus process does not exist,Database connection failed"
			rm -f $pipe_in $pipe_out
			exit 1
		fi

		if [ "$chkvim_pid" = "" ];then
			echo "chkvim process does not exist,Database connection failed"
			rm -f $pipe_in $pipe_out
			exit 1
		fi

		echo "$sqlplus_pid  $awk_pid $chkvim_pid" > $sqlplus_pid_file
	else
		echo "Database connection already exists!"
		exit 2
	fi
fi
exit 0
