################################################################################
#                        oracle查询工具(通过管道)                              #
#作者:臧建伟                                                                   #
# 本工具可显示完整列名,对于金额类型也可完整显示，但是对于派生的金额类型字段    #
# 则不能完整显示,可用cast(amt+0.001 as number(15,3)) 解决                      #
# 可支持多条sql同时执行                                                        #
# 注意:sqlplus中的linesize选项对查询性能影响很大，值越大查询越慢               #
################################################################################
if [ $# -ne 2 -a $# -ne 4 ];then
	echo "Usage:$0 vimpid flag [username] [password]"
	exit
fi

if [ $# -eq 4 ];then
	DBUSER=$3
	DBPASS=$4
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

set -o noglob
#~/user/zjw/bin/regsql $1
#echo "test:$1"

#read_begin_flag=0
ReadPipe()
{
	while read -r line
	do
		#echo "line=[$line]"

		#将上次被中断查询产生的clear_col_file删除
		#SQL_BEGIN_$pid 有可能收不到!!!
		#正确的逻辑是收到SQL_END_$curr_pid,就要退出循环
		#不用管SQL_BEGIN怎么样
		echo "$line"|grep SQL_END_ > /dev/null 2>&1
		if [ $? -eq 0 ];then
			clear_pid=`echo "$line"|sed 's/SQL_END_//g'`
			if [ "$clear_pid" != "$cur_pid" ];then
				rm -f $HOME/.dbtmp/${vimpid}_${clear_pid}_clearcol.col
				continue
			else
				#read_begin_flag=0
				break
			fi
		fi

		#if [[ "$line" = "$SQL_BEGIN" ]];then
		#	read_begin_flag=1
		#	continue
		#fi

		#if [[ "$read_begin_flag" != "1" ]];then
		#	continue
		#fi

		#if [[ "$line" = "$SQL_END" ]];then
		#	read_begin_flag=0
		#	break
		#fi
	done < $pipe_out 

	#如果执行时被中断，要等读取完记过之后再删除clear_col_file,
	#否则，再执行@clear_col_file时该文件已经被删了
	#if [ "$1" = "-f" ];then
	#	rm -f $clear_col_file
	#fi
}

vimpid=$1
pipe_in=~/.dbtmp/.pipe_in.$vimpid
pipe_out=~/.dbtmp/.pipe_out.$vimpid
sqlplus_pid_file=~/.dbtmp/.sqlplus_pid.$vimpid
browfile=~/.dbtmp/$vimpid.txt
#setfile=~/.dbtmp/${vimpid}_set.sql
sqlfile=~/.dbtmp/$vimpid.txt.sql
procfile=$HOME/.dbtmp/${vimpid}_proc.sql
descfile=$HOME/.dbtmp/$vimpid.desc
one_select_flag=$2
cur_pid=$$
#SQL_BEGIN=SQL_BEGIN_$cur_pid
SQL_END=SQL_END_$cur_pid

browfile=~/.dbtmp/$vimpid.txt

if [ ! -s $sqlfile ];then
	echo "没有sql语句" > $browfile
	vim -c "set nonu" $browfile
	rm -f $browfile
	exit 3
fi

#下面清空管道没用，因为有可能数据还没到管道
#先清空管道
#dd if=$pipe_out of=/dev/null bs=1024 count=1000 2>/dev/null iflag=nonblock
#timeout 0.2 cat $pipe_out 
#cat $pipe_out > /dev/null 2>&1 &
#cat $pipe_out &
#cat_pid=$!
#sleep 1
#kill $cat_pid 2>/dev/null

sql=`awk '{
	if (NR > 1)
		print prev_line
	prev_line = $0
	}
	END{
		gsub(/;[ \t]*$/, "", prev_line)
		print prev_line
	}' $sqlfile`

if [ ! -p $pipe_in ];then
	echo "未与sqlplus建立连接" > $browfile
	vim -c "set nonu" $browfile
	rm -f $browfile
	rm -f $sqlfile
	exit 3
fi

sqlplus_pid=`cat $sqlplus_pid_file|awk '{print $1}'`
#pid2=`ps -ef|awk -v pid=$sqlplus_pid '{if ($2 == pid) print $2}'`
#if [ "$pid2" != "$sqlplus_pid" ];then
if ! kill -0 $sqlplus_pid 2>/dev/null; then
	echo "与sqlplus断开" > $browfile
	vim -c "set nonu" $browfile
	rm -f $browfile
	rm -f $sqlfile
	exit 3
fi

kill_waitpid()
{
	#echo "pid $bg_pid is killed!"
	kill -9 $bg_pid 

	#echo "prompt SQL_END;" > $pipe_in
	#必须要加下面一行,向当前的sqlplus发送一个中断信号,终止
	#当前啊正在运行的sql,否则在vim中运行该脚本中时会中断
	#当前正在运行的sql(不知道为什么),但在命令行下运行该
	#脚本有时不会中断当前的sql,会导致读取管道的时候乱掉

	#必须加下面这行,否则中断后再执行会有问题
	kill -INT $sqlplus_pid
	int_flag=1

	#sqlplus收到中断后，sql还会继续运行，用下面方法可彻底停止sql运行
	#(
	#	echo "SQL_START"
	#	echo "prompt $SQL_BEGIN;"
	#	echo "select 1 from dual;"
	#	echo "prompt $SQL_END;"
	#) > $pipe_in
}      

int_flag=0
trap "kill_waitpid" 2 3  

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
	    #echo -e "\033[12;10H Executing SQL,You can press Ctrl+c to interrupt...${str[$n]}"
	    printf "\033[12;10H Executing SQL,You can press Ctrl+c to interrupt...${str[$n]} \n"
	    #echo -e "\033[24;5H Press Ctrl+c to interrupt"
		n=`echo $n|awk '{print ($0+1)%5}'`
	    if [ $n -eq 0 ]; then
	         n=1
	    fi
	    sleep 1
	done 
}

rotate &   
bg_pid=$!
#从作业表中移除,否则会显示:31477 Killed                  rotate
if  command -v disown > /dev/null 2>&1 ;then
	disown $bg_pid
fi

if [ $one_select_flag -eq 1 ];then
	cat << EOF > $procfile
	set serveroutput on; 
	DECLARE 
	    c NUMBER; 
	    d NUMBER; 
	    col_cnt INTEGER; 
	    rec_tab DBMS_SQL.DESC_TAB; 
	    col_num NUMBER; 
	BEGIN 
	    c := DBMS_SQL.OPEN_CURSOR; 
	    DBMS_SQL.PARSE(c, q'[$sql]', DBMS_SQL.NATIVE);
	    d := DBMS_SQL.EXECUTE(c); 
	    DBMS_SQL.DESCRIBE_COLUMNS(c, col_cnt, rec_tab); 
	 
	    FOR col_num IN 1..col_cnt LOOP 
	        DBMS_OUTPUT.PUT_LINE(rec_tab(col_num).col_name||'@'||rec_tab(col_num).col_type||'@'||rec_tab(col_num).col_max_len||'@'||rec_tab(col_num).col_precision||'@'||rec_tab(col_num).col_scale||'@'||rec_tab(col_num).col_charsetform); 
	    END LOOP; 
	 
	    DBMS_SQL.CLOSE_CURSOR(c); 
	END; 
	/ 
EOF

	ReadPipe&
	read_pid=$!
	#if  command -v disown > /dev/null 2>&1 ;then
	#	disown $read_pid
	#fi
	(
		#强制刷新输出,否则像输入seect from tabname 则没有输出,输入set heading off也不会有输出
		#echo "store set $setfile"
		#echo "set echo off;"
		echo "SQL_START"
		#发送SQL_BEGIN没用了
		#echo "prompt $SQL_BEGIN;"
		echo "set timing off;"
		echo "set linesize 80;"
		echo "set feedback off;"
		#echo "set numwidth 20;"
		#echo "set long 3000;"
		echo "set pagesize 200;"
		echo "set termout off;"
		#echo "set trimout on;"
		#echo "set heading on;"
		#echo "set trimspool on;"
		#echo "spool off;"
		#echo "exec dbms_output.put_line('SQL_START');" 
		echo "spool $descfile"
		echo "@$procfile"
		#恢复set设置
		#echo "@$setfile;"
		echo "spool off;"
		echo "prompt $SQL_END;"
	) > $pipe_in

	wait $read_pid

	if [ $int_flag -eq 1 ];then
		echo "请求被中断!" > $browfile
		vim -c "set nonu"  $browfile
		rm -f $descfile
		rm -f $browfile
		#rm -f $setfile
		rm -f $procfile
		rm -f $sqlfile
		exit 3
	fi

	file_len=$HOME/.dbtmp/$vimpid.len
	set_col_file=$HOME/.dbtmp/${vimpid}_setcol.col
	clear_col_file=$HOME/.dbtmp/${vimpid}_${cur_pid}_clearcol.col
	>$set_col_file
	>$clear_col_file
	grep "^ORA-" $descfile > /dev/null 2>&1
	if [ $? -eq 0 ];then
		linesize=20000
	else
		cat $descfile|awk -v file_len=$file_len \
		                             -v set_col_file=$set_col_file \
									 -v clear_col_file=$clear_col_file  -F"@" '{ 
			if ($2 == 1 || $2 == 96) #char or varchar2/nchar or nvarchar2
			{
				arr_type[$1] = "C"

				if ($6 == 2)
				{
					#nchar/nvarchar2 长度要乘以2
					$3 = $3*2
				}

				if (length($1) < $3) 
					max_len=$3;
				else 
					max_len=length($1);

				arr_max[$1] = max_len 

				$3 = max_len
			}
			else if ($2 == 2) #number
			{
				if ($4 > 0 && $5 > 0)
				{
					arr_type[$1] = "N"

					if (length($1) < $4 + 1) 
						max_len=$4 + 1;
					else 
						max_len=length($1);

					if (length($1) > max_len) 
						max_len=length($1);

					arr_tot_len[$1] = max_len 

					arr_last_len[$1] = $5
				}
				else
				{
					if (length($1) > $3) 
						max_len=length($1);
					else
						max_len=$3
				}

				$3 = max_len 
			}
			else if ($2 == 12) #date
			{
				$3 = 30

				if (length($1) > $3) 
					$3=length($1);
			}
			else if ($2 == 208) #urowid
			{
				$3 = 30
				arr_type[$1] = "C"

				if (length($1) > $3) 
					$3=length($1);

				arr_max[$1] = $3
			}
			else if ($2 == 180) #timestamp
			{
				$3 = 150
			}
			else if ($2 == 181) #timestamp with time zone
			{
				$3 = 200
			}
			else if ($2 == 231) #timestamp with local time zone
			{
				$3 = 200
			}
			else if ($2 == 23) #raw
			{
				$3 = $3*2

				if (length($1) > $3) 
					$3=length($1);
			}
			else if ($2 == 100) #binary_float
			{
				$3 = 30

				if (length($1) > $3) 
					$3=length($1);
			}
			else if ($2 == 101) #binary_double
			{
				$3 = 30

				if (length($1) > $3) 
					$3=length($1);
			}
			else if ($2 == 182) #interval year to month
			{
				$3 = 80
			}
			else if ($2 == 183) #interval day to second
			{
				$3 = 80
			}
			else if ($2 == 8) #long 该类型$3为0
			{
				$3 = 1000
			}

			tot_len = tot_len + $3 + 2
		} 
		END { 
			for (colname in arr_type) 
			{
				#clear_str = ""
				clear_str = sprintf("column %s clear", colname)

				if (arr_type[colname] == "C")
				{
					#set_str = ""
					set_str = sprintf("column %s format a%d", colname, arr_max[colname] )
				}
				else
				{
					set_str = sprintf("column %s format ", colname)

					for (i=1;i<arr_tot_len[colname] - arr_last_len[colname]; i++)
					{
						set_str = sprintf("%s%d", set_str, 9)
					}
					set_str = sprintf("%s%s", set_str ,"0.")
					for (i=1;i<=arr_last_len[colname]; i++)
					{
						set_str = sprintf("%s%d", set_str , 9)
					}
					#set_str = sprintf("%s%s", set_str , "\n")
				}
				print set_str >> set_col_file
				print clear_str >> clear_col_file
			}
			#tot_len = tot_len + 100
			print tot_len > file_len
		}' 

		linesize=`cat $file_len`
	fi

	if [ $linesize -ge 32767 ];then
		linesize=32767
	fi

	ReadPipe&
	read_pid=$!
	#加disown nohup 后wait就不会等待
	#if  command -v disown > /dev/null 2>&1 ;then
	#	disown $read_pid
	#fi
	(
		#强制刷新输出,否则像输入seect from tabname 则没有输出,输入set heading off也不会有输出
		echo "SQL_START"
		#发送SQL_BEGIN没用了
		#echo "prompt $SQL_BEGIN;"
		echo "@$set_col_file;"
		#echo "set echo off;"
		echo "set heading on;"
		echo "set feedback on;"
		echo "set timing on;"
		echo "set linesize $linesize;"
		#echo "set feedback on;"
		#echo "set numwidth 20;"
		#echo "set long 3000;"
		#echo "set termout off;"
		#echo "set trimout on;"
		#echo "set heading on;"
		#echo "set trimspool on;"
		echo "set pagesize 50000;"
		#echo "spool off;"
		#echo "exec dbms_output.put_line('SQL_START');" 
		echo "spool $browfile;"
		echo "@$sqlfile"
		#echo "$sqlstr"
		echo "spool off;"
		#要恢复列的设置，否则会影响别的查询
		#如果执行sql时被中断(按下Ctrl+C),下面的语句也会被执行
		echo "@$clear_col_file;"  
		#恢复set设置
		#echo "@$setfile;"
		echo "prompt $SQL_END;"
	) > $pipe_in

	wait $read_pid
	
	#中断时要杀掉ReadPipe,否则可能会出现下列情况
	#管道中断时查询结果还没到达，要登到下次查询时才会到达
	#如果不杀掉ReadPipe，会造成下次查询时新旧两个ReadPipe
	#同时去读管道，但是现在读管道是按进程号来读的，会有
	#旧ReadPipe读的是新查询的SQL_BEGIN,SQL_END,
	#新ReadPipe读的是旧查询的SQL_BEGIN,SQL_END
	#情况，会导致循环不会退出
	if [ $int_flag -eq 1 ];then
		kill -9 $read_pid > /dev/null 2>&1
	else
		kill -9 $bg_pid   > /dev/null 2>&1
		rm -f $clear_col_file
	fi

	rm -f $procfile
	rm -f $descfile
	rm -f $set_col_file
	rm -f $file_len
