use strict;
use Test::More tests => 17;

BEGIN {
  require './t/testlib/Film.pm';
  require './t/testlib/OtherFilm.pm';
  require './t/testlib/Actor.pm';
  Film->CONSTRUCT;
  OtherFilm->CONSTRUCT;
  Actor->CONSTRUCT;
}

ok(my $btaste = Film->retrieve('Bad Taste'), "Fetch Bad Taste again");

# ok(!OtherFilm->move($btaste), " need an ID to move");
ok( my $diff_taste = OtherFilm->move($btaste, "Bad Taste"), "move()");
ok( defined $diff_taste && $diff_taste->isa('OtherFilm'),
                                             " it's a different film");
is( $diff_taste->id, $btaste->id, '  with the same id()' );
is( $diff_taste->Rating, $btaste->Rating, '  with the same rating()' );
is( $diff_taste->NumExplodingSheep, $btaste->NumExplodingSheep, 
                                  '  with the same sheep' );

ok(my $more_taste = OtherFilm->move($btaste, "Bad Taste"), "Move it");
ok( defined $more_taste && $more_taste->isa('OtherFilm'),
                                             " it's a different film");
is( $more_taste->id, $btaste->id, '  with the same id()' );
is( $more_taste->Rating, $btaste->Rating, '  with the same rating()' );
is( $more_taste->NumExplodingSheep, $btaste->NumExplodingSheep, 
                                  '  with the same sheep' );

# Move in other direction, and change rating
ok(my $worse = Film->move($more_taste, 
     { title => "Worse Taste", rating => "18" }), "Move up");
ok(defined $worse && $worse->isa('Film'), " it's a different film");
is( $worse->id, "Worse Taste", "  with the correct title" );
isnt( $worse->Rating, $more_taste->Rating, " and different rating" );
is( $worse->Rating, 18, " (correct rating)" );

# Unrelated class
eval { Actor->move($btaste, "Bad Taste") };
ok $@, $@; 

  
