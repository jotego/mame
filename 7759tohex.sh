#!/bin/bash
OUTPUT=$(basename $1 .log).hex

grep "udp7759: CPU writes " $1 | sed "s/\tudp7759: CPU writes //" > $OUTPUT || exit $?
echo $OUTPUT produced

