# $Id: DBI.t,v 1.9 2000/07/17 06:21:36 schwern Exp $
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)
use strict;

use vars qw($Total_tests);

my $loaded;
my $test_num;
BEGIN { $| = 1; $^W = 1; $test_num=1}
END {print "not ok $test_num\n" unless $loaded;}
print "1..$Total_tests\n";
use Class::DBI;
$loaded = 1;
ok(1,                                                           'compile()' );
######################### End of black magic.

# Utility testing functions.
sub ok {
    my($test, $name) = @_;
    print "not " unless $test;
    print "ok $test_num";
    print " - $name" if defined $name;
    print "\n";
    $test_num++;
}

sub eqarray  {
    my($a1, $a2) = @_;
    return 0 unless @$a1 == @$a2;
    my $ok = 1;
    for (0..$#{$a1}) { 
        unless($a1->[$_] eq $a2->[$_]) {
        $ok = 0;
        last;
        }
    }
    return $ok;
}

# Change this to your # of ok() calls + 1
BEGIN { $Total_tests = 48 }


package Film;
use base qw(Class::DBI);

# Test overriding.
sub HasVomit {
    my($self) = shift;
    $self->_HasVomit_accessor(@_);
}
::ok( Film->can('_HasVomit_accessor'),                          'overriding');

# Make sure a bug where methods with the normalized names keep popping up.
::ok( !Film->can('hasvomit') && !Film->can('title'),
                                                'normalized methods bug'    );

BEGIN {
    Film->columns('Essential', qw( Title ));
    Film->columns('Directors', qw( Director CoDirector ));
    Film->columns('Other',     qw( Rating NumExplodingSheep HasVomit ));
}

# Tell Class::DBI a little about yourself.
Film->table('Movies');
::ok( Film->table eq 'Movies',                                  'table()'   );

Film->columns('Primary', 'Title');
::ok( ::eqarray([Film->columns('Primary')], ['title']),         'columns()' );

# Find a test database to use.
my %dbi;
my @dbi_drivers = DBI->available_drivers;
my @drivers_we_like = grep /^CSV|RAM$/, @dbi_drivers;
if ( grep /^CSV$/, @drivers_we_like ) {      # We like DBD::CSV
     $dbi{'data src'}    = 'DBI:CSV:f_dir=testdb';
     $dbi{user}          = '';
     $dbi{password}      = '';
}
# DBD::RAM doesn't seem quite ready for this.
# elsif ( grep /^RAM$/, @drivers_we_like ) {      # We like DBD::RAM, too.
#     $dbi{'data src'}    = 'DBI:RAM:';
#     $dbi{user}          = '';
#     $dbi{password}      = '';
# }
else {
    my $old_fh = select(STDERR);
    print "\n";
    print "Class::DBI prefers DBD::CSV for testing but cannot find it.";
    print "Give me an alternate DBI data source: (",
          join(', ', map { "dbi:$_:<database name>" } @dbi_drivers), "):  ";
    $dbi{'data src'}    = <STDIN>;
    chomp $dbi{'data src'};
    print "A username to access this data source:  ";
    $dbi{'user'}        = <STDIN>;
    chomp $dbi{user};
    print "And a password:  ";
    $dbi{'password'}    = <STDIN>;
    chomp $dbi{password};

    select($old_fh);
}


Film->set_db('Main', @{dbi}{'data src', 'user', 'password'}, 
             {AutoCommit => 1});
::ok( Film->can('db_Main'),                                 'set_db()'  );

# Set up a table for ourselves.
Film->db_Main->do(<<"SQL");
CREATE TABLE Directors (
        name                    VARCHAR(80),
        birthday                INTEGER,
        isinsane                INTEGER
)
SQL

Film->db_Main->do(<<"SQL");
CREATE TABLE Movies (
        title                   VARCHAR(255),
        director                VARCHAR(80),
        codirector              VARCHAR(80),
        rating                  CHAR(5),
        numexplodingsheep       INTEGER,
        hasvomit                CHAR(1)
)
SQL

# Clean up after ourselves.
END {
    Film->db_Main->do("DROP TABLE Movies");
    Film->db_Main->do("DROP TABLE Directors");
}


package main;

