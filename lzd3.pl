#!/usr/bin/perl
# VERSION: literal runs, so a bit more like LZSS now
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
# astley.lzd3	 512	30	 542
# astley.lzd4	 501	33	 540
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

eval 'exec perl $0 "$@"'
if 0; # ^ Run only under a shell

use v5.12;
use warnings FATAL => qw(pack);
#use feature 'say';
no feature 'unicode_strings';
#use re "/a";
no utf8;
use bytes;
#use open IN  => ':raw', OUT => ':raw';
#use open ':std', IN => ':raw', OUT => ':raw', IO => ':raw';
#use open IN => ':bytes', OUT => ':bytes', IO => ':bytes';
use open qw' :std IO :bytes IN :bytes OUT :bytes';
#use open qw' :std IO :raw   IN :raw   OUT :raw';
#binmode STDIN;
use warnings;
use Data::Dumper;
#$Data::Dumper::Sortkeys = 1;

our $FILE		= "out3.bin";
our $SHOWSKIP		= 0;

our $SEARCH0DEBUG	= 0;
our $SEARCHDEBUG	= 0;
our $PARSEDEBUG		= 0;

our $WINDOW;
our $MATCHLEN;
our $PACK;
our $LITPACK;

# COMPRESSION TUNING
# matchlen==0 means EOF in LZ77 mode
our $MATCHLENOFF	= 0;
our $LITOFF		= 0;
our $MINLEN		= 4; # in code
our $OUTMINLEN		= 0; # in the decompressor

our $NOZERO		= 0; # force nonzero literal between matches. doesn't help usually
our $RLE		= 1;
our $VAROFFSET16	= 1; # variable 8/16bit offset
# /COMPRESSION TUNING

