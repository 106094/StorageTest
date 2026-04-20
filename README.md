## Windows
1. Map network drive
2. Right Click transfer_tool.ps1 select "Run with Powershell"
3. select source folder for write/read test
## Mac
1. Open terminal and cd to tool path
2. sed -i '' 's/\r$//' ./transfer_tool.sh
3. chmod +x ./transfer_tool.sh
## Linux
1. Open terminal and cd to tool path
2. sed -i 's/\r$//' ./transfer_tool.sh
3. chmod +x ./transfer_tool.sh


