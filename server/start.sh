#!/usr/bin/env bash
# Runs the server without Docker. Needs Java 21+ (Java 25 for Minecraft 26.x).
# 1. Download a Paper jar from https://papermc.io/downloads/paper and save it here as paper.jar
# 2. Put FunCraftGames.jar in ../plugins (or in server/plugins)
cd "$(dirname "$0")"
if [ ! -f paper.jar ]; then
  echo "paper.jar not found. Download it from https://papermc.io/downloads/paper and put it in $(pwd)"
  exit 1
fi
mkdir -p plugins
cp -f ../plugins/*.jar plugins/ 2>/dev/null
echo "eula=true" > eula.txt
if [ ! -f server.properties ]; then
  cat > server.properties <<PROPS
motd=§6§lFunCraft §7- §eBedWars, SkyWars, Build Battle & more!
gamemode=adventure
spawn-protection=0
allow-nether=false
allow-flight=true
level-type=minecraft\:flat
generate-structures=false
max-players=30
PROPS
fi
exec java -Xms2G -Xmx4G -jar paper.jar --nogui
