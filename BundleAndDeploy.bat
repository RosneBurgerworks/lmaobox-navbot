@echo off

node bundle.js
move /Y "Lmaobot.lua" "%localappdata%"

exit
