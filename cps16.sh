#!/bin/bash
# Just run any system 16 game and it will output the relevant files
# once per frame
if [ $# != 2 ]; then
    echo "Call it with the system name and the scene number"
fi
TARGET=~/git/jts16/ver/game/$1
mkdir -p $TARGET
for i in char obj pal scr; do
    cp -v $i.bin ~/git/jts16/ver/game/$i$2.bin
done