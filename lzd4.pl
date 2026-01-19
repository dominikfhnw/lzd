#!/usr/bin/perl
# VERSION: flag bit to differentiate between lit/match. Paired with lzd3c.asm
# vv: first version to get get actually tested
# vv: first encoding is 840b. matchselection broken
# vv: now 951, great
# vv: 885, ok...
# vv: 607, now that's some progress. still underwhelming, > 506
# vv: 576 with MINLEN implemented again
# vv: 548, not sure what exactly I did....
# vv: 525 with minlen3
# vv: 513, next PARSE instead of just saying "uhoh"
# vv: 512, minlen takes VAROFFSET16 into account
# vv: some more cleanup
# should be 516b for astley.txt with forward parsing
# FILE		DATA	EXE	TOTAL
# astley.txt	1730	 0	1730
# astley.lzd18	1041	18	1059
# astley.lzd1	 752	21	 773
# astley.lzd2	 612	27	 639
# astley.lzd3	 512	28	 540
# astley.lzd4	 511	31	 542
# astley.lz4	 506	59	 565
# astley.xz0	 391	82	 473
# astley.gz	 368
#
# LaRRLa
# Labbba
# litlen:	98
# matchlen:	255/349
# matchoff:	1004

# lzd.asm:
# OFFSET16, everything else off
# lzd3.pl:
# NOZERO, everything else off
# turn on ALLOWZEROLIT in lzd.asm, then turn off NOZERO in lzd3.pl

# varint sizes:
# 1b: n <=      63	( 6b)
# 2b: n <=    8191	(13b)
# 3b: n <= 1048575	(20b)
#

eval 'exec perl $0 "$@"'
if 0; # ^ Run only under a shell

use v5.12;
use warnings;
use warnings FATAL => qw(pack);
use Data::Dumper;
use Carp;
use POSIX qw( log2 floor ceil );
#$Data::Dumper::Sortkeys = 1;

our $FILE		= "out4.bin";
our $SHOWSKIP		= 0;

our $SEARCH0DEBUG	= 0;
our $SEARCHDEBUG	= 0;
our $PARSEDEBUG		= 0;
our $VALDEBUG		= 0;

our $WINDOW;
our $MATCHLEN;
our $PACK;

our $LITTYPE		= 1;
our $MATCHTYPE		= 0;

# COMPRESSION TUNING
# matchlen==0 means EOF in LZ77 mode
our $MATCHLENOFF	= 0;
our $LITOFF		= 0;
our $MINLEN		= 3; # in code
our $OUTMINLEN		= 0; # in the decompressor
our $OUTMINOFF		= 0; # in the decompressor

our $NOZERO		= 0; # force nonzero literal between matches. doesn't help usually
our $RLE		= 0;
our $ONLYRLE		= 0;
our $VAROFFSET16	= 1; # variable 8/16bit offset
our $VARIANT		= 1;
# /COMPRESSION TUNING

# WINDOW/MATCH SETTINGS
if(0){
	$WINDOW		= 255;
	$MATCHLEN	= 255 -	$MATCHLENOFF;
	$PACK		= "CC";
}elsif(0){
	$WINDOW		= 65535;
	$MATCHLEN	= 65535 - $MATCHLENOFF;
	$PACK		= "SS";
}else{
	$WINDOW		= 16383;
	#$WINDOW		= 32767;
	#$WINDOW		= 65535;
	$WINDOW		= 2**20;
	#$WINDOW		= 1005; # XXX
	$MATCHLEN	= 255 - $MATCHLENOFF + $OUTMINLEN;
	#$MATCHLEN	= 127 - $MATCHLENOFF + $OUTMINLEN;
	$PACK		= "CS";
}
# /WINDOW/MATCH SETTINGS

if(defined($ENV{RLE})){
	$RLE = !!$ENV{RLE};
	say "RLE defined: $ENV{RLE} $RLE";
}


# offsets from 0..1023:
# first byte directly encodes 6 bits,
# if 2 bits > 0 then load another byte
# test al, 0xc0


