################################################################################
#                             Updating Data
# Return value description: 
# 0 Success
# 1 Update failed
# 2 LOADTOTABLE mode does not support modifications involving BLOB fields
# 3 No changes made
# 4 Database connection interrupted
# 5 LC_CTYPE is not UTF-8
# 6 Error processing file in LOADTOTABLE mode
# 7 Error copying table
# 8 Error generating ctrl file
# 9 Error loading data
# 10 AWK syntax error when generating update SQL
# 11 Error generating update SQL
# 12 SQL syntax error
# 13 Operation interrupted
# 14 Generated PL/SQL execution error
# 15 Command line parameter error
# Interruption is prohibited, because the rollback time after interruption
# would be very long.
# Author: Zang Jianwei
################################################################################
if [ "$1" = "-h" -o $# -ne 1 -a $# -ne 3 ];then
    echo "Usage:`basename $0` shortfile"
	shortfile=`basename $1`
	>~/.dbtmp/$shortfile.err.15
    exit 15
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

trap "" 2 3

dir=$HOME/.dbtmp
shortfile=`basename $1`
filename=`basename $1`
newfile=$filename.dif.new
newfile=`echo $newfile|sed 's/-/_/'`
oldfile=$filename.dif.old
oldfile=`echo $oldfile|sed 's/-/_/'`
vimpid=`echo $filename|awk -F- '{print $2}'|sed 's/\.txt.new//'`
col_len_file=~/.dbtmp/${vimpid}_col.txt
updatesql_file=$dir/${vimpid}_update.sql
crttab_file=$dir/${vimpid}_crttab.log
fgf=""
cur_pid=$$                  
SQL_END=SQL_END_$cur_pid    
browfile=$dir/${vimpid}_updres.txt

ReadPipe()
{
	while read -r line
	do
		if [[ "$line" = "$SQL_END" ]];then
			break
		fi
	done < $pipe_out 
}

CrtSql()
{
	#Main file.
	main_file=$1  
	#Auxiliary file.
	aux_file=$2
	#Output file.
	outfile=$3
	table=$unit
	awk -v fgf=$fgf -v table=$table \
		-v install_file=$outfile \
		-v col_file=$col_len_file \
		-v aux_file=$aux_file \
		-v toolong_flag=$toolong_flag \
		-v lob_file_flag=$lob_file_flag \
		-v lob_file_dir="$HOME/.dbtmp" \
		-v errfile=$browfile \
		'function SetVarByValue(colname, coltype, value, install_file)
		{
			#The maximum length of a line in SQL*Plus cannot exceed 2499 bytes 
			#(maximum 2499/3 = 833 multi-byte characters).
			#block_len must be an even number; 
			#otherwise, there will be issues when truncating BLOB/RAW data.
			block_len = 750;
			
			len = length(value)
			if (len == 0)
			{
				if (coltype == "blob" || coltype == "long raw")
				{
					setvar = sprintf("var_%s := NULL;", colname);
				}
                else
				{
					setvar = sprintf("var_%s := \047\047;", colname);
				}
				printf("    %s\n", setvar) >> install_file
			}
			else
			{
				if (len <= block_len)
				{
					gsub("\047", "\047\047", value)
					if (coltype == "blob" || coltype == "long raw")
						setvar = sprintf("var_%s := HEXTORAW(\047%s\047);", colname, value);
					else
						setvar = sprintf("var_%s := \047%s\047;", colname, value);
					printf("    %s\n", setvar) >> install_file
				}
				else
				{
					if (coltype == "blob" || coltype == "long raw")
					{
						print "    v_blob := NULL;" >> install_file
						print "    DBMS_LOB.CREATETEMPORARY(v_blob, TRUE);" >> install_file

						for(m=1; m<=len; m+=block_len)
						{
							str = substr(value, m, block_len)

							printf("    v_blob_str := \047%s\047;\n", str) >> install_file
							print  "    v_blob_raw := HEXTORAW(v_blob_str);   " >> install_file
    						print  "    DBMS_LOB.WRITEAPPEND(v_blob, UTL_RAW.LENGTH(v_blob_raw), v_blob_raw); " >> install_file
							print  "" >> install_file
						}
						printf("    var_%s := v_blob;\n", colname) >> install_file
						print  "    DBMS_LOB.FREETEMPORARY(v_blob);" >> install_file
					}
					else
					{
						if (coltype == "clob" || coltype == "nclob")
						{
							print "    v_clob := NULL;" >> install_file
							print "    DBMS_LOB.CREATETEMPORARY(v_clob, TRUE);" >> install_file
						}

						for(m=1; m<=len; m+=block_len)
						{
							block_str = substr(value, m, block_len)
							gsub("\047", "\047\047", block_str)

							if (coltype == "clob" || coltype == "nclob")
							{
								printf("    v_chunk := \047%s\047;\n", block_str) >> install_file
    							print  "    DBMS_LOB.WRITEAPPEND(v_clob, length(v_chunk), v_chunk); " >> install_file
							}
							else
							{
								if (m == 1)
								{
									printf("    var_%s := \047%s\047 ||\n", colname, block_str) >> install_file
								}
								else
								{
									if (m + block_len <= len)
										printf("        \047%s\047 ||\n", block_str) >> install_file
									else
										printf("        \047%s\047;", block_str) >> install_file
								}
							}
						}

						if (coltype == "clob" || coltype == "nclob")
						{
							printf("    var_%s := v_clob;\n", colname) >> install_file
							print "    DBMS_LOB.FREETEMPORARY(v_clob);" >> install_file
						}
					}
				}
				if (coltype ~ /char/ || coltype ~/clob/)
				{
					printf("    var_%s := replace(var_%s, \047\047, chr(10));\n", colname, colname) >> install_file
				}
				print  "" >> install_file
			}
		}
		BEGIN{
			OFS = fgf

			if (toolong_flag == 1)
			{
				print "declare" >> install_file
  				print "    v_chunk VARCHAR2(3000);"   >> install_file
                print "    v_clob clob;"               >> install_file
				print "    v_blob blob; "              >> install_file
			}

			i = 0;
			while (getline < col_file)
			{
				i++
				arr_name[i] = tolower($1)
				arr_col_length[i] = tolower($3)

				if ($2 == 96)
				{
					if ($5 == 2)
						arr_col_type[i] = "nchar"
					else
						arr_col_type[i] = "char"
				}
				else if ($2 == 1)
				{
					if ($5 == 2)
						arr_col_type[i] = "nvarchar2"
					else
						arr_col_type[i] = "varchar2"
				}
				else if ($2 == 112)
				{
					if ($5 == 2)
						arr_col_type[i] = "nclob"
					else
						arr_col_type[i] = "clob"
				}
				else if ($2 == 2)
				{
					arr_col_type[i] = "number"
				}
				else if ($2 == 8)
				{
					arr_col_type[i] = "long"
				}
				else if ($2 == 11)
				{
					arr_col_type[i] = "rowid"
				}
				else if ($2 == 12)
				{
					arr_col_type[i] = "date"
				}
				else if ($2 == 23)
				{
					arr_col_type[i] = "raw"
				}
				else if ($2 == 24)
				{
					arr_col_type[i] = "long raw"
				}
				else if ($2 == 69)
				{
					arr_col_type[i] = "urowid"
				}
				else if ($2 == 100)
				{
					arr_col_type[i] = "binary_float"
				}
				else if ($2 == 101)
				{
					arr_col_type[i] = "binary_double"
				}
				else if ($2 == 180)
				{
					arr_col_type[i] = "timestamp"
				}
				else if ($2 == 181)
				{
					arr_col_type[i] = "timestamp with time zone"
				}
				else if ($2 == 231)
				{
					arr_col_type[i] = "timestamp with local time zone"
				}
				else if ($2 == 113)
				{
					arr_col_type[i] = "blob"
					has_blob_flag = 1
				}
				else if ($2 == 114)
				{
					arr_col_type[i] = "bfile"
				}
				else if ($2 == 208)
				{
					arr_col_type[i] = "urowid"
				}
				else if ($2 == 182)
				{
					arr_col_type[i] = "interval year to month"
				}
				else if ($2 == 183)
				{
					arr_col_type[i] = "interval day to second"
				}
				else
				{
					printf("Illegal data type[%d]\n", $2);
					exit
				}

				if (toolong_flag == 1)
				{
					if (arr_col_type[i] ~ /char/) 
					{
						printf("    var_%s %s(%d);\n", arr_name[i], arr_col_type[i], arr_col_length[i]) >> install_file
					}
					if (arr_col_type[i] ~ /clob/ || arr_col_type[i] ~ /blob/ || arr_col_type[i] ~ /long/) 
					{
						printf("    var_%s %s;\n", arr_name[i], arr_col_type[i]) >> install_file
					}
				}
			}
			num_col = i

			if (toolong_flag == 1)
			{
				if (has_blob_flag == 1)
				{
                	print "    v_blob_str VARCHAR2(5000);     " >> install_file
                	print "    v_blob_raw RAW(5000);          " >> install_file
				}
			}

			print "begin" >> install_file
			print "    SAVEPOINT start_point;" >> install_file

			FS = fgf

			while (getline < aux_file)
	    	{
				#Remove trailing characters with NBSP
				gsub(/ *$/,"",$1)
				
				delete_str = sprintf("delete from %s where rowid = \047%s\047;", 
						table, $1);

	
				print "    "delete_str >> install_file
	    	}
	}
	{
		linebak = $0
		#Process the new file.

		for(i = 2; i <= NF; i++)
		{
			#Remove trailing NBSP characters 
			#Replacing consecutive NBSP characters with empty depends on whether LC_CTYPE is set to UTF-8.
			#If it is not UTF-8, it is considered multi-byte, and only the last NBSP character will be replaced.
			gsub(/ *$/,"",$i)
			if (arr_col_type[i] ~ /char/ \
				|| arr_col_type[i] ~ /timestamp/ \
				|| arr_col_type[i] == "date" \
				|| arr_col_type[i] ~ /clob/ \
				|| arr_col_type[i] ~ /blob/ \
				|| arr_col_type[i] ~ /long/ \
				|| arr_col_type[i] == "raw" )
			{
				#Replace the NBSP characters at the beginning and in the middle with spaces.
				gsub(/ /," ",$i)

				#char Remove trailing spaces.
				#varchar2 and clob not Remove trailing spaces.
				if (arr_col_type[i] == "char" || arr_col_type[i] == "nchar")
				{
					if (match($i,/^  *$/))
					{
						#If they are all spaces, keep one space.
						gsub(/  */," ",$i)
					}
					else
					{
						#Remove trailing spaces.
						gsub(/  *$/,"",$i)
					}
				}

				if (arr_col_type[i] ~ /timestamp/ || arr_col_type[i] == "date" || arr_col_type[i] == "raw")
				{
					#Remove trailing and leading spaces.
					gsub(/^ */,"",$i)
					gsub(/ *$/,"",$i)
				}
			}
			else if (arr_col_type[i] ~ /interval/ )
			{
				#INTERVAL YEAR TO MONTH/INTERVAL DAY TO SECOND
				#Delete leading characters that are ASCII 255 or spaces.
				gsub(/^ */,"",$i)
				gsub(/^ */,"",$i)

				#Remove trailing spaces.
				gsub(/ *$/,"",$i)

				#Replace the NBSP characters in the middle with spaces.
				gsub(/ /," ",$i)
			}
			else
			{
				#Non-character.
				#Remove characters with NBSP and spaces.
				gsub(/ /,"",$i)
				gsub(/ /,"",$i)
			}
		}

		insert_str = sprintf("insert into %s values (", table)
		for(i = 2; i <= NF; i++)
		{
			#When inserting, replace the single quotes in `:where brcattr='1'` with two single quotes: `:where brcattr=''1''`.
			value = $i
			gsub("\047", "\047\047", $i)

			colname = arr_name[i]
			#Add double quotes on both sides.
			if (arr_col_type[i] ~ /char/ \
				|| arr_col_type[i] ~ /timestamp/ \
				|| arr_col_type[i] == "date" \
				|| arr_col_type[i] ~ /clob/ \
				|| arr_col_type[i] ~ /long/ \
				|| arr_col_type[i] ~ /blob/ \
				|| arr_col_type[i] ~ /long raw/ \
				|| arr_col_type[i] ~ /interval/ \
				|| arr_col_type[i] == "raw" \
				|| arr_col_type[i] == "urowid")
			{
				#If the string is too long, an error will occur when executing the SQL. It needs to be split into segments, concatenated, and assigned to a variable, then replaced with the variable in the SQL execution.
				if ((arr_col_type[i] ~ /char/ \
					|| arr_col_type[i] ~ /clob/ \
					|| arr_col_type[i] ~ /blob/ \
					|| arr_col_type[i] ~ /long/) \
					&& toolong_flag == 1)
				{
					if ((arr_col_type[i] ~ /clob/ \
						|| arr_col_type[i] ~ /blob/ \
						|| arr_col_type[i] ~ /long/) \
						&& lob_file_flag == 1)
					{
						lob_file = value
						gsub(" ", "", value)
						gsub(" ", "", lob_file)
						#printf("lob_file=[%s]\n",lob_file)
						if (lob_file != "")
						{
							gsub("<", "", lob_file)
							gsub(">", "", lob_file)
							gsub(" *$", "", lob_file)
							lob_file = sprintf("%s/%s", lob_file_dir, lob_file)

							if ((getline lob_line < lob_file) < 0) 
							{
							    close(lob_file)
    						    printf("Cannot modify the filename of a LOB field[%s]!\n", lob_file) > errfile
								exit
							}
		                    else
							{
								lob_value = lob_line
								k = 1
								
								while ((getline lob_line < lob_file) > 0)
								{
								 	lob_value = lob_value "" lob_line
									k++
								}
								close(lob_file)
								SetVarByValue(colname, arr_col_type[i], lob_value, install_file)
							}
						}
						else
						{
							SetVarByValue(colname, arr_col_type[i], value, install_file)
						}
					}
					else
					{
						SetVarByValue(colname, arr_col_type[i], value, install_file)
					}
					$i = "var_"colname
				}
				else
				{
					$i = "\047"$i"\047"
				}
			}
			if ((arr_col_type[i] == "nchar" ||arr_col_type[i]  == "nvarchar2"||arr_col_type[i]  == "nclob") && toolong_flag != 1)
			{
				$i = "N"$i
			}
			else if (arr_col_type[i] ~ /interval.*year/)
			{
				if ($i == "\047\047")
					$i = "null"
				else
					$i = "INTERVAL "$i" YEAR TO MONTH"
			}
			else if (arr_col_type[i] ~ /interval.*day/)
			{
				if ($i == "\047\047")
					$i = "null"
				else
					$i = "INTERVAL "$i" DAY TO SECOND"
			}

			if (i > 1)
				insert_str = sprintf("%s ", insert_str)
			if ($i == "")
			{
				insert_str = sprintf("%snull", insert_str)
			}
			else
			{
				insert_str = sprintf("%s%s", insert_str,$i)
			}
			if (i != NF)
				insert_str = sprintf("%s,", insert_str)
			else
				insert_str = sprintf("%s);", insert_str)
		}

		gsub(//, "\n" ,insert_str)
		print "    "insert_str >> install_file
	}
	END {
		print "" >> install_file 
		print "    EXCEPTION" >> install_file 
		print "        WHEN OTHERS THEN" >> install_file 
		print "            ROLLBACK TO start_point;" >> install_file 
		print "            DBMS_OUTPUT.PUT_LINE(SQLERRM);" >> install_file 
		print "end;" >> install_file
		print "/" >> install_file

	}' $main_file 

	if [ $? -ne 0 ];then
		kill -9 $bg_pid   > /dev/null 2>&1
		rm -f $updatesql_file   
		rm -f $dir/$newfile
		rm -f $dir/$oldfile
		>~/.dbtmp/$shortfile.err.10
		exit 10
	fi

	if [ -f $browfile ];then
	    return 1
	else
    	return 0
	fi

    return 0
}

DiffData()
{
	shortfile=$1
	newfile2=$shortfile.txt.new
	oldfile2=$shortfile.txt.old

	newfile2_tmp=$shortfile.txt.new.tmp
	oldfile2_tmp=$shortfile.txt.old.tmp

	sed -n '2,$ p' $dir/$newfile2 > $dir/$newfile2_tmp
	sed -n '2,$ p' $dir/$oldfile2 > $dir/$oldfile2_tmp
	
	diff ~/.dbtmp/$newfile2_tmp ~/.dbtmp/$oldfile2_tmp > ~/.dbtmp/$shortfile.dif
	result=$?
	rm -f $dir/$newfile2_tmp
	rm -f $dir/$oldfile2_tmp

	if [ $result -eq 0 ];then #The two files are identical.
		rm -f ~/.dbtmp/$shortfile.dif
		return 0
	else
		awk '/^< /' ~/.dbtmp/$shortfile.dif |sed 's/^< //'> ~/.dbtmp/$newfile
	
		awk '/^> /' ~/.dbtmp/$shortfile.dif |sed 's/^> //'> ~/.dbtmp/$oldfile
	
		rm -f ~/.dbtmp/$shortfile.dif
	
		return 1
	fi
}
DiffData $shortfile

if [ $? -eq 0 ];then
	#Return 3: No changes made.
	>~/.dbtmp/$shortfile.err.3
	exit 3
fi

IFS="
"

toolong_flag=`awk 'BEGIN{toolong_flag = 0}
	{ 
		#If it is of type VARCHAR2 with a length greater than 2900, or if it is of type CLOB, set the toolong_flag.
		if ($2 == 1 && $3 > 2900 || $2 == 112 || $2 == 8 || $2 == 113 || $2 == 24) 
		{
			toolong_flag = 1 
		}
		tot_len = tot_len + $3
	} 
	END{ 
		if (tot_len > 2800)
			toolong_flag = 1
		print toolong_flag 
	}' $col_len_file`

lob_file_flag=0

unit=`echo $filename|sed 's/^p_//'|awk -F- '{print $1}'`
echo $unit|grep "^c_" > /dev/null 2>&1
if [ $? -eq 0 ];then
	lob_file_flag=1
	unit=`echo $unit|sed 's/^c_//'`
fi

field_num=`echo $unit|awk -F. '{print NF}'`
if [ $field_num -eq 2 ];then
	owner=`echo $unit|awk -F. '{print toupper($1)}'`
	up_tabname=`echo $unit|awk -F. '{print toupper($2)}'`
else
	up_tabname=`echo $unit|awk '{print toupper($1)}'`
fi

#setfile=~/.dbtmp/${vimpid}_upd_set.sql  
pipe_in=$dir/.pipe_in.$vimpid
pipe_out=$dir/.pipe_out.$vimpid
sqlplus_pid_file=~/.dbtmp/.sqlplus_pid.$vimpid

if [ ! -p $pipe_in ];then
	>~/.dbtmp/$shortfile.err.4
	exit 4
fi

sqlplus_pid=`cat $sqlplus_pid_file|awk '{print $1}'`
#pid2=`ps -ef|awk -v pid=$sqlplus_pid '{if ($2 == pid) print $2}'`
#if [ "$pid2" != "$sqlplus_pid" ];then
if ! kill -0 $sqlplus_pid 2>/dev/null; then
	>~/.dbtmp/$shortfile.err.4
	exit 4
fi

rotate()
{
	str[1]="-"
	str[2]="\\"
	str[3]="|"
	str[4]="/"
	clear     #Clear screen
	n=1
	while true
	do
	    printf "\033[12;30H $prompt_str...${str[$n]} \n"
		n=`echo $n|awk '{print ($0+1)%5}'`
	    if [ $n -eq 0 ]; then
	         n=1
	    fi
	    sleep 1
	done 
}

prompt_str="Prepare"

rotate &   
bg_pid=$!

if  command -v disown > /dev/null 2>&1 ;then
	disown $bg_pid
fi

#cd $dir

fgf=""

if [ ! -f $dir/$newfile ];then
	> $dir/$newfile
fi

if [ ! -f $dir/$oldfile ];then
	> $dir/$oldfile
fi

>$updatesql_file
CrtSql $dir/$newfile $dir/$oldfile $updatesql_file
sucflag=$?

if [ $sucflag -ne 0 ];then
	kill -9 $bg_pid   > /dev/null 2>&1
	#rm -f $setfile
	rm -f $updatesql_file   
	rm -f $dir/$newfile
	rm -f $dir/$oldfile
	vim -c "set nonu" $browfile
	rm -f $browfile
	>~/.dbtmp/$shortfile.err.11
	exit 11
fi

kill -9 $bg_pid   > /dev/null 2>&1

#No update
if [ ! -s $updatesql_file ];then
	rm -f $updatesql_file   
	#rm -f $dir/col_*.txt
	rm -f $dir/$newfile
	rm -f $dir/$oldfile
	>~/.dbtmp/$shortfile.err.3
	exit 3
fi

rm -f $dir/$newfile
rm -f $dir/$oldfile

prompt_str="Executing SQL"
rotate &   
bg_pid=$!

if  command -v disown > /dev/null 2>&1 ;then
	disown $bg_pid
fi

ReadPipe&
read_pid=$!
(
	echo "SQL_START"
	echo "set timing off;"
	echo "set feedback off;"

	echo "spool $browfile;"
	echo "@$updatesql_file;"
	echo "spool off;"
	#echo "@$setfile;"
	echo "prompt $SQL_END;"
) > $pipe_in

wait $read_pid

kill -9 $bg_pid   > /dev/null 2>&1

if [ -s $browfile ];then
	#vim -u ~/user/zjw/bin/.vimrc.db $browfile
	vim -u NONE -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapView()|call oracle_tui#SetAutocmdView()" $browfile
	grep "^ORA-" $browfile > /dev/null 2>&1
	if [ $? -eq 0 ];then
		retcode=1
	else
		grep "^SP2-" $browfile > /dev/null 2>&1
		if [ $? -eq 0 ];then
			retcode=1
		else
			retcode=0
		fi
	fi
	#retcode=1
else
	retcode=0
fi

rm -f $crttab_file
rm -f $browfile
#rm -f $setfile
rm -f $updatesql_file   

if [ "$retcode" = "0" ];then
    >~/.dbtmp/$shortfile.err.0
fi

exit $retcode
