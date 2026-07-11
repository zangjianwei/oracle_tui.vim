################################################################################
#                        oracle查询工具                                        #
#                           老臧                                               #
################################################################################
if [ $# -ne 1 ];then
	echo "Usage:$0 sql"
	exit
fi

set -o noglob
#~/user/zjw/bin/regsql $1
#echo "test:$1"

echo "$1" |grep -i "^[ 	]*select" >/dev/null 2>&1
if [ $? -eq 0 ];then
	sel_flag=1
else
	sel_flag=0
fi

kill_waitpid()
{
	echo "pid $! is killed!"
	kill -9 $! 
}      

trap "kill_waitpid" 2 3  

echo "$1" > ~/tmp/$$.txt.sql   

browfile=~/tmp/$$.txt

rotate()
{
	str[1]="-"
	str[2]="\\"
	str[3]="|"
	str[4]="/"
	clear     #清屏
	n=1
	while true
	do
	    echo -e "\033[12;30H Waiting...${str[$n]}"
		n=`echo $n|awk '{print ($0+1)%5}'`
	    if [ $n -eq 0 ]; then
	         n=1
	    fi
	    sleep 1
	done 
}
rotate &   
#从作业表中移除,否则会显示:31477 Killed                  rotate
disown $!

if [ $sel_flag -eq 1 ];then
	sql=`echo $1|awk '{print tolower($0)}'`
	echo $sql|grep -i where > /dev/null 2>&1
	if [ $? -eq 0 ];then
		tmpstr=`echo $sql|sed 's/where/WHERE/'`
		tabname=`echo $tmpstr|sed 's/.*from[ 	]\{1,\}\(.*\)WHERE.*/\1/g'`
	else
		tabname=`echo $sql|sed 's/.*from[ 	]\{1,\}\(.*\)/\1/g'`
	fi
	echo $tabname|tr ',' '\n'|awk '{printf "desc %s;\n",$1}' > $HOME/tmp/$$.spl
	
	sqlplus -S $DBUSER/$DBPASS<<END >/dev/null
	set echo off;
	set linesize 300;
	set feedback on;
	set numwidth 17;
	set long 17;
	set pagesize 200;
	set termout off;
	set trimout on;
	set heading on;
	set trimspool on;
	spool $HOME/tmp/$$.desc
	@$HOME/tmp/$$.spl
	spool off;
	exit
END
grep -w -E "CHAR|VARCHAR2" $HOME/tmp/$$.desc|sed 's/ \([^ 	]\{1,\}\).*(\(.*\))/\1 \2/'|awk '{ if (length($1) < $2) max_len=$2;else max_len=length($1);if (max_len > arr_max[$1]) arr_max[$1] = max_len } END{ for (colname in arr_max) printf "column %s format a%d\n", colname, arr_max[colname] }' > $HOME/tmp/$$.col
fi

sqlplus -S $DBUSER/$DBPASS<<END >/dev/null
@$HOME/tmp/$$.col
set echo off;
set linesize 5000;
set feedback on;
set numwidth 17;
set long 17;
set termout off;
set trimout on;
set heading on;
set trimspool on;
set pagesize 50000;
spool $browfile;
$1;
spool off;
exit
END

rm -f $HOME/tmp/$$.spl
rm -f $HOME/tmp/$$.desc
rm -f $HOME/tmp/$$.col

kill -9 $!   > /dev/null 2>&1

if [ $sel_flag -eq 1 ]
then
	vim -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapView()|call oracle_tui#SetAutocmdView()|set ve=all" $browfile
else
	cat $browfile
fi

rm  $browfile
rm ~/tmp/$$.txt.sql   

