## Windows
1. Map network drive
2. Right Click transfer_tool.ps1 select "Run with Powershell"
3. select source folder for write/read test (multi-paths supported)
4. Select Destination Disk (Input Number) ex: 0 for "[0] Y: (Y:\)" then enter to start testing
5. after testing completed, there is a datalog (.csv) in the same folder of test tool 
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