# WINDOW/MATCH SETTINGS
if(0){
	$WINDOW		= 255;
	$MATCHLEN	= 255 -	$MATCHLENOFF;
	$PACK		= "CC";
	$LITPACK	= "C";
}elsif(0){
	$WINDOW		= 65535;
	$MATCHLEN	= 65535 - $MATCHLENOFF;
	$PACK		= "SS";
	$LITPACK	= "C";
}else{
	$WINDOW		= 65535;
	$WINDOW		= 32768;
	#$WINDOW		= 1005; # XXX
	$MATCHLEN	= 255 - $MATCHLENOFF + $OUTMINLEN;
	$PACK		= "CS";
	$LITPACK	= "S";
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
	my $MAX = 60;
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

	printf "S %ipos before:{%s} after:{%s}\n",$ipos,quotm($before),quotm($after) if $SEARCH0DEBUG;
	SEARCH: for my $nlen (1..length($after)){
		my $needle = substr($after,0,$nlen);

		my $in = rindex($before,$needle);
		my $relp = abs($in - $blen);
		my $lastp = $relp - $nlen;
		if($in >= 0){
			printf "match %4d %3d %3d \"%s\"\n",$relp,$nlen,$lastp,quotm($needle) if $SEARCH0DEBUG;
			if($lastp == 0){
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
				if(!$RLE){
					$rle = 1; # XXX
				}
				if($nlen * $rle > $len){
					$pos = $in;
					$len = $nlen * $rle;
					printf "matc2 %4d %3d %3d \"%s\"\n",$relp,$len,$lastp,quotm($needle) if $SEARCH0DEBUG;
				}
			}
			else {
				# XXX duplicate
				if($nlen > $len){
					$pos = $in;
					$len = $nlen;
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
	#if( $mlen > $MINLEN-1 ){
	if(1){
		my $endpos = $pos+$mlen-1;
		my @data = ($pos, $mlen,$mpos,$mpos2);
		push @first, \@data;
		printf "FOUND len: %3s off: %4s end: %4s \"%s\"", $mlen, $mpos, $endpos, quot(substr($contents,$pos-$mpos,$mlen)) if $SEARCHDEBUG;
		say "" if $SEARCHDEBUG;
	}else{
		$mlen=0;$mpos=0;
		printf "CHAR  len: %3s off: %4s", $mlen, $mpos if $SEARCHDEBUG;
	}

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
	my $mpos = 0;
	my $mpos2 = 0;
	my $mx = 0;
	SEARCH: for(my $i = $mi; $i < scalar(@first); $i++){
		my @t = @{ $first[$i] };
		my $endpos = $t[0] + $t[1] - 1;
		my $tlen = $t[1];
		my $end2 = $endpos;
		if($endpos > $pos){
			$end2 = $pos;
		}
		my $tlen2 = $end2 - $t[0] + 1;
		my $minlen = $MINLEN;
		if($VAROFFSET16 && $t[2]>127){
			$minlen++
		}
		#say "\tTT $tlen $tlen2 $t[2]" if $PARSEDEBUG;
		#say "\t$t[0]-$endpos len:$t[1]" if $PARSEDEBUG;
		#@entry = @{ $first[$i] };
		if($endpos >= $pos && $tlen2 >= $mlen && $tlen2 >= $minlen){
			$match = $t[0];
			$mlen = $tlen2;
			$mpos = $t[2];
			$mx = $t[3];
			$mpos2 = $pos;
			$mi = $i+1;
			#say "\tGOOD $match,$mlen" if $PARSEDEBUG;
			say "\tGOOD $pos: $t[0]-$endpos len:$t[1]" if $PARSEDEBUG;
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
	say "\tCHOSEN: $pos $match-$endpos len:$mlen" if $PARSEDEBUG;
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

# FINAL ASSEMBLY & OUTPUT
open(my $fh, '>', $FILE);
my $nomatch = -1;
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

	#printf "P %4d %4d %4d %4d %4d\n", $pos, $xpos,$mlen,$mpos,$mpos2;
	#printf "\tP pos %4d match %4d xpos %4d mlen %4d\n", $pos, $match, $xpos,$mlen;
	my $pos1 = $pos;
	my $pos2 = $match;
	my $pos3 = $pos2 + $mlen - 1;
	#if($pos!=$pos2){
	if(1){
		my $len = $match-$pos;
		my $str = substr($contents, $pos1,($pos2-$pos1));
		my $enc = (pack("C",$len+$LITOFF) || die "failed to pack at $pos") . $str;
		my $enclen = length($enc);
		print $fh $enc;
		#if($len==0){
		#	printf "LIT    %-8s\t\t%3d {%s}\n", "zero",$enclen, quot2($str);
		#}else{
			printf "LIT   %4d %4d\t\t%3d {%s}\n", $pos1, $len, $enclen, quotm($str);
		#}
	}

	# MATCH
	{
		last if $pos2 > $length;
		my $str = substr($contents,$pos2, ($pos3-$pos2)+1);
		(($pos3-$pos2)+1) == $mlen or die "MLEN assert failed";
		my $len = $mlen;
		my $off = $mpos;
		my $str2 = substr($contents, $pos2 - $off, $len);
		#say STDERR "DBG $xpos $off,$len";
		#printf STDERR "MATCH %4d-%4d %4d %4d\t%3d {%s}\n", $pos2, $pos3, $mlen, $mpos2, 0, quot2($str);
		($str eq $str2) or die "match assert failed: \"$str\" != \"$str2\"";

		## XXX OFFSET: mlen==0 means EOF
		#$enclen = $mlen + $MATCHLENOFF;
		my $enc;

		if($VAROFFSET16){
			if($off>127){
				my $encoff2 = ~( $off>>8 );
				my $encoff = $off % 256;
				$enc = pack("CcC", $len-$OUTMINLEN, $encoff2,$encoff);
			}else{
				$enc = pack("CC", $len-$OUTMINLEN, $off);
			}
		}else{
			$enc = pack($PACK, $len-$OUTMINLEN, $off);
		}
		my $enclen = length($enc);
		print $fh $enc;
		printf "MATCH %4d %4d %4d\t%3d {%s}\n", $pos2, $mlen, $off, $enclen, quotm($str);
		#say "ENC ",quot($enc);

	}
	$pos = $pos3;
}
close $fh;
if($nomatch > 0){
	die "NOMATCH $nomatch";
}
say "SIZE: ", -s $FILE;