else
	ReadPipe&
	read_pid=$!
	#if  command -v disown > /dev/null 2>&1 ;then
	#	disown $read_pid
	#fi

	#发现了一个很奇怪的事情,在vim中执行该脚本时如果按
	#中断键,则sqlplus也能收到中断并即刻返回,但是用在
	#命令行下执行则sqlplus收不到中断
	(
		#强制刷新输出,否则像输入seect from tabname 则没有输出,输入set heading off也不会有输出
		#强制刷新方法 
		#select 1 from dual where 1=2;
		#或host sleep 0
		#echo "set echo on;"
		#echo "set trimout on;"
		#echo "set trimspool on;"
		#echo "set numwidth 20;"
		
		#echo "store set $setfile"
		echo "SQL_START"
		#发送SQL_BEGIN没用了
		#echo "prompt $SQL_BEGIN;"
		echo "set heading on;"
		echo "set feedback on;"
		echo "set timing on;"
		echo "set linesize 10000;"
		echo "set pagesize 50000;"
		#echo "set feedback on;"
		#echo "spool off;"
		#echo "exec dbms_output.put_line('SQL_START');" 
		echo "spool $browfile;"
		echo "@$sqlfile;"
		#不能恢复set设置，否则执行set命令后会恢复设置
		#echo "@$setfile;"
		echo "spool off;"
		echo "prompt $SQL_END;"
	) > $pipe_in

	#先往管道中写再读有时可能会有问题,会读不出管道中内容
	#比如那些不会强制刷新缓存的语句
	#例如:set linesize 100 
	#     pubbaseinfo;
	#往管道中写之前先放在后台中读取,则能读出管道中的所有内容
	#while read -r line
	#do
	#	if [[ "$line" = "SQL_END" ]];then
	#		break
	#	fi
	#done < $pipe_out 

	wait $read_pid

	#不能要下面部分，它会把查询的输出也输出到$browfile中
	#况且中断以后就是要把已经执行的结果输出
	#if [ $int_flag -eq 1 ];then
	#	echo "用户中断了请求" > $browfile
	#	vim -c "set nonu" $browfile
	#	rm -f $browfile
	#	#rm -f $setfile
	#	rm -f $sqlfile
	#	exit 3
	#fi

	if [ $int_flag -eq 1 ];then
		kill -9 $read_pid > /dev/null 2>&1
	else
		kill -9 $bg_pid   > /dev/null 2>&1
	fi
fi

if [ ! -s $browfile ];then
	if [ $int_flag -ne 1 ];then
		echo "执行完成" > $browfile
	else
		echo "执行被中断" > $browfile
	fi
	vim -c "set nonu" $browfile
else
	#要加-u NONE(不加载默认配置),否则调用ShowUpdateTitle()时光标停在第5行，且不能向上移动
	if [ $one_select_flag -eq 1 ];then
		suc_flag=`sed -n '3p' $browfile|awk '{if ($0 ~ /^[- ][- ]*$/) print 1}'`
		if [ "$suc_flag" = "1" ];then
			vim -u NONE -c "call oracle_tui#SetUsername('$DBUSER')|call oracle_tui#SetPassword('$DBPASS')|call oracle_tui#SetLocal()|call oracle_tui#ShowViewTitle()|call oracle_tui#SetMapView()|call oracle_tui#SetAutocmdView()|set ve=all|normal! gg" $browfile
		else
			vim -u NONE -c "call oracle_tui#SetLocal()" $browfile
		fi
	else
		vim -u NONE -c "call oracle_tui#SetLocal()|set ve=all" $browfile
	fi
fi

rm -f $browfile
#rm -f $setfile
rm -f $sqlfile


exit 0
