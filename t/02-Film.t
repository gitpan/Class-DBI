use strict;
use Test::More tests => 46;

$|=1;
require './t/testlib/Film.pm';
ok Film->CONSTRUCT, "Construct Film table";

ok( Film->can('db_Main'), 'set_db()'  );

{
  my $nul = Film->retrieve();
  is $nul, undef, "Can't retrieve nothing";
}

my $btaste = Film->retrieve('Bad Taste');
isa_ok $btaste, 'Film';
is( $btaste->Title, 'Bad Taste', 'Title() get'   );
is( $btaste->Director, 'Peter Jackson', 'Director() get'    );
is( $btaste->Rating, 'R', 'Rating() get'      );
is( $btaste->NumExplodingSheep, 1, 'NumExplodingSheep() get'   );

ok my $gone = Film->create({ Title       => 'Gone With The Wind',
  Director           => 'Bob Baggadonuts',
  Rating             => 'PG',
  NumExplodingSheep  => 0
}), "Add Gone With The Wind";
isa_ok $gone, 'Film';
ok $gone = Film->retrieve('Gone With The Wind'), "Fetch it back again";
isa_ok $gone, 'Film';

# Shocking new footage found reveals bizarre Scarlet/sheep scene!
is( $gone->NumExplodingSheep, 0,    'NumExplodingSheep() get again'     );
$gone->NumExplodingSheep(5);
is( $gone->NumExplodingSheep, 5,    'NumExplodingSheep() set'           );

is( $gone->Rating, 'PG', 'Rating() get again'    );
$gone->Rating('NC-17');
is( $gone->Rating, 'NC-17', 'Rating() set'          );
$gone->commit;

{
  my @films = eval { Film->retrieve_all };
  is (@films, 2, "We have 2 films in total");
}

my $gone_copy = Film->retrieve('Gone With The Wind');
ok( $gone->NumExplodingSheep == 5,  'commit()'      );
ok( $gone->Rating eq 'NC-17',       'commit() again'    );

# Grab the 'Bladerunner' entry.
Film->create({ Title       => 'Bladerunner',
               Director    => 'Bob Ridley Scott',
               Rating      => 'R',
               NumExplodingSheep => 0,  # Exploding electric sheep?
             });

my $blrunner = Film->retrieve('Bladerunner');
is( ref $blrunner, 'Film',    'retrieve() again'  );
ok( $blrunner->Title      eq 'Bladerunner'        &&
    $blrunner->Director   eq 'Bob Ridley Scott'   &&
    $blrunner->Rating     eq 'R'                  &&
    $blrunner->NumExplodingSheep == 0, ' ... with correct data');

# Make a copy of 'Bladerunner' and create an entry of the directors cut
my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");
is( ref $blrunner_dc, 'Film', "copy() produces a film" );
is( $blrunner_dc->Title, "Bladerunner: Director's Cut", 'Title correct');
is( $blrunner_dc->Director, 'Bob Ridley Scott', 'Director correct');
is( $blrunner_dc->Rating, 'R', 'Rating correct');
is( $blrunner_dc->NumExplodingSheep, 0, 'Sheep correct');

{
  # Ishtar doesnt deserve an entry anymore.
  my $ishtar = Film->create( { Title => 'Ishtar' } );
  ok( Film->retrieve('Ishtar'), 'Ishtar created');
  $ishtar->delete;
  ok( !Film->retrieve('Ishtar'), 'Ishtar deleted'  );
}

# Find all films which have a rating of NC-17.
my @films = Film->search('Rating', 'NC-17');
is( scalar @films, 1, ' search returns one film');
is( $films[0]->id, $gone->id, ' ... the correct one');

# Find all films which were directed by Bob
@films = Film->search_like('Director', 'Bob %');
is( scalar @films, 3, ' search_like returns 3 films');
ok( eq_array([sort map { $_->id } @films], 
             [sort map { $_->id } $blrunner_dc, $gone, $blrunner]),
    'the correct ones'   );

# Test that a disconnect doesnt harm anything.
Film->db_Main->disconnect;
@films = Film->search({ Rating => 'NC-17' });
ok( @films == 1 && $films[0]->id eq $gone->id, 'auto reconnection'  );

# Test rollback().
my $orig_director = $btaste->Director;
$btaste->Director('Lenny Bruce');
is( $btaste->Director, 'Lenny Bruce', 'set new Director' );
$btaste->rollback;
is( $btaste->Director, $orig_director, 'rollback()'     );

# Make sure a DESTROY without commit squeals
{
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_; };
  {
    my $br = Film->retrieve('Bladerunner');
    $br->Rating('FFF');
    $br->NumExplodingSheep(10);
  }
  is(scalar @warnings, 1, "DESTROY without commit warns");
}

# Primary key of 0
{ 
	ok my $zero = Film->create({ Title => 0, Rating => "U" }), "Create 0";
	ok my $ret = Film->retrieve(0), "Retrieve 0";
	is $ret->Title, 0, "Title OK";
	is $ret->Rating, "U", "Rating OK";
}

# Make sure that we can have other accessors. (Bugfix in 0.28)
{ 
  Film->mk_accessors(qw/temp1 temp2/);
  my $blrunner = Film->retrieve('Bladerunner');
  $blrunner->temp1("Foo");
  $blrunner->NumExplodingSheep(2);
  eval { $blrunner->commit };
  ok(!$@, "Other accessors");
}

{
  {
    ok my $byebye = DeletingFilm->create({ 
      Title       => 'Goodbye Norma Jean',
      Rating      => 'PG',
    }), "Add a deleting Film";

    isa_ok $byebye, 'DeletingFilm';
    isa_ok $byebye, 'Film';
    ok Film->retrieve('Goodbye Norma Jean'), "Fetch it back again";
  }
  ok !Film->retrieve('Goodbye Norma Jean'), "It destroys itself";
}

