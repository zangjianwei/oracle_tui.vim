# Introduction  
A fully-featured, native UNIX/Linux Vim Oracle client that rivals the experience of GUI applications. Powered by SQL*Plus for SQL execution, it offers spreadsheet-like data manipulation in tabular format—edit data as easily as in Excel, with automatic alignment upon modification. Additional capabilities include execution plan analysis, table structure viewing, DDL extraction for database objects, transaction control, LOB field editing, smart autocompletion (with mid-string matching support), and sticky column headers for seamless navigation.
![Screenshot](https://raw.githubusercontent.com/zangjianwei/oracle_tui.vim/master/images/oracle_tui_en.gif)
# Features
  - Rapid Connection: Supports auto-login via environment variables; connect to your database with a single command.
  - Spreadsheet-like Editing: Edit data in Vim just like Excel (SELECT ... FOR UPDATE).
    - Hides ROWID to prevent accidental modification.
    - Supports file-based editing for CLOB/BLOB fields.
    - Auto-alignment: Right-aligns numbers and formats dates.
  - Keyboard-Centric Workflow:
    - F8: Execute SQL
    - F12: Commit data changes
    - F2 / F6: Rollback / Commit transaction
  - Safety Mechanisms: Forces an error and intercepts exit if there are uncommitted transactions when quitting Vim.
  - Smart Completion: Supports table name auto-completion (including non-prefix strings).
  - Multi-Statement Support: Supports PL/SQL block execution with separated result displays.
  - Three Distinct Window Modes:
    - SQL Execution Window: The default window upon entering Vim.
    - Query Window: Opens when executing a single SELECT statement.
      - Column headers display fully, overcoming sqlplus truncation limits.
      - Fixed header row.
    - Data Modification Window: Opens when executing SELECT ... FOR UPDATE.
      - Spreadsheet-style editing with fixed headers.
      - Auto-alignment during insert/delete/modify/replace operations (numbers are right-aligned).
      - Intelligently recognizes trailing spaces in VARCHAR2 fields.
      - Generates temporary files for CLOB/BLOB fields; press Ctrl+A on the field to open an editor window.
      - Replacement operations preserve headers and CLOB/BLOB filenames.
      - Auto-prompts input format when the cursor lands on DATE or TIMESTAMP fields.
      - Auto-prompts Ctrl+A usage when the cursor lands on CLOB/BLOB fields.
# Installation
## Dependencies
  - Linux/Unix Environment
  - Oracle Instant Client (must have sqlplus configured)
  - Vim 7.4+(Vim 8.2 or above is recommended. Vim 7.4 has some functional limitations.)
## Steps
1. Place oracle_tui.tar in the installation user's $HOME directory.
2. Extract the file: tar xvf oracle_tui.tar.
3. Modify the profile by adding the following environment variables.  
       export PATH=$PATH:$HOME/oracle_tui:.
4. Check whether your NLS_LANG and LC_CTYPE environment variables are set to UTF-8. If not, modify the profile by adding the following environment variables(Please select your [language]_[territory] setting)  
   export TUI_NLS_LANG="AMERICAN_AMERICA.AL32UTF8"  
   export TUI_LC_CTYPE=en_US.UTF-8  
6. Set the file encoding to UTF-8.  
    Add the following settings to ~/.vimrc or your own .vimrc file:   
    set encoding=utf-8  
    set fileencodings=ucs-bom,utf-8,gb18030,gbk,gb2312,cp936,latin1  
    set termencoding=utf-8  
7. Modify the profile to add the DBUSER and DBPASS environment variables (optional):  
    export DBUSER=user  
    export DBPASS=pass  
      
    If these variables are set, the tool will start using them automatically. If not, you will be prompted to enter the username and password manually.  
8. Set an alias in the user's profile (optional):  
    alias vidb='vim -c "call oracle_tui_start#ConnectDB()"'  
    Or  
    alias vidb='vim -u /path/to/your/.vimrc -c "call oracle_tui_start#ConnectDB()"'  

    If this alias is set, typing vidb will automatically connect to the database.  
9. Source the profile to apply the changes: (e.g., . ~/.profile).

# Startup Steps
1. Set the terminal encoding to UTF-8.
2. Method 1:  
   Open vim and enter :Connect. If the DBUSER and DBPASS environment variables are set, the tool will log in using those credentials. Otherwise, you will be prompted to enter the username and password. Alternatively, you can force the login prompt by entering :Connect -u to manually enter the username and password.
3. Method 2:  
   Use the alias for auto-start by typing vidb <filename>.  
# Keybindings
## SQL Execution Window
| Key           | Function                                                                     |
|:-------------|:------------------------------------------------------------------------------|
| F1            | Show Help                                                                    |
| F8            | Execute SQL (Executes selection in Visual mode, current line in Normal mode) |
| Ctrl+C        | Interrupt current operation                                                  |
| F2 / F6       | Rollback / Commit Transaction                                                |
| F4            | Check for uncommitted transactions                                           |
| F5            | View SQL Execution Plan                                                      |
| F7            | List Database Objects<br>F9 and F10 work in the popup window                 |
| F9            | Show table structure description for the table under the cursor              |
| F10           | Show DDL statement for the object under the cursor                           |
| - / =         | Decrease / Increase window width                                             |
| Shift + - / = | Decrease / Increase window height                                            |
| Ctrl+↑        | Jump to the upper window                                                     |
| Ctrl+↓        | Jump to the lower window                                                     |
| Ctrl+→        | Jump to the right window                                                     |
| Ctrl+←        | Jump to the left window                                                      |
| Ctrl+n        | Object name auto-complete (Prefix only, Insert mode)                         |
| Ctrl+k        | table name auto-complete (Suport not prefix,Insert or normal mode)<br>F9 and F10 work in the popup window|
| gt            | Switch between tabs                                                          |
| :Tablist      | Show table name and comment                                                  |
| :Seelock      | View locks                                                                   |
| :Unlock       | Unlock                                                                       |
| :Tabused      | View table space usage                                                       |
| :Tabspace     | View tablespace usage                                                        |
| :Nowsql       | View currently running SQL                                                   |  
## Query Window  
| Key     | Function                                      |
|:---------|:-----------------------------------------------|
| [ / ]   | Move Left / Right                             |
| { / }   | Fast Move Left / Right                        |
| j / k   | Move Down / Up                                |
| J / K   | Fast Move Down / Up                           |
| /       | Search                                        |
| -       | Decrease window width                         |
| +       | Increase window width                         |
| Ctrl+→  | Jump to right window                          |
| Ctrl+←  | Jump to left window                           |
| Ctrl+↑  | Sort by current column asc                    |
| Ctrl+↓  | Sort by current column desc                   |
| F3      | Freeze / Unfreeze Header Row                  |
| wv      | Split window vertically                       |
| TAB     | Jump to next field                            |
| Ctrl+t  | Jump to previous field                        |
| F11     | Show current SQL statement                    |
| Crtsql  | Generate SQL based on current data file       |
| Ctrl+X  | shorten column length                         |
| \x      | Cut the current column                        |
| \p      | Paste the cut column after the current column |
| Ctrl+\  | Sum numbers in the selected column            |
| F1      | Show Help                                     |
## Data Modification Window
| Key    | Function                                                      |
|:--------|:---------------------------------------------------------------|
| [ / ]  | Move Left / Right                                             |
| { / }  | Fast Move Left / Right                                        |
| j / k  | Move Down / Up                                                |
| J / K  | Fast Move Down / Up                                           |
| /      | Search                                                        |
| F12    | Submit table data modifications (does not commit transaction) |
| o      | Add new row below current line (Normal mode)                  |
| O      | Add new row above current line (Normal mode)                  |
| Ctrl+→ | Jump to right window                                          |
| Ctrl+← | Jump to left window                                           |
| Ctrl+T | Jump to previous column (Insert or Normal mode)               |
| TAB    | Jump to next column (Insert or Normal mode)                   |
| Ctrl+A | Open a window to edit the current column (for CLOB/BLOB)      |
| F3     | Freeze / Unfreeze Header Row                                  |
| wv     | Split window vertically                                       |
| Ctrl+n | Toggle display of null characters                             |
| Ctrl+@ | Toggle display of diff highlighting                           |
| -      | Decrease current window width                                 |
| +      | Increase current window width                                 |
| F1     | Show Help                                                     |
# ⚠️ Limitations
  - Modifications for fields containing LONG or LONG RAW types are not supported in Data Modification Window.
  - Vim 9 on AIX has a bug processing list; therefore, Vim 9 cannot be used on AIX.

## Author
**zangjianwei**

- GitHub: [@zangjianwei](https://github.com/zangjianwei)
- Email: [zangjianwei35@gmail.com](mailto:zangjianwei35@gmail.com)