# set boolean constant DEBUG according to environment variable DEBUG
BEGIN {
	my $d = !!$ENV{DEBUG};
	*DEBUG = sub(){ $d };
}
sub dbg {
	printf @_ if DEBUG;
}


#open(my $in, '< :raw', 'genesis') or die "error opening file: $!";
#open(my $in, '<', 'genesis') or die "error opening file: $!";
#binmode $in;
#my $contents = do { local $/; <$in> || die "read failed: $!" };
my $contents = do { local $/; <> || die "read failed: $!" };

sub quot {
	my $q = shift;
	#$q =~ s/\n/\\n/g;
	#$q =~ s/ /\\40/g;
	#$q =~ s/([^a-zA-Z0-9 ])/"\e[33m\\".sprintf("%o",ord($1))."\e[m"/ge;
	#$q =~ s/([^-.,;a-zA-Z0-9 ])/"\\".sprintf("%o",ord($1))/ge;
	$q =~ s/([^ -~])/"\\".sprintf("%o",ord($1))/ge;
	return $q;
}

sub quot2 {
	my $q = shift;
	$q =~ s/\n/\\n/g;
	return $q;
}

sub quotm {
	my $MAX = 170;
	my $q = shift;
	$q = quot($q);
	#$q =~ s/([^a-zA-Z0-9 ])/"\\".sprintf("%o",ord($1))/ge;
	if(length($q) > $MAX){
		$q = substr($q,0,$MAX-3)."..."
	}
	return $q;
}

sub search {
	my $ipos = shift;
	my $before0 = shift;
	# XXX OFFSET: current char is already written when we process the match
	my $before = substr($before0,-$WINDOW+1);
	my $after = shift;
	my $blen = length($before);
	my $pos = 0;
	my $len = 0;
	my $netlen = 0;

	printf "S %ipos before:{%s} after:{%s}\n",$ipos,quotm($before),quotm($after) if $SEARCH0DEBUG;
	SEARCH: for my $nlen (1..length($after)){
		my $needle = substr($after,0,$nlen);

		my $in = rindex($before,$needle);
		my $relp = abs($in - $blen);
		my $lastp = $relp - $nlen;
		if($in >= 0){
			printf "match %4d %3d %3d \"%s\"\n",$relp,$nlen,$lastp,quotm($needle) if $SEARCH0DEBUG;
			if($RLE && $lastp == 0){
				say "check rle" if $SEARCH0DEBUG;
				my $max = ($MATCHLEN / $nlen)+1; # XXX 1?
				my $rle = 1;
				for my $i(2..$max){
					my $n2 = $needle x $i;
					if(substr($after,0,$nlen*$i) eq $n2){
						say "YEAH RLE $i" if $SEARCH0DEBUG;
					}
					else {
						say "rle done $i" if $SEARCH0DEBUG;
						$rle = --$i;
						last;
					}
				}
				say "RLE $rle" if $SEARCH0DEBUG;
				#if(!$RLE){
				#	$rle = 1; # XXX
				#}
				if($nlen * $rle > $len){
					$pos = $in;
					$len = $nlen * $rle;
					printf "matc2 %4d %3d %3d \"%s\"\n",$relp,$len,$lastp,quotm($needle) if $SEARCH0DEBUG;
				}
			}
			else {
				# XXX first match selection
				my $newnet = 0;
				$newnet = $nlen - matchlen($relp,$nlen);
				$newnet = 0 if $newnet < 0;
				# this one seems the best, not sure why tho
				#if(!$ONLYRLE && $nlen > $len && $newnet > $netlen){
				if(!$ONLYRLE && $nlen > $len){
				#if(!$ONLYRLE && $newnet > $netlen){
					$pos = $in;
					$len = $nlen;
					$netlen = $newnet;
					printf "matc3 %4d %3d %3d \"%s\"\n",$relp,$len,$lastp,quotm($needle) if $SEARCH0DEBUG;
				}
			}
		}
		else{
			printf "last  %4d %3d %3d\n",$relp,$nlen,$len if $SEARCH0DEBUG;
			last
		}
	}

	my $pos2 = 0;
	if($len > 0){
		$pos2 = abs($pos - $blen);
	}
	say "" if $SEARCH0DEBUG;
	return ($len,$pos2,$pos);
}

