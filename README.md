# How to Use - VDBench Test
(include fio install, disk 1 status is "offline" and "readonly" is disabled)
1. Right-click `vdbench_2026.bat` then click **Run as administrator**.
2. A message "The VDBench Test has completed successfully" will appear after the test completes.
3. Logs saved in `\VDBench\VDBench50407\Fill25*` and `Fill100*` for 25% and 100% fill rate.
4. Run the data analysis with `Storage0729_v0.4_Array.exe`.

---

# How to Use - ReadWrite Test

## Windows
1. In **This PC** in File Explorer, use **Map network drive** to bind the destination (NAS) drive.
2. Open PowerShell as administrator and enter the command to set the trust policy:
   ```
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
   ```
3. Launch the script: right-click the `.ps1` file and select **Run with PowerShell**.
4. Select destination: the console will list available drives. Enter the number corresponding to your target disk (e.g., your mapped NAS drive).
5. Select source folders:
   - A folder browser will appear. Select the folder you want to use as test data.
   - A prompt will ask "Any other folder need to be executed?". Click **Yes** to add more or **No** to begin testing.
6. Automatic testing:
   - **Write phase:** the tool copies the folder to the destination 5 times.
   - **Read phase:** the tool copies the data back to the local source directory 5 times.
   - **Cleanup:** temporary test folders are deleted automatically after the test.
7. Review results: a CSV named `WriteReadLog_YYYYMMDD_HHmm.csv` will be created in the same folder as the script.

---
### Prerequisites
- Edit `nas_config.txt` file in the same folder as the script with the following content:
  ```
  NAS_IP=192.168.x.x
  SHARE_NAME=your_share
  NAS_USER=your_username
  NAS_PASS=your_password
  ```
## Mac
### Steps
1. Open Terminal and `cd` to the tool path.
2. Strip Windows line endings:
   ```
   sed -i '' 's/\r$//' ./transfer_tool.sh
   ```
3. Make the script executable:
   ```
   chmod +x transfer_tool.sh
   ```
4. Run the script:
   ```
   ./transfer_tool.sh
   ```
5. **Destination selection:** the script will automatically detect mounted NAS volumes in `/Volumes/`. Select the corresponding index number.
6. **Select source folders for write/read test:**
   - Pick your source folder when the dialog appears.
   - Choose **Yes** when asked "Add another folder?" to queue more tests, or **No** to start.
7. Review results: a file named `WriteReadLog_YYYYMMDD_HHmm.csv` will be generated in the script's directory.

> **Notice:** If the NAS is not found in `/Volumes/`, press **Command+K** in Finder, enter `smb://[NAS IP]`, and it will be mounted to `/Volumes/` again.

---

## Linux
### Prerequisites
- Create a `nas_config.txt` file in the same folder as the script with the following content:
  ```
  NAS_IP=192.168.x.x
  SHARE_NAME=your_share
  NAS_USER=your_username
  NAS_PASS=your_password
  ```
- Install `zenity` for the graphical folder picker (optional; falls back to terminal prompt if not available):
  ```
  sudo apt install zenity
  ```

### Steps
1. Open Terminal and `cd` to the tool path.
2. Strip Windows line endings:
   ```
   sed -i 's/\r$//' ./transfer_tool.sh
   ```
3. Make the script executable:
   ```
   chmod +x transfer_tool.sh
   ```
4. Run the script:
   ```
   ./transfer_tool.sh
   ```
   The script will automatically mount the NAS via a kernel-level SMB connection using the credentials in `nas_config.txt`. A `sudo` password prompt will appear for the mount. No manual NAS mounting in the file manager is required.
5. **Select source folders for write/read test:**
   - Pick your source folder in the dialog (or enter the path if `zenity` is not installed).
   - Choose **Yes** when asked "Add another folder?" to queue more tests, or **No** to start.
6. Review results: a file named `WriteReadLog_YYYYMMDD_HHmm.csv` will be generated in the script's directory. The NAS will be unmounted automatically when the test completes.
