if [ -d ~/oracle_tui ];then
	echo "已经存在~/oracle_tui目录，安装失败!"
	exit 1
fi

tar cvf ~/oracle_tui.tar .vim oracle_tui
cd ~
tar xvf oracle_tui.tar
if [ ! -d oracle_tui ];then
	echo "安装错误!"
	exit 1
else
	cd oracle_tui
	chmod u+x *.sh
fi
rm -f oracle_tui.tar

echo "安装成功,请完成后续的配置"