# SEARCH MATCHES
my @first;
my $length = length($contents)-1;
#for(my $pos = 0;$pos < length($contents); $pos++){
for(my $pos = $length; $pos >= 0; $pos--){
#for(0..50){
	my $posoff = 0;
	my $before = substr($contents,0,$pos+$posoff);	
	# XXX OFFSET
	my $after = substr($contents,$pos+$posoff,$MATCHLEN);	
	#my $char = substr($contents,$pos,1);
	##say "B ",quot($before)," C ",quot($char)," A ",quot($after);
	##printf "B %s A %s\n",quot($before),quot($after);

	printf "% 5d ", $pos if $SEARCHDEBUG;
	##printf "% 5d %s ", $pos, "X";
	my ($mlen,$mpos,$mpos2) = search($pos,$before,$after);
	#if( ($mlen > 2 && $mpos <= 127) || ($mlen > 3) ){
	# XXX right value here...
	if( $mlen > $MINLEN-2 ){
		my $endpos = $pos+$mlen-1;
		my @data = ($pos, $mlen,$mpos,$mpos2);
		push @first, \@data;
		printf "FOUND len: %3s off: %4s end: %4s \"%s\"", $mlen, $mpos, $endpos, quot(substr($contents,$pos-$mpos,$mlen)) if $SEARCHDEBUG;
	}else{
		$mlen=0;$mpos=0;
		printf "CHAR  len: %3s off: %4s", $mlen, $mpos if $SEARCHDEBUG;
	}

	say "" if $SEARCHDEBUG;
	
#	my $enclen;
#	my $encpos;
#	# XXX OFFSET: mlen==0 means EOF
#	$enclen = $mlen + $MATCHLENOFF;
#	if($mpos>127){
#		#$encpos = $mpos;
#		my $encpos2 = ~( $mpos>>8 );
#		$encpos = $mpos % 256;
#		##printf "EEE $mpos %2x $encpos\n", $encpos2;
#		
#		print $fh $char, pack("CcC", $enclen, $encpos2,$encpos);
#	}else{
#		$encpos = $mpos;
#		if($enclen == 0){
#			$encpos = 1;
#			print $fh $char;
#		}
#		else {
#			print $fh $char, pack("CC", $enclen, $encpos);
#		}
#	}
	
	if($SHOWSKIP){
		for(1..$mlen){
			printf "% 5d %3s skip\n", $pos+$_, quot(substr($contents,$pos+$_,1));
		}
	}
	#$pos += $mlen;

	#say "B: ",quot($before);
	#say "A: ",quot(substr($after,0,50));
	#say "";
}
#my @data = (0,0,0);
#push @first, \@data;

#say Dumper(\@first);
#exit;

