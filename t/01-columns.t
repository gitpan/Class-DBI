use strict;
use Test::More tests => 16;

#-------------------------------------------------------------------------
package State;

use base qw(Class::DBI);

State->table('State');
State->columns('Primary',   'Name');
State->columns('Essential', qw( Name Abbreviation ));
State->columns('Weather',   qw( Rain Snowfall ));
State->columns('Other',     qw( Capital Population ));

sub mutator_name { 
  my ($class, $column) = @_;
  return "set_$column";
}

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

ok( State->can('Rain'),               'accessor set up');
ok( State->can('_Rain_accessor'),     ' with alias');
ok( !State->can('rain'),              ' (not normalized)');
ok( State->can('set_Rain'),           'overriden mutator');
ok( State->can('_set_Rain_accessor'), ' with alias');

ok( State->can('Snowfall'),               'overridden accessor set up');
ok( State->can('_Snowfall_accessor'),     ' with alias');
ok( !State->can('snowfall'),              ' (not normalized)');
ok( State->can('set_Snowfall'),           'overriden mutator');
ok( State->can('_set_Snowfall_accessor'), ' with alias');


