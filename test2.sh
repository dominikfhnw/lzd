#!/bin/bash

#DEBUG= FULL=1 bash lzemb.asm -Lw+ -l nasm.list -DINC="\"lzd/out4.bin\""
DEBUG= FULL= bash lzemb.asm -DINC="\"lzd/out4.bin\""
strace -rni ./lzemb > o
cmp o astley.txt && echo "OK"

