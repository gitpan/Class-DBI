use strict;
use Test::More tests => 17;

require './t/testlib/Actor.pm';
require './t/testlib/Film.pm';
Actor->CONSTRUCT;
Film->CONSTRUCT;

Film->has_many(actors => Actor => film => { sort => 'name' });
my $film = Film->create({ Title => 'MY Film' });

Actor->make_filter(between => '%s >= ? AND %s <= ?');

my @act = (
  Actor->create({
    name => 'Actor 1', film => $film, salary => 10,
  }),
  Actor->create({
    name => 'Actor 2', film => $film, salary => 20,
  }),
  Actor->create({
    name => 'Actor 3', film => $film, salary => 30,
  }),
);

{ 
  ok my @actors = Actor->salary_between(0, 100), "Range 0 - 100";
  is @actors, 3, "Got all";
}

{ 
  my @actors = Actor->salary_between(100, 200);
  is @actors, 0, "None in Range 100 - 200";
}

{ 
  ok my @actors = Actor->salary_between(0, 10), "Range 0 - 10";
  is @actors, 1, "Got 1";
  is $actors[0]->name, $act[0]->name, "Actor 1";
}

{ 
  ok my @actors = Actor->salary_between(20, 30), "Range 20 - 20";
  @actors = sort { $a->salary <=> $b->salary } @actors;
  is @actors, 2, "Got 2";
  is $actors[0]->name, $act[1]->name, "Actor 2";
  is $actors[1]->name, $act[2]->name, "and Actor 3";
}

#----------------------------------------------------------------------
# Iterators
#----------------------------------------------------------------------

my $it = $film->actors;
isa_ok $it, "Class::DBI::Iterator";
is $it->count, 3, " - with 3 elements";

my $i = 0;
while (my $film = $it->next) {
  is $film->name, $act[$i++]->name, "Get $i";
}
ok !$it->next, "No more";
is $it->first->name, $act[0]->name, "Get first";


