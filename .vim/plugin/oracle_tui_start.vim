"==============================================================================
" oracle_tui.vim - A native Vim-based Oracle client for UNIX/Linux
"==============================================================================
"
" Description:  A lightweight Oracle database client inside Vim that rivals
"               GUI tools. Provides spreadsheet-like data editing via SQL*Plus,
"               with transaction enforcement, LOB support, smart autocompletion,
"               and sticky headers. Perfect for SSH/terminal environments.
"
" Maintainer:   zangjianwei <zangjianwei35@gmail.com>
" Repository:   https://github.com/zangjianwei/oracle_tui.vim
" License:      MIT (See LICENSE file for details)
" Version:      1.01
" Last Change:  2026-07-10
"
" Supported Vim: 7.4+ (Vim 8.2 or above is recommended)
" Supported OS:   UNIX/Linux
" Copyright:    Copyright (C) 1999-2005 Charles E. Campbell, Jr. {{{1
"               Permission is hereby granted to use and distribute this code,
"               with or without modifications, provided that this copyright
"               notice is copied with it. Like anything else that's free,
"               Align.vim is provided *as is* and comes with no warranty
"               of any kind, either expressed or implied. By using this
"               plugin, you agree that in no event will the copyright
"               holder be liable for any damages resulting from the use
"               of this software.
"
" Usage:
"   :Connect              - Connect to Oracle using DBUSER/DBPASS env vars
"   :Connect -u           - Force manual username/password prompt
"   F8                    - Execute SQL (selection or current line)
"   F12                   - Commit data changes in modification window
"   See documentation for full keybindings.
"
"==============================================================================
let s:save_cpo = &cpo
set cpo&vim

if exists("loaded_oracle_tui")
	finish
endif
let loaded_oracle_tui = 1

"Disable cursor position restoration.
"set viminfo='0

"The following line is for loading your own crtdb.txt and should be deleted when officially provided.
if getfsize($HOME."/oracle_tui/crtdb.txt") > 0
	let s:mydblist=1
else
	let s:mydblist=0
endif

