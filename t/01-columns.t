use strict;
use Test::More tests => 26;

#-------------------------------------------------------------------------
package State;

use base 'Class::DBI';

State->table('State');
State->columns('Primary',   'Name');
State->columns('Essential', qw/Abbreviation/);
State->columns('Weather',   qw/Rain Snowfall/);
State->columns('Other',     qw/Capital Population/);

sub accessor_name { 
  my ($class, $column) = @_;
  my $return = $column eq "Rain" ? "Rainfall" : $column;
  return $return;
}

sub mutator_name { 
  my ($class, $column) = @_;
  my $return = $column eq "Rain" ? "set_Rainfall" : "set_$column";
  return "set_$column";
}

sub Snowfall { 1 }
#-------------------------------------------------------------------------
package CD;
use base 'Class::DBI';

CD->table('CD');
CD->columns('All' => qw/artist title length/);
#-------------------------------------------------------------------------

package main;

is (State->table, 'State', 'table()');
is (State->_primary, 'name', 'primary()');

ok eq_set(
     [State->columns('Primary')],   [qw/name/]
   ), 'Primary cols:' . join ", ", State->columns('Primary');
ok eq_set(
     [State->columns('Essential')], [qw/name abbreviation/]
   ), 'Essential cols:' . join ", ",  State->columns('Essential');
ok eq_set(
     [State->columns('All')], 
     [qw/name abbreviation rain snowfall capital population/]
   ), 'All cols:'. join ", ", State->columns('All');

is (CD->_primary, 'artist', 'primary()');
ok eq_set(
     [CD->columns('All')], [qw/artist title length/]
   ), 'All cols:'. join ", ", CD->columns('All');
ok eq_set(
     [CD->columns('Essential')], [qw/artist title length/]
   ), 'Essential cols:'. join ", ", CD->columns('Essential');
ok eq_set(
     [CD->columns('Primary')],   [qw/artist/]
   ), 'Primary cols:'. join ", ", CD->columns('Primary');


{ local $SIG{__WARN__} = sub { ok 1, "Error thrown" };
  ok (!State->columns('Nonsense'), "No Nonsense group");
}
ok( State->has_column('Rain'),        'has_column Rain');
ok( State->has_column('rain'),        'has_column rain');
ok( !State->has_column('HGLAGAGlAG'), '!has_column HGLAGAGlAG');
ok( State->is_column('capital'),      'is_column');

ok( !State->can('Rain'),               'No Rain accessor set up');
ok( State->can('Rainfall'),            'Rainfall accessor set up');
ok( State->can('_Rainfall_accessor'),      ' with correct alias');
ok( !State->can('_Rain_accessor'),      ' (not by colname)');
ok( !State->can('rain'),               ' (not normalized)');
ok( State->can('set_Rain'),           'overriden mutator');
ok( State->can('_set_Rain_accessor'), ' with alias');

ok( State->can('Snowfall'),               'overridden accessor set up');
ok( State->can('_Snowfall_accessor'),     ' with alias');
ok( !State->can('snowfall'),              ' (not normalized)');
ok( State->can('set_Snowfall'),           'overriden mutator');
ok( State->can('_set_Snowfall_accessor'), ' with alias');