#my $fstart = 0;
#my @second;
# PARSE MATCHES
my %h;
my $mi = 0;
PARSE: for(my $pos = $length; $pos >= 0; $pos--){
	say "POS $pos" if $PARSEDEBUG;
	my @entry = ();
	my $enum;

	my $match = 0;
	my $mlen = 0;
	my $mlen0 = 0;
	my $mnet = 0;
	my $mpos = 0;
	my $mpos2 = 0;
	my $mx = 9999999999;
	SEARCH: for(my $i = $mi; $i < scalar(@first); $i++){
		my @t = @{ $first[$i] };
		my $endpos = $t[0] + $t[1] - 1;
		my $tlen = $t[1];
		my $end2 = $endpos;
		if($endpos > $pos){
			$end2 = $pos;
		}
		my $tlen2 = $end2 - $t[0] + 1;
		my $enclen = 9999999;
		if($tlen2 >= 0){
			$enclen = matchlen($t[2],$tlen2)+0;
		}
		my $minlen = $MINLEN;
		my $tnet = $tlen2 - $enclen;
		say "\tMMM MINLEN:$MINLEN enclen:$enclen tpos:$t[2] tlen2:$tlen2" if $PARSEDEBUG;
		if($VARIANT==1 && $t[2]>=64){
			#$minlen++;
		}
		#if($VAROFFSET16 && $t[2]>127){
		#	$minlen++
		#}
		#XXX say "\tTT tlen:$tlen tlen2:$tlen2 tpos:$t[2] mlen:$mlen minlen:$minlen" if $PARSEDEBUG;
		say "\t$t[0]-$endpos len:$t[1]" if $PARSEDEBUG;
		#@entry = @{ $first[$i] };
		#if($endpos >= $pos && $tlen2 >= $mlen && $minlen <= $mx){
		#if($endpos >= $pos){
		#if($endpos >= $pos && $tlen2 >= $mlen && $minlen <= $mx){
		#if($endpos >= $pos && $tlen2 >= $mlen && $tlen2 >= $minlen){
		if($endpos >= $pos && $tlen2 >= $mlen && $tlen2 >= $minlen && $tlen2 > $enclen && $tnet >= $mnet){
			#&& $minlen <= $mx){
			if(0){
			#if($tlen2 >= $mlen && $minlen <= $mx){
				say "\t\tMINLEN $minlen" if $PARSEDEBUG;
			}
			$match = $t[0];
			$mlen = $tlen2;
			$mlen0 = $tlen;
			$mnet = $tnet;
			$mpos = $t[2];
			$mx = $minlen;
			$mpos2 = $pos;
			$mi = $i+1;
			my $extra ="";
			#say "\t\tGOOD $match,$mlen mpos:$mpos $extra" if $PARSEDEBUG;
		}
		if($endpos < $pos){
			if($mlen>0){
				say "\tLAST" if $PARSEDEBUG;
				last
			}
			else {
				#$pos--;
				say "\tNEXT PARSE" if $PARSEDEBUG;
				next PARSE;
				#say "uhoh pos$pos $match $mlen $i @t";
				#$match = $t[0];
				#$mlen = $t[1];
				#$mpos = $t[2];
			}
		}
		$enum = $i;
		#last if $endpos <= $pos;

	}
	#@entry = @{ $first[$mnum] };
	#my $newpos = $entry[0];
	#my $endpos2 = $entry[0] + $entry[1] - 1;
	my $endpos = $match + $mlen - 1;
	my $extra="";
	if($mlen!=$mlen0){
	}
	$extra="SIZEDIFF:".($mlen0-$mlen);
	say "\tCHOSEN: $pos $match-$endpos len:$mlen $extra" if $PARSEDEBUG;
	say "\tE $enum ",scalar(@first) if $PARSEDEBUG;
	#say "\tCHOSEN:  $pos $newpos-$endpos2 len:$entry[1]";
	# TODO: ue startpos as primary ident
	# TODO: remove mpos2/the last value
	# XXX: why the hell +1??
	#$h{$pos} = [$pos,$mlen,$match,0];
	if($match > 0){
		$h{$match} = [$match,$mlen,$mpos,$endpos];
	}

	say "MIAU $mx $pos $mpos2 [$pos,$mlen,$mpos,0] @entry" if $PARSEDEBUG;
	##say "EE len $mlen endpos $endpos curpos $pos";# e ",($mpos);
	if($enum == (scalar(@first)-1)){
		say "END PARSE" if $PARSEDEBUG;
		last PARSE;
	}
	##last SEARCH if $endpos < $pos;

	#printf "EE len %3d start %4d end %4d curpos %4d\n",$mlen,$xpos,$endpos,$pos;
	#printf "EE len %3d start %4d end %4d curpos %4d\n",$mlen,$xpos,$endpos,$pos;
	say "NEWPOS $pos, match $match" if $PARSEDEBUG;
	if($pos < $match){
		#die "uggh";
		#$pos++;
	}else{
		if($NOZERO){
			$pos = $match - 1;
		}else{
			$pos = $match;
		}
	}
}

