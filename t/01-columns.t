use strict;
use Test::More tests => 9;

#-------------------------------------------------------------------------
package State;

use base qw(Class::DBI);

State->table('State');
State->columns('Primary',   'Name');
State->columns('Essential', qw( Name Abbreviation ));
State->columns('Weather',   qw( Rain Snowfall ));
State->columns('Other',     qw( Capital Population ));

sub Snowfall { 1 }

#-------------------------------------------------------------------------

package main;

is( State->table, 'State', 'table()'   );
ok( eq_array([State->columns('Primary')], ['name']), 'primary()' );
ok( eq_array([sort State->columns('All')], 
             [sort qw/name abbreviation rain snowfall capital population/]), 
     'all columns OK' );
ok( State->is_column('Rain'),         'is_column(), true' );
ok( State->is_column('rain'),         'is_column(), true, case insensitive' );
ok( !State->is_column('HGLAGAGlAG'),   'is_column(), false');
ok( State->can('_Rain_accessor'), '_accessor');
ok( State->can('_Snowfall_accessor'), '_accessor when override');
ok( !State->can('name') && !State->can('snowfall'), 'no normalized methods' );


