use strict;
use Test::More tests => 8;

require './t/testlib/Film.pm';
ok Film->CONSTRUCT, "Construct Film table";

{
	my $btaste = Film->retrieve('Bad Taste');
	isa_ok $btaste, 'Film', "We have Bad Taste";
	{
		local *Ima::DBI::st::execute = sub { die "Database died" };
		local $SIG{__WARN__} = sub { 
			::like shift, qr/Failure.*Database died/s, "We failed";
		};
		$btaste->delete;
	}
	my $still = Film->retrieve('Bad Taste');
	isa_ok $btaste, 'Film', "We still have Bad Taste";
}

{
	my $btaste = Film->retrieve('Bad Taste');
	isa_ok $btaste, 'Film', "We have Bad Taste";
	$btaste->numexplodingsheep(10); 
	{
		local *Ima::DBI::st::execute = sub { die "Database died" };
		local $SIG{__WARN__} = sub { 
			::like $_[0], qr/Cannot commit.*Database died/s, "We failed";
		};
		$btaste->commit;
	}
	$btaste->rollback;
	my $still = Film->retrieve('Bad Taste');
	isa_ok $btaste, 'Film', "We still have Bad Taste";
	is $btaste->numexplodingsheep, 1, "with 1 sheep";
}

