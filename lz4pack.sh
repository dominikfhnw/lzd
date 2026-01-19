#!/bin/sh
# exepacker for Linux/x86 by u/dominikr86
# No dependencies. memfd_create. LZ4. 156 bytes.
# Packed file can be 64b ELF, script, or anything else your system can execve
# LZ4 originally by trixter
set -eu
OUT="$1.packed"
cp -p "$1" "$OUT"
printf '\177ELFNBBBBBBBBDP=\2B\6B\31DP=\31DP=RBBB\213\\$\bfUdNQ\251\40BNBCHZAO\311j]XCH\207\337\262\3F\260TCHY\227P\276\234DP=KKZNIMG\302TJRJ\35BBBIW9\336s$fK\222$OJ\rBBBVG\376)\326\203SRIW^\353\330<O\221u\7MNS<\377t\371\303fUfN[]]G\342\215tMR\277B\20BBQG\341CH\314'|tr BCDGHIJKMNORSTUWZ '\0\315\220\211\200\363\350\255\254\1\17\4\301\300\270\244\223'>"$OUT"
lz4 -cl12 "$1" >> "$OUT"
ls -l "$1" "$OUT"
