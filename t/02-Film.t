use strict;
use Test::More tests => 32;

require './t/testlib/Film.pm';
Film->CONSTRUCT;

ok( Film->can('db_Main'), 'set_db()'  );

my $btaste = Film->retrieve('Bad Taste');
is( ref $btaste, 'Film', 'new()'     );
is( $btaste->Title, 'Bad Taste', 'Title() get'   );
is( $btaste->Director, 'Peter Jackson', 'Director() get'    );
is( $btaste->Rating, 'R', 'Rating() get'      );
is( $btaste->NumExplodingSheep, 1, 'NumExplodingSheep() get'   );

Film->create({ Title       => 'Gone With The Wind',
               Director        => 'Bob Baggadonuts',
               Rating      => 'PG',
               NumExplodingSheep   => 0
             });

# Retrieve the 'Gone With The Wind' entry from the database.
my $gone = Film->retrieve('Gone With The Wind');
is( ref $gone, 'Film', 'retrieve()'    );

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

# Make a copy of 'Bladerunner' and create an entry of the director's
# cut from it.
my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");
is( ref $blrunner_dc, 'Film', "copy() produces a film" );
is( $blrunner_dc->Title, "Bladerunner: Director's Cut", 'Title correct');
is( $blrunner_dc->Director, 'Bob Ridley Scott', 'Director correct');
is( $blrunner_dc->Rating, 'R', 'Rating correct');
is( $blrunner_dc->NumExplodingSheep, 0, 'Sheep correct');

{
  # Ishtar doesn't deserve an entry anymore.
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

# Test that a disconnect doesn't harm anything.
Film->db_Main->disconnect;
@films = Film->search('Rating', 'NC-17');
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

# Make sure that we can have other accessors. (Bugfix in 0.28)
{ 
  Film->mk_accessors(qw/temp1 temp2/);
  my $blrunner = Film->retrieve('Bladerunner');
  $blrunner->temp1("Foo");
  $blrunner->NumExplodingSheep(2);
  eval { $blrunner->commit };
  ok(!$@, "Other accessors");
}