function! oracle_tui_start#ConnectDB(...)
	"set encoding=utf-8
	"redraw!
	if &enc != "utf-8"
		call oracle_tui#ShowErr("The 'encoding' setting is not UTF-8")
		return
	endif

	"Highlighting (if there is an issue with the terminfo library, syntax highlighting will not work).
	"if &t_Co == 0 || empty(&t_Sf) || empty(&t_Sb)
	"	set t_Co=8
	"	set t_Sf=[3%p1%dm
	"	set t_Sb=[4%p1%dm
	"endif

	let pid=getpid()

	let dbdir=$HOME."/.dbtmp"
	if !isdirectory(dbdir)
		call mkdir(dbdir, 'p')
	endif

	"db_disconnect.sh must be placed here; otherwise, if the database connection fails, the temporary file cannot be deleted.
	autocmd vimLeave * sil execute "! db_disconnect.sh ".getpid()

	let input_user_flag = 0
	if a:0 == 1
		if a:1 != "-u" || a:1 == "-h"
			call oracle_tui#ShowErr('Usage:Connect [-u]')
			return
		else
			let input_user_flag = 1
		endif
	endif

	if exists('s:username') 
		unlet s:username
	endif

	if exists('s:password') 
		unlet s:password
	endif

	if input_user_flag == 1
		let s:username = input('Database username:')
		if s:username == ''
			redraw!
			call oracle_tui#ShowErr('Username is missing')
			return
		endif

		redraw!
		let s:password = inputsecret('Database username:'.s:username."\nDatabase password:")
		if s:password == ''
			redraw!
			call oracle_tui#ShowErr('Password is missing')
			return
		endif
	else
		if $DBUSER == ''
			let s:username = input('Database username:')
			if s:username == ''
				redraw!
				call oracle_tui#ShowErr('Username is missing')
				return 
			endif

			redraw!
			let s:password = inputsecret('Database username:'.s:username."\nDatabase password:")
			if s:password == ''
				redraw!
				call oracle_tui#ShowErr('Password is missing')
				return 
			endif
		else
			if $DBPASS == ''
				let s:username = input('Database username:', $DBUSER)
				if s:username == ''
					redraw!
					call oracle_tui#ShowErr('Username is missing')
					return 
				endif
				
				redraw!
				let s:password = inputsecret('Database username:'.s:username."\nDatabase password:")
				if s:password == ''
					redraw!
					call oracle_tui#ShowErr('Password is missing')
					return 
				endif
			endif
		endif
	endif

	if exists('s:username') && exists('s:password')
		let cmd="db_connect.sh ".pid." ".s:username. " ".s:password
	else
		let cmd="db_connect.sh ".pid
	endif


	"sil execute "! ".cmd
	let output = system(cmd)

	let status = shell_error
	if status != 0
		redraw!
		"echo "Connection failed.!"
		"echo output
		call oracle_tui#ShowErr(output)
		return
	endif

	let w:main_window_flag = 1
	let t:main_tab_flag = 1

	"set paste will make imap mappings ineffective
	set nopaste

	if exists('s:username') && exists('s:password')
		call oracle_tui#SetUsername(s:username)
		call oracle_tui#SetPassword(s:password)
	endif

	setlocal nohlsearch

	"command! -bar -buffer Line call oracle_tui#Line()
	"command! -bar -buffer UnLine call oracle_tui#UnLine()
	"command! -bar -buffer -range Plan <line1>,<line2> call oracle_tui#Plan()
	"command! -bar -buffer GetWord call oracle_tui#GetWord()
	"command! -bar -buffer ShowTab call oracle_tui#ShowTab()
	"command! -bar -buffer DescObj call oracle_tui#DescObj()
	"command! -bar -buffer GrepTab call oracle_tui#GrepTab()
	"command! -bar -buffer IfCommit call oracle_tui#IfCommit()
	"command! -bar -buffer Fsql call oracle_tui#Fsql()
	"command! -bar -buffer -nargs=1 RollCommit call oracle_tui#RollCommit(<f-args>)
	"command! -bar -buffer ListObj call oracle_tui#ListObj()
	"command! -bar -buffer CheckNoCommit call oracle_tui#CheckNoCommit()
	"command! -bar -buffer DBCliHelp call oracle_tui#DBCliHelp()
	"command! -bar -buffer -nargs=* ShowErr call oracle_tui#ShowErr(<f-args>)

	"command! -nargs=? -range Exe <line1>,<line2> call oracle_tui#ExeSql(<f-args>)
	"command! ConvWork call oracle_tui#ConvWork()
	"command! ShowMode call oracle_tui#ShowMode()

	command! -bar -buffer -nargs=*  Tablist  call oracle_tui#Tablist(<f-args>)
	command! -bar -buffer Tabspace call oracle_tui#Tabspace()
	command! -bar -buffer Tabused call oracle_tui#Tabused()
	command! -bar -buffer Nowsql call oracle_tui#Nowsql()
	command! -bar -buffer Seelock call oracle_tui#Seelock()
	command! -bar -buffer -nargs=* Unlock call oracle_tui#Unlock(<f-args>)

	if s:mydblist == 1 
		execute "badd ".$HOME."/oracle_tui/crtdb.txt"
		execute "badd ".$HOME."/oracle_tui/kjdb.txt"
	else
		if exists('s:username') && exists('s:password')
		  	let result = system("db_list_table.sh ".s:username." ".s:password." ".pid)
		else
			let result = system("db_list_table.sh ".pid)
		endif
		execute "badd ".dbdir."/.dbobj.".pid
	endif

	"- Decrease the window width.[ 
	nnoremap <silent> <expr> - exists("t:main_tab_flag") && t:main_tab_flag == 1 ? '<C-W><' : ''
	"_ Increase the window width.
	nnoremap <silent> <expr> = exists("t:main_tab_flag") && t:main_tab_flag == 1 ? '<C-W>>' : ''
	
	"= Decrease the window height.
	nnoremap <silent> <expr> _ exists("t:main_tab_flag") && t:main_tab_flag == 1 ? '<C-W>-' : ''
	"+  Increase the window height.
	nnoremap <silent> <expr> + exists("t:main_tab_flag") && t:main_tab_flag == 1 ? '<C-W>+' : ''
	
	nnoremap <silent> <expr> <C-Up> exists("t:main_tab_flag") && t:main_tab_flag == 1 ? '<C-W>k' : ''
	nnoremap <silent> <expr> <C-Down> exists("t:main_tab_flag") && t:main_tab_flag == 1 ? '<C-W>j' : ''
	nnoremap <silent> <expr> <C-Left> exists("t:main_tab_flag") && t:main_tab_flag == 1 ? '<C-W>h' : ''
	nnoremap <silent> <expr> <C-Right> exists("t:main_tab_flag") && t:main_tab_flag == 1 ? '<C-W>l' : ''
	
	"map J 10j
	"map K 10k
	
	"<F1> show help
	"nmap <silent> OP :Help<CR>
	"nnoremap <expr>  OP expand("%") == "backlist" ? ':HelpBackList<CR>' : ':DBCliHelp<CR>'
	nnoremap <silent> <expr> OP exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#DBCliHelp()<CR>" : ''
	
	"<F2> Roll back the transaction.
	nnoremap <silent> <expr> OQ exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#RollCommit(0)<CR>" : ''
	
	"<F6> Commit the transaction.
	nnoremap <silent> <expr> [17~ exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#RollCommit(1)<CR>" : ''
	
	"<F3> View locks.
	"nnoremap <silent>  OR :Seelock<CR>
	
	"<F4> Check for uncommitted transactions.
	nnoremap <silent> <expr> OS exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#IfCommit()<CR>" : ''
	
	"<F5> View the execution plan.
	noremap <silent> <expr> [15~ exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#Plan()<CR>" : ''
	
	"<F7>
	nnoremap <silent> <expr> [18~ exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#ListObj()<CR>" : ''
	
	"<F8> Execute SQL.
	"map <silent> [19~ :Exe<CR>
	nnoremap <silent> <expr> [19~ exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#ExeSql('n')<CR>" : ''
	vnoremap <silent> <expr> [19~ exists("w:main_window_flag") && w:main_window_flag == 1 ? ":<C-U>call oracle_tui#ExeSql('v')<CR>" : ''
	
	"<F9> Display the table definitions in crtdb.txt.
	nnoremap <silent> <expr> [20~ exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#ShowTab()<CR>" : ''
	
	"<F10> Display the statements for creating database objects.
	nnoremap <silent> <expr> [21~ exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#DescObj()<CR>" : ''

	"<F11> View tablespaces.
	"nnoremap <silent>  [23~ :Tabspace<CR>

	"<F12> View currently running SQL.
	"nnoremap <silent>  [24~ :Nowsql<CR>
	
	"Capture the word under the current cursor position, insert it at the cursor position in the previous window, and close the current window.
	"map  :call GetWord()a
	"nnoremap <silent>  :GetWord<CR>
	
	"Search for the table name corresponding to the string under the cursor.
	"nnoremap <silent>  <CR> :GrepTab<CR>
	inoremap <silent> <expr> <C-K> exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#GrepTab()<CR>" : ''
	nnoremap <silent> <expr> <C-K> exists("w:main_window_flag") && w:main_window_flag == 1 ? ":call oracle_tui#GrepTab()<CR>" : ''

	"cnoremap  <expr> q <SID>HandleQuit()
	"cnoremap  <expr> x <SID>HandleQuit_x()

	cnoremap <silent>  <expr> <CR> oracle_tui#CheckMainCommand()

	"let mapleader = ","
	"nnoremap <silent> <Leader>s :ShowMode<CR>
	
	"autocmd VimLeavePre * call oracle_tui#CheckNoCommit()
	"autocmd vimLeave * sil execute "! db_disconnect.sh ".getpid()
	"autocmd BufReadPost *
	"			\ if line("'\"") > 0 && line("'\"") <= line("$") |
	"			\   exe "normal! g`\"" |
	"			\ endif

	"let s:last_win_nr = 1
	"augroup RememberLastWindow
	"	autocmd!
	"	autocmd WinEnter * let s:last_win_nr = winnr()
	"augroup END

	"cnoreabbrev <silent> <expr> only (getcmdtype()==':') ? 'sil only<bar>sil tabonly<bar>' : 'only'
	redraw!
	call oracle_tui#ShowErr("Welcome to ORACLE TUI client. Press F1 for help")
endfun

command! -buffer -nargs=? Connect call oracle_tui_start#ConnectDB(<f-args>)
"command! VerSplit call oracle_tui#VerSplit()
"command! -range Sum <line1>,<line2> call oracle_tui#Sum()

let &cpo = s:save_cpo
