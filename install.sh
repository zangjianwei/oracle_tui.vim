if [ -d ~/oracle_tui ];then
	echo "The directory ~/oracle_tui already exists. Installation fail"
	exit 1
fi

tar cvf ~/oracle_tui.tar .vim oracle_tui
cd ~
tar xvf oracle_tui.tar
if [ ! -d oracle_tui ];then
	echo "install error!"
	exit 1
else
	cd oracle_tui
	chmod u+x *.sh
fi
rm -f oracle_tui.tar
echo "Installation successful. Please complete the remaining configuration steps."
