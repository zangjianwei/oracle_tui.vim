################################################################################
#                           Disconnect the database connection                 #
#Author: Zang Jianwei                                                          #
################################################################################
if [ $# -ne 1 ];then
	echo "Usage:`basename $0` vimpid"
	exit 1
fi

lc_all=`locale|grep LC_all|awk -F"=" '{gsub(/"/, "", $2);print $2}'`

lc_utf_flag=`locale|grep LC_CTYPE|sed 's/"//g'|awk -F"=" '{print $2}'|awk -F. '{
		if (tolower($2) ~/utf/)
			print 1
		else
			print 0
	}'`

if [ $lc_utf_flag -eq 0 ];then
	if [ "$lc_all" != "" ];then
		export LC_ALL="$TUI_LC_CTYPE"
	else
		export LC_CTYPE="$TUI_LC_CTYPE"
	fi
fi

vimpid=$1

pipe_in=~/.dbtmp/.pipe_in.$vimpid
pipe_out=~/.dbtmp/.pipe_out.$vimpid
sqlplus_pid_file=~/.dbtmp/.sqlplus_pid.$vimpid
obj_file=~/.dbtmp/.dbobj.$vimpid
dblist_file=~/.dbtmp/.dblist_$vimpid.txt

if [ -s $sqlplus_pid_file ];then
	sqlplus_pid=`cat $sqlplus_pid_file|awk '{print $1}'`
	awk_pid=`cat $sqlplus_pid_file|awk '{print $2}'`
	chkvim_pid=`cat $sqlplus_pid_file|awk '{print $3}'`
	chkvim_child_pid=`ps -ef|awk -v pid=$chkvim_pid '{if ($3 == pid) print $2}'`

	comand=`ps -ef|awk -v pid=$sqlplus_pid '{if ($2 == pid) print $8}'`
	if [ "$comand" = "sqlplus" ];then
		#echo "quit" > $pipe_in
		(
			echo "SQL_START"
			echo "quit;"
		) > $pipe_in
	else
		kill -9 $sqlplus_pid > /dev/null 2>&1
	fi
	
	kill -9 $awk_pid > /dev/null 2>&1

	#Do not kill the child process first; otherwise, a sleep process will be spawned immediately.
	#ps -ef|awk -v pid=$chkvim_pid '{if ($3 == pid) print $2}'|xargs -I {}  kill -9 {} >/dev/null 2>&1
	kill -9 $chkvim_pid > /dev/null 2>&1
	kill -9 $chkvim_child_pid > /dev/null 2>&1

	rm -f $pipe_in
	rm -f $pipe_out
	rm -f $sqlplus_pid_file
	rm -f $obj_file
	rm -f $dblist_file
	rm -f $HOME/.dbtmp/${vimpid}_*_clearcol.col
fi

#echo "ok"
