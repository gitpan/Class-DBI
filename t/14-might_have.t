use strict;
use Test::More tests => 10;

$|++;

require './t/testlib/Film.pm';
require './t/testlib/Blurb.pm';
Film->CONSTRUCT;
Blurb->CONSTRUCT;

is Blurb->primary_column, "title", "Primary key of Blurb = title";
is_deeply [Blurb->_essential], [Blurb->all_columns], "Essential = All";

eval { Blurb->retrieve(10) };
is $@, "", "No problem retrieving non-existent Blurb";

Film->might_have(info => Blurb => qw/blurb/);

{ 
	ok my $bt = Film->retrieve('Bad Taste'), "Get Film";
	isa_ok $bt, "Film";
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
