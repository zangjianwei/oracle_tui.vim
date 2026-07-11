################################################################################
#                           创建sqlplus连接                                    #
#作者:臧建伟                                                                   #
#tail在aix环境下接收消息时会有延迟,所以不用tail                                #
################################################################################
if [ $# -ne 2 -a $# -ne 4 ];then
	echo "Usage:`basename $0` pipe_in pipe_out [username] [password]"
	exit 1
fi
pipe_in=$1
pipe_out=$2

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

if awk 'BEGIN{fflush(); print "OK"}' 2>/dev/null | grep -q "OK"; then
	#tail -f $pipe_in|sqlplus -S $DBUSER/$DBPASS > $pipe_out
	#要加-n 100,否则只能取到后10行数据
	awk -v pipe_in=$pipe_in 'BEGIN {
		while (1)
		{
			while (getline < pipe_in)
			{
				if ($0 == "SQL_START")
				{
					start_flag = 1
					continue
				}
	
				if (start_flag == 1)
				{
					print $0
					#不加fflush()会导致缓冲延迟,sqlplus收不到信息
					fflush()
				}
	
				if ($0 ~ /prompt SQL_END/)
					start_flag = 0
			}
			close(pipe_in)
		}
	}' | sqlplus -S $DBUSER/$DBPASS > $pipe_out
else
	#tail -f $pipe_in|sqlplus -S $DBUSER/$DBPASS > $pipe_out
	#要加-n 100,否则只能取到后10行数据
	awk -v pipe_in=$pipe_in 'BEGIN {
		while (1)
		{
			while (getline < pipe_in)
			{
				if ($0 == "SQL_START")
				{
					start_flag = 1
					continue
				}
	
				if (start_flag == 1)
				{
					print $0
					#不加system("")会导致缓冲延迟,sqlplus收不到信息
					system("")
				}
	
				if ($0 ~ /prompt SQL_END/)
					start_flag = 0
			}
			close(pipe_in)
		}
	}' | sqlplus -S $DBUSER/$DBPASS > $pipe_out
fi
