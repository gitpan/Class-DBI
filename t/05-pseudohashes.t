use strict;
use Test::More tests => 4;

# Test pseudohashes as objects.

package More::Film;

BEGIN {
  require './t/testlib/Film.pm';
  Film->CONSTRUCT;
}
use base qw(Film);

sub _init {
    my($class) = shift;
    no strict 'refs';
    my($self) = [\%{$class.'::FIELDS'}];
    $self->{__Changed} = {};
    return bless $self, $class;
}

package main;

ok( More::Film->table eq 'Movies',                      'phash table()'   );
ok( eq_array([More::Film->columns('Primary')], ['title']),   
                                                        'phash columns()' );
ok( More::Film->can('db_Main'),                         'phash set_db()'  );

eval {
  my $btaste = More::Film->retrieve('Bad Taste');
};

ok $@, $@;
