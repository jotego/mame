#!/bin/bash
# Just run any system 16 game and it will output the relevant files
# once per frame
if [ $# != 2 ]; then
    echo "Call it with the system name and the scene number"
fi
TARGET=~/git/jts16/ver/game/$1
mkdir -p $TARGET
for i in char obj pal scr; do
    cp -v $i.bin $TARGET/$i$2.bin
done

MAMESNAP=~/.mame/snap/$1

if [ ! -d $MAMESNAP ]; then
    echo Warning: no MAME snapshot for $1
else
    # copy latest snap file from MAME
    LATEST=$(ls $MAMESNAP -t | head -n 1)
    cp -v $MAMESNAP/$LATEST $TARGET/$2.png
fi