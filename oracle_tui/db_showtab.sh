################################################################################
#                     导出表结构说明(crtdb.txt中)                              #
#作者:臧建伟                                                                   #
################################################################################
if [ $# -ne 1 ];then
	echo "Usage:`basename $0` tabname"
	exit 1
fi

tabname=`echo "$1"|awk '{print tolower($0)}'`

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

filename=~/.dbtmp/tab_$$.txt
>$filename
awk -v tabname=$tabname -v filename=$filename 'BEGIN{
	str = "表名[ \t][ \t]*"tabname"[ \t]"
	show_flag = 0
}
{
	if ($0 ~ str)
	{
		show_flag = 1
	}
	else
	{
		if ($0 ~ /^[ \t]*表名/)
			show_flag = 0
	}
	if (show_flag == 1)
	{
		print >> filename
	}
}' ~/oracle_tui/crtdb.txt

awk -v tabname=$tabname -v filename=$filename 'BEGIN{
	str = "表名[ \t][ \t]*"tabname"[ \t]"
	show_flag = 0
}
{
	if ($0 ~ str)
	{
		show_flag = 1
	}
	else
	{
		if ($0 ~ /^[ \t]*表名/)
			show_flag = 0
	}
	if (show_flag == 1)
	{
		print >> filename
	}
}' ~/oracle_tui/kjdb.txt

if [ -s $filename ];then
	cat $filename
	rm -f $filename
	exit 0
else
	rm -f $filename
	exit 1
fi
