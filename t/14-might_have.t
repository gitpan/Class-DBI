use strict;
use Test::More tests => 5;

$|++;

require './t/testlib/Film.pm';
require './t/testlib/Blurb.pm';
Film->CONSTRUCT;
Blurb->CONSTRUCT;

Film->might_have(info => Blurb => qw/blurb/);

{ 
	my $bt = Film->retrieve('Bad Taste');
  is $bt->info, undef, "No blurb yet";
}

{
	Blurb->make_bad_taste;
  my $bt = Film->retrieve('Bad Taste');
	my $info = $bt->info;
  isa_ok $info, 'Blurb';

  is $bt->blurb, $info->blurb, "Blurb is the same as fetching the long way";
  ok $bt->blurb("New blurb"), "We can set the blurb";
     $bt->commit;
  is $bt->blurb, $info->blurb, "Blurb has been set";
}
