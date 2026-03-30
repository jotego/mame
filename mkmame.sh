#!/bin/bash
# call mkmame.sh REGENIE=1
# after adding a new game
unset TARGET
S=src/mame
nice make TARGET=mame \
SOURCES=$S/konami/twin16.cpp,$S/namco/namcos1.cpp,$S/capcom/gunsmoke.cpp,$S/dataeast/karnov.cpp,\
$S/capcom/lwings.cpp,$S/konami/thunderx.cpp,$S/capcom/higemaru.cpp,$S/sega,$S/konami/tmnt.cpp,$S/konami/tmnt2.cpp,\
$S/konami/gradius3.cpp,$S/konami/xmen.cpp,$S/konami/aliens.cpp,$S/konami/rungun.cpp,$S/konami/piratesh.cpp,\
$S/toaplan/twincobr.cpp,$S/technos/wwfsstar.cpp,$S/tecmo/tehkanwc.cpp,$S/taito/flstory.cpp,$S/konami/yiear.cpp,\
$S/tecmo/gaiden.cpp,$S/taito/nycaptor.cpp,$S/sega/segaorun.cpp,$S/namco/namcos86.cpp,$S/namco/pacland.cpp,\
$S/namco/baraduke.cpp,$S/technos/renegade.cpp,$S/sega/system1.cpp,$S/seta/downtown.cpp,$S/capcom/gng.cpp,$S/capcom/cps3.cpp \
-j 10 $*
