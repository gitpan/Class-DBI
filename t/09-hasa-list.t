use strict;
use Test::More tests => 25;

BEGIN {
  require './t/testlib/Film.pm';
  require './t/testlib/Actor.pm';
  Film->CONSTRUCT;
  Actor->CONSTRUCT;
  Film->has_many(actors => Actor => 'Film', { sort => 'name' });
  is(Actor->_primary, 'name', "Actor primary OK");
}

ok(Actor->can('Salary'), "Actor table set-up OK");
ok(Film->can('actors'), " and have a suitable method in Film");

ok( my $btaste = Film->retrieve('Bad Taste'), "We have Bad Taste");

ok(my $pvj = Actor->create({ 
  Name       => 'Peter Vere-Jones',
  Film       => undef,
  Salary     => '30_000',  # For a voice!
}), 'create Actor' );
is $pvj->Name, "Peter Vere-Jones", "PVJ name ok";
ok !$pvj->Film, "No film";
ok $pvj->set_Film($btaste), "Set film"; 
   $pvj->commit;
is $pvj->Film->id, $btaste->id, "Now film";
{
  my @actors = $btaste->actors;
  is(@actors, 1, "Bad taste has one actor");
  is($actors[0]->Name, $pvj->Name, " - the correct one");
}

ok( my $pj = Actor->create({ 
  Name       => 'Peter Jackson',
  Film       => $btaste,
  Salary     => '0',  # it's a labour of love
}), 'add another actor' );
is $pj->Name, "Peter Jackson", "PJ ok";
is $pvj->Name, "Peter Vere-Jones", "PVJ still ok";


{
  my @actors = $btaste->actors;
  is(@actors, 2, " - so now we have 2");
  is $actors[0]->Name, $pj->Name, "PJ first";
  is $actors[1]->Name, $pvj->Name, "PVJ first";
}

my $as = Actor->create({ 
  Name       => 'Arnold Schwarzenegger',
  Film       => 'Terminator 2',
  Salary     => '15_000_000'
});

eval { $btaste->actors($pj, $pvj, $as) };
ok $@, $@;
is($btaste->actors, 2, " - so we still only have 2 actors");

my @bta_before = Actor->search(Film => 'Bad Taste');
is (@bta_before, 2, "We have 2 actors in bad taste");
ok ($btaste->delete, "Delete bad taste");
my @bta_after = Actor->search(Film => 'Bad Taste');
is (@bta_after, 0, " - after deleting there are no actors");

# While we're here, make sure Actors have unreadable mutators and
# unwritable accessors

eval { $as->Name("Paul Reubens") }; ok $@, $@;
eval { my $name = $as->set_Name };  ok $@, $@;

is($as->Name, 'Arnold Schwarzenegger', "Arnie's still Arnie");

