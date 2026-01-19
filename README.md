# Small decompressors

Just a dump of my compression/decompression stuff:
* an i386 port of Trixter's LZ4_8088 (59b)
* i386 port of unzx0 (82b)
* small exepacker for Linux
* a bunch of very small decompressors for i386:
  * 9b RLE
  * 18b LZ77 
  * 31b LZSS w/varint encoding
  * some experimental matching compressors (protototypical, written in perl, no speed optimizations whatsoever)

 
* `lzemb.asm` serves as a testbed for the different algorithms
* `lzd4.asm` is the 31b LZSS decompressor
* `lzd*.asm` are all the other LZ-type decompressors. All of them have (too many) ifdefs to tune the size
  * Hint: `grep VERSION: *` to get short descriptions for what the files do
* `lz4pack.sh` is a ready-to-use lz4 based exepacker
* `rle.asm` contains RLE decompressors from 9..15b
