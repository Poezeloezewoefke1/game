@echo off
REM Runs the server without Docker. Needs Java 21+ (Java 25 for Minecraft 26.x).
REM 1. Download a Paper jar from https://papermc.io/downloads/paper and save it here as paper.jar
REM 2. Put FunCraftGames.jar in ..\plugins (or in server\plugins)
cd /d "%~dp0"
if not exist paper.jar (
  echo paper.jar not found. Download it from https://papermc.io/downloads/paper and put it in this folder.
  pause
  exit /b 1
)
if not exist plugins mkdir plugins
copy /Y ..\plugins\*.jar plugins\ >nul 2>&1
echo eula=true> eula.txt
if not exist server.properties (
  (
    echo motd=FunCraft - BedWars, SkyWars, Build Battle and more!
    echo gamemode=adventure
    echo spawn-protection=0
    echo allow-nether=false
    echo allow-flight=true
    echo level-type=minecraft\:flat
    echo generate-structures=false
    echo max-players=30
  ) > server.properties
)
java -Xms2G -Xmx4G -jar paper.jar --nogui
pause
