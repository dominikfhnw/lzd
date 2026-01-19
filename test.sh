#!/bin/bash

DEBUG= FULL= bash lzemb.asm -DINC
#cat lzd/out3.bin >> lzemb
strace -rni ./lzemb > o
#truncate -s -1 o
cmp o astley.txt && echo "OK"