# Create a new film entry for Bad Taste.
my $btaste = Film->new({ Title       => 'Bad Taste',
                         Director    => 'Peter Jackson',
                         Rating      => 'R',
                         NumExplodingSheep   => 1
                       });
::ok( defined $btaste and ref $btaste   eq 'Film',      'new()'     );
::ok( $btaste->Title            eq 'Bad Taste',     'Title() get'   );
::ok( $btaste->Director         eq 'Peter Jackson', 'Director() get'    );
::ok( $btaste->Rating           eq 'R',         'Rating() get'      );
::ok( $btaste->NumExplodingSheep == 1,              'NumExplodingSheep() get'   );


Film->new({ Title       => 'Gone With The Wind',
        Director        => 'Bob Baggadonuts',
        Rating      => 'PG',
        NumExplodingSheep   => 0
      });

# Retrieve the 'Gone With The Wind' entry from the database.
my $gone = Film->retrieve('Gone With The Wind');
::ok( defined $gone and ref $gone eq 'Film',                'retrieve()'    );

# Shocking new footage found reveals bizarre Scarlet/sheep scene!
::ok( $gone->NumExplodingSheep == 0,    'NumExplodingSheep() get again'     );
$gone->NumExplodingSheep(5);
::ok( $gone->NumExplodingSheep == 5,    'NumExplodingSheep() set'           );
::ok( $gone->Rating eq 'PG',                        'Rating() get again'    );
$gone->Rating('NC-17');
::ok( $gone->Rating eq 'NC-17',                     'Rating() set'          );
$gone->commit;

my $gone_copy = Film->retrieve('Gone With The Wind');
::ok( $gone->NumExplodingSheep == 5,                                'commit()'      );
::ok( $gone->Rating eq 'NC-17',                                 'commit() again'    );

# Grab the 'Bladerunner' entry.
Film->new({ Title       => 'Bladerunner',
            Director    => 'Bob Ridley Scott',
            Rating      => 'R',
            NumExplodingSheep => 0,  # Exploding electric sheep?
          });
my $blrunner = Film->retrieve('Bladerunner');
::ok( defined $blrunner and ref $blrunner eq 'Film',    'retrieve() again'  );
::ok( $blrunner->Title      eq 'Bladerunner'        and
      $blrunner->Director   eq 'Bob Ridley Scott'   and
      $blrunner->Rating     eq 'R'                  and
      $blrunner->NumExplodingSheep == 0 );

# Make a copy of 'Bladerunner' and create an entry of the director's
# cut from it.
my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");
::ok( defined $blrunner_dc and ref $blrunner_dc eq 'Film' );
::ok( $blrunner_dc->Title       eq "Bladerunner: Director's Cut"    and
      $blrunner_dc->Director    eq 'Bob Ridley Scott'               and
      $blrunner_dc->Rating      eq 'R'                              and
      $blrunner_dc->NumExplodingSheep == 0,                     'copy()'    );


# Ishtar doesn't deserve an entry anymore.
Film->new( { Title => 'Ishtar' } );
Film->retrieve('Ishtar')->delete;
::ok( !Film->retrieve('Ishtar'),                                'delete()'  );

# Find all films which have a rating of NC-17.
my @films = Film->search('Rating', 'NC-17');
::ok( @films == 1 and $films[0]->id eq $gone->id,               'search()'  );

# Find all films which were directed by Bob
@films = Film->search_like('Director', 'Bob %');
::ok( @films == 3 and 
      ::eqarray([sort map { $_->id } @films], 
                [sort map { $_->id } $blrunner_dc, $gone, $blrunner]),
                                                          'search_like()'   );

# Test that a disconnect doesn't harm anything.
Film->db_Main->disconnect;
@films = Film->search('Rating', 'NC-17');
::ok( @films == 1 and $films[0]->id eq $gone->id,               'auto reconnection'  );


# Test simple subclassing.
package Film::Threat;

use base qw(Film);


package main;

::ok( Film::Threat->db_Main->ping,               'subclass db_Main()' );
::ok( eqarray([sort Film::Threat->columns], [sort Film->columns]),
                                                 'subclass columns()' );

$btaste = Film::Threat->retrieve('Bad Taste');

