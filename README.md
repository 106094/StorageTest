## Windows
🛠️ How to Use
1. Launch the Script: Right-click the .ps1 file and select Run with PowerShell.
2. Select Source Folders:
-A folder browser will appear. Select the folder you want to use as test data.
-A prompt will ask "Any other folder need to be executed?". Click Yes to add more or No to begin testing.
3. Select Destination: The console will list available drives. Enter the number corresponding to your target disk (e.g., your mapped NAS drive).
4. Automatic Testing:
-Write Phase: The tool copies the folder to the destination 5 times.
-Read Phase: The tool copies the data back to the local source directory 5 times.
-Cleanup: Temporary test folders are deleted automatically after the test.
5. Review Results: Once finished, a CSV named WriteReadLog_YYYYMMDD_HHmm.csv will be created in the same folder as the script.
📊 CSV Log Format
- The log is structured for easy import into Excel:
- Source	   Metric	        Result
- FolderName	time (Write 1)	12.45 s
- FolderName	speed (Write 1)	105.2 MB/s
- FolderName	time (Read 1)	10.12 s
- ...	...	...
## Mac
1. Open terminal and cd to tool path
2. sed -i '' 's/\r$//' ./transfer_tool.sh
3. chmod +x ./transfer_tool.sh
4. ./transfer_tool.sh to start
5. select sources folder for write/read test
6. after testing completed, there is a datalog (.csv) in the same folder of test tool 
## Linux
1. Open terminal and cd to tool path
2. sed -i 's/\r$//' ./transfer_tool.sh
3. chmod +x ./transfer_tool.sh
4.  ./transfer_tool.sh to start test
5.  select sources folder for write/read test
6.  after testing completed, there is a datalog (.csv) in the same folder of test tool 


