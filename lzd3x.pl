#!/usr/bin/perl
# VERSION: literal runs, so a bit more like LZSS now
# vv: first version to get get actually tested
# vv: first encoding is 840b. matchselection broken
# vv: now 951, great
# should be 516b for astley.txt with forward parsing
# astley.txt	1730
# astley.lzd1	 752
# astley.lzd2	 612
# astley.lzd3	 516
# astley.lz4	 506
# astley.xz0	 391
# astley.gz	 368
#
# LaRRLa
# Labbba
use v5.12;
use warnings;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our $SHOWSKIP		= 0;
our $RLE		= 0;
# matchlen==0 means EOF in LZ77 mode
our $MATCHLENOFF	= 0;
our $MATCHPOSOFF	= 0;
our $MINLEN		= 3;

our $WINDOW;
our $MATCHLEN;
our $PACK;
if(0){
	$WINDOW		= 255;
	$MATCHLEN	= 255 -	$MATCHLENOFF;
	$PACK		= "CC";
}elsif(0){
	$WINDOW		= 65535;
	$MATCHLEN	= 65535 - $MATCHLENOFF;
	$PACK		= "SS";
}else{
	$WINDOW		= 65535;
	#$WINDOW		= 1005; # XXX
	$MATCHLEN	= 255 - $MATCHLENOFF;
	$PACK		= "CS";
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


my $contents = do { local $/; <> || die "read failed: $!" };

sub quot {
	my $q = shift;
	$q =~ s/\n/\\n/g;
	$q =~ s/ /\\40/g;
	return $q;
}

sub quot2 {
	my $q = shift;
	$q =~ s/\n/\\n/g;
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

	SEARCH: for my $nlen (1..length($after)){
		my $needle = substr($after,0,$nlen);


		my $in = rindex($before,$needle);
		if($in >= 0 && length($needle) > $len){
			$pos = $in;
			$len = length($needle);
		}
		else{
			last
		}
	}

	my $pos2 = 0;
	if($len > 0){
		$pos2 = abs($pos - $blen);
	}
	return ($len,$pos2,$pos);
}


my @first;
my $length = length($contents)-1;
#for(my $pos = 0;$pos < length($contents); $pos++){
for(my $pos = $length; $pos >= 0; $pos--){
#for(0..50){
	my $before = substr($contents,0,$pos+0);	
	# XXX OFFSET
	my $after = substr($contents,$pos+0,$MATCHLEN);	
	my $char = substr($contents,$pos,1);
	#say "B ",quot($before)," C ",quot($char)," A ",quot($after);
	#printf "B %s A %s\n",quot($before),quot($after);

	printf "% 5d %3s ", $pos, quot($char);
	#printf "% 5d %s ", $pos, "X";
	my ($mlen,$mpos,$mpos2) = search($pos,$before,$after);
	if( ($mlen > 2 && $mpos <= 127) || ($mlen > 3) ){
		my $endpos = $pos+$mlen-1;
		my @data = ($pos, $mlen,$mpos,$mpos2);
		push @first, \@data;
		printf "FOUND len: %3s off: %4s end: %4s \"%s\"", $mlen, $mpos, $endpos, quot(substr($contents,$pos-$mpos,$mlen));
	}else{
		$mlen=0;$mpos=0;
		printf "CHAR  len: %3s off: %4s", $mlen, $mpos;
	}

	say "";
	
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


#my $fstart = 0;
#my @second;
my %h;
PARSE: for(my $pos = $length; $pos > 0; $pos--){
	my $xpos =	0;
	my $mlen =	0;
	my $mpos =	0;
	my $mpos2 =	0;
	#my $startpos =	0;
	say "POS $pos";
	#SEARCH: for my $e (@first){
	my @entry = ();
	my $enum;
	SEARCH: for(my $i = 0; $i < scalar(@first); $i++){
		my @t = @{ $first[$i] };
		#say "DDDD $i $first[$i] @entry";
		#my @entry = @{ $e };
		my $endpos = $t[0] + $t[1] - 1;
		#say "X $t[0] $endpos < $pos";
		@entry = @{ $first[$i] };
		$enum = $i;
		last if $endpos <= $pos;

#		#say "DDDD $e @entry";
#		if(${ $first[$i] }[0] >= $pos){
#			@entry = @{ $first[$i] };
#			($xpos, $mlen,$mpos,$mpos2) = @entry;
#			#say "CAND $entry[0] len $entry[1] pos $entry[2]";		
#			#$mpos =	$entry[0];
#			#$mlen =		$entry[1];
#			#$mpos =		$entry[2];
#
#			#$startpos = $endpos - $mlen;
#		}
#		else {
#			#$fstart = $i;
#			last SEARCH;
#		}
	}
	#unshift @second, [$endpos,$mlen,$mpos];
	my $newpos = $entry[0];
	my $endpos = $entry[0] + $entry[1] - 1;
	#say "E0 $enum ",scalar(@first);
	say "EE $newpos $endpos @entry";
	$h{$newpos} = \@entry;
	# XXX why needed?
	if($xpos>0){
		$h{$xpos} = \@entry;
	}
	##say "EE len $mlen endpos $endpos curpos $pos";# e ",($mpos);
	##last SEARCH if $endpos < $pos;

	last PARSE if $enum == (scalar(@first)-1);
	#printf "EE len %3d start %4d end %4d curpos %4d\n",$mlen,$xpos,$endpos,$pos;
	#printf "EE len %3d start %4d end %4d curpos %4d\n",$mlen,$xpos,$endpos,$pos;
	$pos = $newpos;
}

#say Dumper(\%h);
#exit;
open(my $fh, '>', 'lzd3.bin');
for(my $pos = 0;$pos <= $length; $pos++){
	my $match = -1;
	for($pos..$length){
		if($h{$_}){
			#say "\tmmm $_";
			$match = $_;
			last;
		}
	}
	#my ($endpos,$mlen,$mpos) = @{ $h{$match}  }; 
	my ($xpos, $mlen,$mpos,$mpos2) = @{ $h{$match}  };
	say "DBG $match $xpos $mlen $mpos $mpos2";

	#printf "P %4d %4d %4d %4d %4d\n", $pos, $xpos,$mlen,$mpos,$mpos2;
	#printf "\tP pos %4d match %4d xpos %4d mlen %4d\n", $pos, $match, $xpos,$mlen;
	my $pos1 = $pos;
	my $pos2 = $xpos;
	my $pos3 = $pos2 + $mlen - 1;
	#if($pos!=$pos2){
	if(1){
		my $len = $match-$pos;
		my $str = substr($contents, $pos1,($pos2-$pos1));
		my $enc = pack("C",$len) . $str;
		my $enclen = length($enc);
		print $fh $enc;
		printf "LIT   %4d-%4d %4d\t\t%3d {%s}\n", $pos1, $pos2-1, $len, $enclen, quot2($str);
	}
#	#printf "P %4d %4d %3d\n", $pos, $endpos,$mlen;
#	my $pos1 = $pos;
#	my $pos2 = $match;
#	my $pos3 = $endpos;
#	if($pos!=$pos2){
#		printf "LIT   %4d-%4d\t\t{%s}\n", $pos1, $pos2-1, quot2(substr($contents, $pos1,($pos2-$pos1)));
#	}
#	#$pos = ($endpos-$mlen);
	#printf "MATCH %4d-%4d %3d - %3d %3d %3d\t\t{%s}\n", $pos2, $pos3, $mlen, $xpos, $mpos, $mpos2, quot2(substr($contents,$pos2, ($pos3-$pos2)+1));

	{
		my $str = substr($contents,$pos2, ($pos3-$pos2)+1);
		(($pos3-$pos2)+1) == $mlen or die "MLEN assert failed";
		my $len = $mlen;
		my $off = $mpos;
		my $str2 = substr($contents, $pos2 - $off, $len);
		($str eq $str2) or die "match assert failed: \"$str\" != \"$str2\"";

		## XXX OFFSET: mlen==0 means EOF
		#$enclen = $mlen + $MATCHLENOFF;
		my $enc;
		if($off>127){
			#$encpos = $mpos;
			my $encoff2 = ~( $off>>8 );
			my $encoff = $off % 256;
			##printf "EEE $mpos %2x $encpos\n", $encpos2;
			
			$enc = pack("CcC", $len, $encoff2,$encoff);
		}else{
			#my $encpos = $off;
			#if($len == 0){
			#	$encpos = 1;
			#	print $fh $char;
			#}
			#else {
			$enc = pack("CC", $len, $off);
			#}
		}
		my $enclen = length($enc);
		print $fh $enc;
		printf "MATCH %4d-%4d %4d %4d\t%3d {%s}\n", $pos2, $pos3, $mlen, $mpos2, $enclen, quot2($str);

	}
	$pos = $pos3 + 0;
#	$pos = $pos3;
	#say "";
}
close $fh;
say "SIZE: ", -s "lzd3.bin";