#say Dumper(\%h);
#exit;

sub vardec {
	my $enc = shift;
	my ($v1, $extra) = unpack("Ca",$enc);
	my $bit1 = $v1 % 2;
	my $v2 = $v1 >> 1;
	printf "VARDEC %d -> %d %d. extralen %d\n",$v1,$bit1,$v2,length($extra) if $VALDEBUG;
	my $next = -1;
	my $v3 = $v2;
	if($bit1){
		$next = unpack("C",$extra);
		$v3 = $v3*256+$next;
	}
	printf "VARDEC2 nextbyte:%d val:%d\n",$next,$v3 if $VALDEBUG;

	my $type = $v3 % 2;
	my $val = $v3 >> 1;
	printf "VARDEC3 val:%d type:%d\n",$val,$type if $VALDEBUG;

	return ($val,$type);
}

sub varintold {
	my $val = shift;
	my $MAXVAL = 128;
	my $enc;

	confess "varint too big" if $val > 32767;
	if($val >= $MAXVAL){
		my $val1 = int($val/256);
		my $val2 = $val % 256;
		say "VAL $val, 2b $val1,$val2" if $VALDEBUG;
		$enc = pack("CC", 2*$val1+1, $val2);
	}else{
		say "VAL $val, 1b $val" if $VALDEBUG;
		$enc = pack("C", 2*$val);
	}

	return $enc;
}

sub varint {
	my $val = shift;
	my $MAXVAL = 128;
	my $enc;

	if($val >= $MAXVAL){
		my $val1 = int($val/$MAXVAL);
		my $val2 = ($val % $MAXVAL);
		say "VAL $val, 2b $val1,$val2" if $VALDEBUG;
		$enc = pack("CC", 2*$val1+1, 2*$val2);
	}else{
		say "VAL $val, 1b $val" if $VALDEBUG;
		$enc = pack("C", 2*$val);
	}

	return $enc;
}

sub varintnew {
	my $val = shift;
	my $MAXVAL = 128;
	my @enc;
	my $enc = "";
	my $count = 0;

	say "VAL input $val" if $VALDEBUG;
	while(1){
		my $val7 = ($val % $MAXVAL);
		$val = int($val / $MAXVAL);

		if($val > 0){
			say "VAL $val -> $val7" if $VALDEBUG;
			my $more = 0;
			if($count>0){
				$more = 1;
			}
			else{
				$count++;
			}	
			my $p = pack("C", 2*$val7+$more);# || confess "pack failed";
			$enc = $p . $enc;
		}
		else{
			say "VAL last $val -> $val7" if $VALDEBUG;
			my $more = 0;
			if($count>0){
				$more = 1;
			}
			my $p = pack("C", 2*$val7+$more);# || confess "pack failed";
			$enc = $p . $enc;
			last;
		}

	}

	return $enc;
}

sub vartype {
	my $val = shift;
	my $type = shift;

	my $tval = $val*2 + $type;

	my $enc = varintnew($tval);

	# XXX fix
	#my ($newval, $newtype) = vardec($enc);
	#confess "assert failed" if $newval  ne $val;
	#confess "assert failed" if $newtype ne $type;
	return $enc;

}

sub litlenenc {
	my $len = shift;

	if($VARIANT == 1){
		return vartype($len,$LITTYPE);
		#return pack("C",$val*2+1);
	}else{
		return 0;
	}
}

sub litenc {
	my $len = shift;
	my $string = shift;
	
	say "" if $VALDEBUG;
	return litlenenc($len).$string;
}

sub matchenc {
	my $offset = shift;
	my $len = shift;
	say "" if $VALDEBUG;
	say "MATCHENC off:$offset len:$len" if $VALDEBUG;

	if($VARIANT == 1){
		if($len > 255 || $len < 0){
			confess "len out of range";
		}
		my $t = vartype($offset,$MATCHTYPE);
		my $l = pack("C", $len);
		return $t.$l;
	}else{
		if($offset>127){
			my $encoff2 = ~( $offset>>8 );
			my $encoff = $offset % 256;
			#$enc = pack("CcC", $len-$OUTMINLEN, $encoff2,$encoff);
		#	$enc = pack("cCC", $encoff2*2+1,$encoff,$len-$OUTMINLEN);
		}else{
			#$enc = pack("CC", $offset*2+1, $len-$OUTMINLEN);
		}
	return 0;
	}
}

