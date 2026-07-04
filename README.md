                                                Vim Oracle TUI Client 
    A lightweight, terminal-based UNIX/LINUX Oracle database client built for Vim. It interacts with sqlplus via pipes to provide a GUI-like data editing experience right in your terminal.
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
  - Vim 7.4+
## Steps
1. Place oracle_tui.tar in the installation user's $HOME directory.
2. Extract the file: tar xvf oracle_tui.tar.
3. Modify the profile by adding the following environment variables.  
       export PATH=$PATH:$HOME/oracle_tui:.
4. Check whether your NLS_LANG and LC_CTYPE environment variables are set to UTF-8. If not, modify the profile by adding the following environment variables  
   export TUI_NLS_LANG="SIMPLIFIED CHINESE_CHINA.AL32UTF8"
   export TUI_LC_CTYPE=zh_CN.UTF-8
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
9. Source the profile to apply the changes: (e.g., source ~/.bashrc).

# Startup Steps
1. Set the terminal encoding to UTF-8.
2. Method 1:  
   Open vim and enter :Connect. If the DBUSER and DBPASS environment variables are set, the tool will log in using those credentials. Otherwise, you will be prompted to enter the username and password. Alternatively, you can force the login prompt by entering :Connect -u to manually enter the username and password.
4. Method 2:  
   Use the alias for auto-start by typing vidb <filename>.