::ok( defined $btaste and $btaste->isa('Film::Threat'),  'subclass new()' );
::ok( $btaste->Title    eq 'Bad Taste',                  'subclass get'   );

# Test rollback().
my $orig_director = $btaste->Director;
$btaste->Director('Lenny Bruce');
::ok( $btaste->Director eq 'Lenny Bruce' );
$btaste->rollback;
::ok( $btaste->Director eq $orig_director,               'rollback()'     );


# Test the laziness Class::DBI.
package Lazy;

use base qw(Class::DBI);

Lazy->set_db('Main', @{dbi}{'data src', 'user', 'password'}, 
             {AutoCommit => 1});
::ok( Lazy->can('db_Main'),                                 'set_db()'  );

Lazy->table("Lazy");


# Set up a table for ourselves.
Lazy->db_Main->do(<<"SQL");
CREATE TABLE Lazy (
    this INTEGER,
    that INTEGER,
    eep  INTEGER,
    orp  INTEGER,
    oop  INTEGER,
    opop INTEGER
)
SQL

# Clean up after ourselves.
END {
    Film->db_Main->do("DROP TABLE Lazy");
}

Lazy->columns('Primary', qw(this));
Lazy->columns('Essential', qw(this opop));
Lazy->columns('things', qw(this that));
Lazy->columns('horizon', qw(eep orp));
Lazy->columns('vertical', qw(oop opop));

package main;

::ok( eqarray([sort Lazy->columns('All')], 
              [sort qw(this that eep orp oop opop)]), 
                                                 'autogen columns("All")' );

Lazy->new({this => 1, that => 2, oop => 3, opop => 4, eep => 5});

my $obj = Lazy->retrieve(1);

::ok( exists $obj->{this} and exists $obj->{opop} and !exists $obj->{eep}
      and !exists $obj->{oop},                 'lazy' );

::ok( $obj->eep == 5 );
::ok( exists $obj->{eep} and exists $obj->{orp},     'proactive' );




# Test pseudohashes as objects.

package More::Film;

use base qw(Film);

sub _init {
    my($class) = shift;

    no strict 'refs';

    my($self) = [\%{$class.'::FIELDS'}];
    
    $self->{__Changed} = {};

    return bless $self, $class;
}

::ok( More::Film->table eq 'Movies',                      'phash table()'   );
::ok( ::eqarray([More::Film->columns('Primary')], ['title']),   
                                                          'phash columns()' );
::ok( More::Film->can('db_Main'),                         'phash set_db()'  );

$btaste = More::Film->retrieve('Bad Taste');

::ok( defined $btaste and $btaste->isa('More::Film'),    'phash new()' );
::ok( $btaste->Title    eq 'Bad Taste',                  'phash get'   );


package Film::Directors;

use base qw(Class::DBI);
Film::Directors->set_db('Main', @{dbi}{'data src', 'user', 'password'}, 
                        {AutoCommit => 1});
::ok( Film::Directors->can('db_Main'),                        'set_db()'  );

Film::Directors->columns(All     => qw(Name Birthday IsInsane));
Film::Directors->columns(Primary => 'Name');
Film::Directors->table('Directors');

::ok( Film::Directors->new({ Name       => 'Peter Jackson',
                             Birthday   => -300000000,
                             IsInsane   => 1
                           }) );

Film->hasa('Film::Directors' => 'Director');
Film->hasa('Film::Directors' => 'CoDirector');
$btaste = Film->retrieve('Bad Taste');

my $pj = $btaste->Director;
::ok( defined $pj and 
      $pj->isa('Film::Directors') and 
      $pj->id eq 'Peter Jackson' );

# Oh no!  Its Peter Jackson's even twin, Skippy!  Born one minute after him.
my $sj = Film::Directors->new({ Name       => 'Skippy Jackson',
                                Birthday   => (-300000000 + 60),
                                IsInsane   => 1
                              });
::ok( defined $sj and $sj->id eq 'Skippy Jackson' );
$btaste->CoDirector($sj);
$btaste->commit;
::ok( $btaste->CoDirector->Name eq 'Skippy Jackson' );

# Make sure they didn't interfere with each other.
::ok( $btaste->Director->Name   eq 'Peter Jackson' );