sub matchlen {
	my $offset = shift;
	my $len = shift;
	my $calc = 1;
	my $bits = ceil(log2($offset+1));
	if($bits > 6){
		$calc++;
		$bits -= 6;
	}
	$calc += ceil($bits/7);
	if(0){
		my $actual = length(matchenc($offset,$len));
		confess "assert failed: offset $offset, bits $bits, calc $calc != $actual" if $actual != $calc;
	}
	return $calc;
}

# FINAL ASSEMBLY & OUTPUT
open(my $fh, '>', $FILE);
my $nomatch = -1;
#rintf "LIT   %4d %4d\t\t%3d {%s}\n", $pos1, $len, $enclen, quot2($str);
printf "Type   Pos  Len  Offset\tOutLen\n";
for(my $pos = 0;$pos <= $length; $pos++){
	my $match = -1;
	for($pos..$length){
		if($h{$_}){
			#say "\tmmm $_";
			$match = $_;
			$nomatch = -1;
			last;
		}
	}

	my ($mlen,$mpos);
	if($match == -1){
		say "uhoh: no match at $pos";
		#$nomatch = $pos if $nomatch == -1;
		#if($nomatch == -1){
		#	$nomatch = $pos;
		#}
		#else{
		#	say "OOOOOOOO";
		#	last;
		#}
		# XXX
		($match,$mlen,$mpos) = ($length+1,0,$pos);
		#next;
	}
	else {
		($mlen,$mpos) = @{ $h{$match}  }[1,2];
	}

	my $pos1 = $pos;
	my $pos2 = $match;
	my $pos3 = $pos2 + $mlen - 1;
	# LIT
	{
		my $len = $match-$pos;
		if($len > 0){
			my $str = substr($contents, $pos1,($pos2-$pos1));
			my $enclen = 0;
			my $enc = litenc($len,$str);
			$enclen = length($enc);
			print $fh $enc;
			printf "LIT   %4d %4d\t\t%3d {%s}\n", $pos1, $len, $enclen, quotm($str);
			say "ENC ",quot($enc) if $VALDEBUG;
		}
	}

	# MATCH
	{
		last if $pos2 > $length;
		my $str = substr($contents,$pos2, ($pos3-$pos2)+1);
		(($pos3-$pos2)+1) == $mlen or die "MLEN assert failed";
		my $len = $mlen;
		my $off = $mpos;
		my $str2 = substr($contents, $pos2 - $off, $len);
		($str eq $str2) or die "match assert failed: \"$str\" != \"$str2\"";

		## XXX OFFSET: mlen==0 means EOF
		#$enclen = $mlen + $MATCHLENOFF;
		my $enc;
		#if($VAROFFSET16){
		if(1){
			$enc = matchenc($off - $OUTMINOFF, $len - $OUTMINLEN);
			#if($off>127){
			#	my $encoff2 = ~( $off>>8 );
			#	my $encoff = $off % 256;
			#	#$enc = pack("CcC", $len-$OUTMINLEN, $encoff2,$encoff);
			##	$enc = pack("cCC", $encoff2*2+1,$encoff,$len-$OUTMINLEN);
			#}else{
			#	$enc = pack("CC", $off*2+1, $len-$OUTMINLEN);
			#}
		}
		my $enclen = length($enc);
		print $fh $enc;
		printf "MATCH %4d %4d %4d\t%3d {%s}\n", $pos2, $mlen, $off, $enclen, quotm($str);
		say "ENC ",quot($enc) if $VALDEBUG;

	}
	$pos = $pos3;
}
close $fh;
if($nomatch > 0){
	die "NOMATCH $nomatch";
}
say "SIZE: ", -s $FILE;


