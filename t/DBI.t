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
ok(1, 															'compile()'	);
######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):
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
BEGIN { $Total_tests = 21 }


package Film;
use base qw(Class::DBI);
use public qw( Title Director Rating NumExplodingSheep );

# Tell Class::DBI a little about yourself.
Film->table('Movies');
::ok( Film->table eq 'Movies',									'table()'	);

Film->columns('Primary', 'Title');
::ok( ::eqarray([Film->columns('Primary')], ['Title']),			'columns()'	);

die "For now, Class::DBI needs DBD::CSV in order to test properly."
  unless grep { $_ eq 'CSV' } DBI->available_drivers;
Film->set_db('Main', 'DBI:CSV:f_dir=testdb', undef, undef, {AutoCommit => 1});
::ok( Film->can('db_Main'),									'set_db()'	);

# Set up a table for ourselves.
Film->db_Main->do(<<"SQL");
CREATE TABLE Movies (
		 Title      VARCHAR(255),
         Director   VARCHAR(80),
         Rating     CHAR(5),
         NumExplodingSheep      INTEGER
)
SQL

# Clean up after ourselves.
END {
	Film->db_Main->do("DROP TABLE Movies");
}

# Create a new film entry for Bad Taste.
my $btaste = Film->new({ Title       => 'Bad Taste',
						 Director    => 'Peter Jackson',
						 Rating      => 'R',
						 NumExplodingSheep   => 1
					   });
::ok( defined $btaste and ref $btaste eq 'Film',				'new()'		);
::ok( $btaste->Title 		eq 'Bad Taste',					'Title() get' 	);
::ok( $btaste->Director 	eq 'Peter Jackson',			'Director() get'	);
::ok( $btaste->Rating		eq 'R',						'Rating() get'		);
::ok( $btaste->NumExplodingSheep == 1,			'NumExplodingSheep() get'	);


Film->new({ Title		=> 'Gone With The Wind',
			Director	=> 'Bob Baggadonuts',
			Rating		=> 'PG',
			NumExplodingSheep	=> 0
		  });

# Retrieve the 'Gone With The Wind' entry from the database.
my $gone = Film->retrieve('Gone With The Wind');
::ok( defined $gone and ref $gone eq 'Film',				'retrieve()'	);

# Shocking new footage found reveals bizarre Scarlet/sheep scene!
::ok( $gone->NumExplodingSheep == 0,	'NumExplodingSheep() get again'		);
$gone->NumExplodingSheep(5);
::ok( $gone->NumExplodingSheep == 5,	'NumExplodingSheep() set'			);
::ok( $gone->Rating eq 'PG',						'Rating() get again'	);
$gone->Rating('NC-17');
::ok( $gone->Rating eq 'NC-17',						'Rating() set'			);
$gone->commit;

# Grab the 'Bladerunner' entry.
Film->new({ Title		=> 'Bladerunner',
			Director	=> 'Bob Ridley Scott',
			Rating		=> 'R',
			NumExplodingSheep => 0,  # Exploding electric sheep?
		  });
my $blrunner = Film->retrieve('Bladerunner');
::ok( defined $blrunner and ref $blrunner eq 'Film',	'retrieve() again'	);
::ok( $blrunner->Title 		eq 'Bladerunner' 		and
	  $blrunner->Director	eq 'Bob Ridley Scott' 	and
	  $blrunner->Rating		eq 'R'					and
	  $blrunner->NumExplodingSheep == 0 );

# Make a copy of 'Bladerunner' and create an entry of the director's
# cut from it.
my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");
::ok( defined $blrunner_dc and ref $blrunner_dc eq 'Film' );
::ok( $blrunner_dc->Title 		eq "Bladerunner: Director's Cut" 	and
	  $blrunner_dc->Director	eq 'Bob Ridley Scott' 				and
	  $blrunner_dc->Rating		eq 'R'								and
	  $blrunner_dc->NumExplodingSheep == 0,						'copy()'	);


# Ishtar doesn't deserve an entry anymore.
Film->new( { Title => 'Ishtar' } );
Film->retrieve('Ishtar')->delete;
::ok( !Film->retrieve('Ishtar'),								'delete()'	);

# Find all films which have a rating of PG.
my @films = Film->search('Rating', 'PG');
::ok( @films == 1 and $films[0]->id eq $gone->id,				'search()'	);

# Find all films which were directed by Bob
@films = Film->search_like('Director', 'Bob %');
::ok( @films == 3 and 
	  ::eqarray([sort map { $_->id } @films], 
				[sort map { $_->id } $blrunner_dc, $gone, $blrunner]),
                                                          'search_like()'	);
