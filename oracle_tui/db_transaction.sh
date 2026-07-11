################################################################################
#                        提交回滚事务                                          #
#作者:臧建伟                                                                   #
################################################################################
if [ $# -ne 2 ];then
	echo "Usage:$0 sql vimpid"
	exit
fi

sql="$1"
vimpid=$2

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

browfile=~/.dbtmp/${vimpid}_$$.txt
setfile=~/.dbtmp/set_$vimpid.sql
pipe_in=~/.dbtmp/.pipe_in.$vimpid
pipe_out=~/.dbtmp/.pipe_out.$vimpid
sqlplus_pid_file=~/.dbtmp/.sqlplus_pid.$vimpid
cur_pid=$$               
SQL_END=SQL_END_$cur_pid 

if [ ! -p $pipe_in ];then
	echo "未与sqlplus建立连接" > $browfile
	vim -c "set nonu" $browfile
	rm -f $browfile
	exit 3
fi

sqlplus_pid=`cat $sqlplus_pid_file|awk '{print $1}'`
#pid2=`ps -ef|awk -v pid=$sqlplus_pid '{if ($2 == pid) print $2}'`
#if [ "$pid2" != "$sqlplus_pid" ];then
if ! kill -0 $sqlplus_pid 2>/dev/null; then
	echo "与sqlplus断开" > $browfile
	vim -c "set nonu" $browfile
	rm -f $browfile
	exit 3
fi

ReadPipe()
{
	while read -r line
	do
		if [[ "$line" = "$SQL_END" ]];then
			break
		fi
	done < $pipe_out 
}


kill_waitpid()
{
	echo "pid $bg_pid is killed!"
	kill -9 $bg_pid 
	#必须要加下面一行,向当前的sqlplus发送一个中断信号,终止
	#当前啊正在运行的sql,否则在vim中运行该脚本中时会中断
	#当前正在运行的sql(不知道为什么),但在命令行下运行该
	#脚本有时不会中断当前的sql,会导致读取管道的时候乱掉
	kill -INT $sqlplus_pid
	int_flag=1
}      

int_flag=0
trap "kill_waitpid" 2 3  

ReadPipe&
read_pid=$!
(
	#强制刷新输出,否则像输入seect from tabname 则没有输出,输入set heading off也不会有输出
	#echo "store set $setfile"
	echo "SQL_START"
	echo "set linesize 100"
	echo "set feedback on"
	echo "set timing off"
	echo "set pagesize 100"
	echo "spool $browfile;"
	echo "$sql;"
	echo "spool off;"
	#恢复set设置
	#echo "@$setfile;"
	echo "prompt $SQL_END;"
) > $pipe_in

wait $read_pid

if [ $int_flag -eq 1 ];then
	echo "请求被中断" > $browfile
	vim -c "set nonu" $browfile
	rm -f $browfile
	#rm -f $setfile
	rm -f $sqlfile
	exit 3
fi

if [ ! -s $browfile ];then
	echo "执行完成" > $browfile
fi

cat $browfile|grep -v "^[ 	]*$"

rm -f $browfile
#rm -f $setfile

exit 0
