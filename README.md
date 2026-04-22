# How to Use - VDBench Test (include fio install, disk 1 check dsk 1 status is offline and readonly is disable)
1. Right Click vdbench_2026.bat then click [run as administrator]
2. It will popup a message with "The VDBench Test has completed successfully" after test completed.
3. log saved in \VDBench\VDvench50407\Fill25* and Fill100* for 25% and 100% fill rate.
4. Run the data analyzing with "Storage0729_v0.4_Array.exe"

# How to Use - ReadWrite Test

## Windows
1. Launch the Script: Right-click the .ps1 file and select Run with PowerShell.
2. Select Destination: The console will list available drives. Enter the number corresponding to your target disk (e.g., your mapped NAS drive).
3. Select Source Folders:
-A folder browser will appear. Select the folder you want to use as test data.
-A prompt will ask "Any other folder need to be executed?". Click Yes to add more or No to begin testing.
4. Automatic Testing:
-Write Phase: The tool copies the folder to the destination 5 times.
-Read Phase: The tool copies the data back to the local source directory 5 times.
-Cleanup: Temporary test folders are deleted automatically after the test.
5. Review Results: Once finished, a CSV named WriteReadLog_YYYYMMDD_HHmm.csv will be created in the same folder as the script.

## Mac
1. Open terminal and cd to tool path
2. sed -i '' 's/\r$//' ./transfer_tool.sh
3. chmod +x transfer_tool.sh
4. ./transfer_tool.sh to start
5.  Destination Selection:
    The script will detect mounted volumes (macOS) or SMB shares (Linux). Select the corresponding index number.
6.  select sources folder for write/read test
    - Pick your source folder when the dialog appears.
    - Choose Yes when asked "Add another folder?" to queue more tests, or No to start.
7. Review Results: A file named WriteReadLog_YYYYMMDD_HHmm.csv will be generated in the script's directory.
   
## Linux
1. Open terminal and cd to tool path
2. sed -i 's/\r$//' ./transfer_tool.sh
3. chmod +x transfer_tool.sh
4.  ./transfer_tool.sh to start test
5.  Destination Selection:
    The script will detect mounted volumes (macOS) or SMB shares (Linux). Select the corresponding index number.
6.  select sources folder for write/read test
    - Pick your source folder when the dialog appears.
    - Choose Yes when asked "Add another folder?" to queue more tests, or No to start.
7. Review Results: A file named WriteReadLog_YYYYMMDD_HHmm.csv will be generated in the script's directory.


