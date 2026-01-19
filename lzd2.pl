#!/usr/bin/perl
# VERSION: LZ77, 8/16bit matchpos varint
use v5.12;
use warnings;

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


open(my $fh, '>', 'out2.bin');
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
	#if( ($mlen > 2 && $mpos <= 127) || ($mlen > 3) ){
	if( ($mlen > 0) ){
	#if(1){
		printf "FOUND %3s %4s %4s \"%s\"", $mlen, $mpos, $pos+$mlen, quot(substr($contents,$pos-$mpos+1,$mlen));
		#printf "FOUND -%s \"%s\"", $mpos, quot(substr($contents,$pos-$mpos+1,$mlen));
	}else{
		#$mlen=0;$mpos=0;
		printf "CHAR";#  %3s %4s", $mlen, $mpos;
	}

	say "";
	
	my $enclen;
	my $encpos;
	# XXX OFFSET: mlen==0 means EOF
	$enclen = $mlen + $MATCHLENOFF;
	if($mpos>127){
		#$encpos = $mpos;
		my $encpos2 = ~( $mpos>>8 );
		$encpos = $mpos % 256;
		printf "EEE $mpos %2x $encpos\n", $encpos2;
		
		print $fh $char, pack("CcC", $enclen, $encpos2,$encpos);
	}else{
		$encpos = $mpos;
		if($enclen == 0){
			$encpos = 1;
		}
		print $fh $char, pack("CC", $enclen, $encpos);
	}
	
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
say "SIZE: ", -s "out2.bin";
