# Lmaobox Navbot
A lua script that allows you to navigate through the maps using pathfinding

The original code was created by Inx00

## How to install
### Requirements
* [Node.JS](https://nodejs.org/) stable version

### Usage
1. Download the latest source code from [Releases](https://github.com/RosneBurgerworks/lmaobox-navbot/releases)
2. Unzip it anywhere you want 
3. Open the command prompt in the unzipped folder and run `npm install luabundle`
4. Run `Bundle.bat`, once it creates file named `bundle.js` and finishes, run `BundleAndDeploy.bat`
5. Start TF2 and inject lmaobox, then open console (backquote key) and type `map X`. X replacing map you want to use (Currently supported: PL, CTF)
6. Go to lua tab in lmaobox menu and load `Lmaobot.lua`, if you are comfortable with everything you can queue for a match.

### Navigation Meshes
* If you don't have any navigation meshes, run `nav_generate` after step 5. This will heavily lag your game, when it's done it should make you rejoin the map.
* If your pc can't handle `nav_generate` or you don't want to do it for each map, download the [navigation meshes](https://github.com/RosneBurgerworks/rosnebot-database/tree/master/nav%20meshes) and put them in ``tf/maps`` folder

For any other issues or questions, join our [discord server](https://dsc.gg/rosnehook)
