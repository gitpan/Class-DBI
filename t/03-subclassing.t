use strict;
use Test::More tests => 4;

require './t/testlib/Film.pm';
Film->CONSTRUCT;

# Test simple subclassing.
package Film::Threat;
use base 'Film';

package main;

ok( Film::Threat->db_Main->ping,               'subclass db_Main()' );
ok( eq_array([sort Film::Threat->columns], [sort Film->columns]),
   'has the correct columns');

my $btaste = Film::Threat->retrieve('Bad Taste');

ok( defined $btaste && $btaste->isa('Film::Threat'),  'subclass new()' );
ok( $btaste->Title    eq 'Bad Taste',                 'subclass get()'   );
