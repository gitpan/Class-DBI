use strict;
use Test::More tests => 11;

$|++;

require './t/testlib/Film.pm';
Film->CONSTRUCT;

sub valid_rating  { 
  my $value = shift;
  my $ok = grep $value eq $_, qw/U Uc PG 12 15 18/;
  return $ok;
}

Film->add_constraint('valid rating', Rating => \&valid_rating);

my %info = (
  Title    => 'La Double Vie De Veronique',
  Director => 'Kryzstof Kieslowski',
  Rating   => '18',
);

{
  local $info{Title} = "nonsense";
  local $info{Rating} = 19;
  eval { Film->create({%info}) };
  ok $@, $@;
  ok !Film->retrieve($info{Title}), "No film created";
  is Film->retrieve_all, 1, "Only one film";
}

ok (my $ver = Film->create({%info}), "Can create with valid rating");
is $ver->Rating, 18, "Rating 18";

ok $ver->Rating(12), "Change to 12";
ok $ver->commit, "And commit";
is $ver->Rating, 12, "Rating now 12";

eval { 
  $ver->Rating(13); 
  $ver->commit;
};
ok $@, $@;
is $ver->Rating, 12, "Rating still 12";
ok $ver->delete, "Delete";

