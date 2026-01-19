#!/usr/bin/perl
# VERSION: LZ77, 16bit fixed window
use v5.12;
use warnings;

our $SHOWSKIP		= 0;
our $RLE		= 0;
# matchlen==0 means EOF in LZ77 mode
our $MATCHLENOFF	= 1;

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

sub search {
	my $ipos = shift;
	my $before0 = shift;
	# XXX OFFSET: current char is already written when we process the match
	my $before = substr($before0,-$WINDOW+1);
	my $after = shift;
	my $blen = length($before);
	my $pos = 0;
	my $len = 0;

	for my $nlen (1..length($after)){
		my $needle = substr($after,0,$nlen);

		# RLE
		if($RLE){
			my $bb = substr($before,-$nlen);
			if($bb eq $needle){
				dbg "\nBB %s\n",quot($bb);
				my $count = 0;
				RLE: while(1){
					my $m = $bb x $count;
					my $x = substr($after,0,$nlen*$count);
					dbg "MM $count $nlen $x\n";
					if($m ne $x){
						dbg "LASTne $count $nlen\n";
						last RLE;
					}
					dbg "MC %d (%d*%d) %d\n",$count*$nlen,$count,$nlen,length($after);
					if(($count+1)*$nlen >= length($after)){
						dbg "LASTlen $count $nlen\n";
						last RLE;
					}
					$count++;
				}
				my $newlen = $count * $nlen;
				#say "CC $count LEN $newlen ($count * $nlen)";
				if($newlen > $len){
					$len = $newlen;
					$pos = $blen - $nlen;
					#say "NEWMAX $len $pos ($blen - $nlen)";
				}
			}
		}
		# /RLE

		my $in = rindex($before,$needle);
		if($in >= 0 && length($needle) > $len){
			$pos = $in;
			$len = length($needle);
		}
	}

	my $pos2 = 0;
	if($len > 0){
		$pos2 = abs($pos - $blen);
	}
	return ($len,$pos2);
}


open(my $fh, '>', 'out.bin');
for(my $pos = 0;$pos < length($contents); $pos++){
#for(my $pos = length($contents)-1; $pos >= 0; $pos--){
#for(0..50){
	my $before = substr($contents,0,$pos+1);	
	# XXX OFFSET
	my $after = substr($contents,$pos+1,$MATCHLEN);	
	my $char = substr($contents,$pos,1);
	#say "B ",quot($before)," C ",quot($char)," A ",quot($after);
	dbg "B %s A %s\n",quot($before),quot($after);

	printf "% 5d %3s ", $pos, quot($char);
	#printf "% 5d %s ", $pos, "X";
	my ($mlen,$mpos) = search($pos,$before,$after);
	if($mlen > 0){
	#if(1){
		printf "FOUND %3s %4s \"%s\"", $mlen, $mpos, quot(substr($contents,$pos-$mpos+1,$mlen));
		#printf "FOUND -%s \"%s\"", $mpos, quot(substr($contents,$pos-$mpos+1,$mlen));
	}else{
		printf "FOUND %3s %4s", $mlen, $mpos;
	}

	say "";
	
	my $enclen;
	my $encpos;
	# XXX OFFSET: mlen==0 means EOF
	$enclen = $mlen + $MATCHLENOFF;
	$encpos = $mpos;

	print $fh $char, pack($PACK, $enclen, $encpos);
	if($SHOWSKIP){
		for(1..$mlen){
			printf "% 5d %3s skip\n", $pos+$_, quot(substr($contents,$pos+$_,1));
		}
	}
	$pos += $mlen;

	#say "B: ",quot($before);
	#say "A: ",quot(substr($after,0,50));
	#say "";
}
close $fh;
say "SIZE: ", -s "out.bin";
