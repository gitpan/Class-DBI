use strict;
use Test::More tests => 18;

BEGIN {
  require './t/testlib/Film.pm';
  require './t/testlib/Director.pm';
  Film->CONSTRUCT;
  Director->CONSTRUCT;
}
ok( my $btaste = Film->retrieve('Bad Taste'), "We have Bad Taste");
ok( my $pj = $btaste->Director, "Bad taste hasa() director");
ok( !ref($pj), ' ... which is not an object');

ok(Film->hasa('Director' => 'Director'), "Link Director table");
ok( Director->create({ 
  Name       => 'Peter Jackson',
  Birthday   => -300000000,
  IsInsane   => 1
}), 'create Director' );

ok( $pj = $btaste->Director, "Bad taste now hasa() director");
ok( $pj->isa('Director'), ' ... which isa->Director');
is( $pj->id, 'Peter Jackson', ' ... and is the correct director');

# Oh no!  Its Peter Jackson's even twin, Skippy!  Born one minute after him.
my $sj = Director->create({ 
  Name       => 'Skippy Jackson',
  Birthday   => (-300000000 + 60),
  IsInsane   => 1,
});

is( $sj->id, 'Skippy Jackson', 'We have a new director' );
Film->hasa('Director' => 'CoDirector');
$btaste->CoDirector($sj);
$btaste->commit;
is( $btaste->CoDirector->Name, 'Skippy Jackson', 'He co-directed' );
is( $btaste->Director->Name, 'Peter Jackson', "Didn't interfere with each other" );


package YA::Film;
use base qw(Film);

package main;

$btaste = YA::Film->retrieve('Bad Taste');
is( ref($btaste->Director), 'Director', 'inheriting hasa()' );
is( ref($btaste->CoDirector), 'Director', 'inheriting hasa()' );
is( $btaste->CoDirector->Name, 'Skippy Jackson', ' ... correctly');

# Skippy directs a film and Peter helps!
$sj = Director->retrieve('Skippy Jackson');
$pj = Director->retrieve('Peter Jackson');

my $tastes_bad = YA::Film->create({ Title          => 'Tastes Bad',
                                    Director       => $sj,
                                    CoDirector     => $pj,
                                    Rating         => 'R',
                                    NumExplodingSheep => 23
                                  });

is( $tastes_bad->_Director_accessor, 'Skippy Jackson', 'Director_accessor');
is( $tastes_bad->Director->Name, 'Skippy Jackson', 'Director' );
is( $tastes_bad->CoDirector->Name, 'Peter Jackson', 'CoDirector' );
is( $tastes_bad->_CoDirector_accessor, 'Peter Jackson', 'CoDirector_accessor' );

