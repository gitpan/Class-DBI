use strict;
use Test::More tests => 66;

$|=1;
require './t/testlib/Film.pm';
ok Film->CONSTRUCT, "Construct Film table";

ok( Film->can('db_Main'), 'set_db()'  );

{
  my $nul = Film->retrieve();
  is $nul, undef, "Can't retrieve nothing";
}

{
	eval { my $id = Film->id };
	like $@, qr/class method/, "Can't get id with no object";
}

{
	eval { my $id = Film->title };
	like $@, qr/class method/, "Can't get title with no object";
}

eval { my $duh = Film->create; };
like $@, qr/create nothing/, "Can't create nothing";

my $btaste = Film->retrieve('Bad Taste');
isa_ok $btaste, 'Film';
is( $btaste->Title, 'Bad Taste', 'Title() get'   );
is( $btaste->Director, 'Peter Jackson', 'Director() get'    );
is( $btaste->Rating, 'R', 'Rating() get'      );
is( $btaste->NumExplodingSheep, 1, 'NumExplodingSheep() get'   );

{
	my $bt2 = Film->find_or_create( Title => 'Bad Taste' );
	is $bt2->Director, $btaste->Director, "find_or_create";
	my @bt = Film->search(Title => 'Bad Taste');
	is @bt, 1, " doesn't create a new one";
}

ok my $gone = Film->find_or_create({
	Title              => 'Gone With The Wind',
	Director           => 'Bob Baggadonuts',
	Rating             => 'PG',
	NumExplodingSheep  => 0
}), "Add Gone With The Wind";
isa_ok $gone, 'Film';
ok $gone = Film->retrieve('Gone With The Wind'), "Fetch it back again";
isa_ok $gone, 'Film';

# Shocking new footage found reveals bizarre Scarlet/sheep scene!
is( $gone->NumExplodingSheep, 0,    'NumExplodingSheep() get again'     );
$gone->NumExplodingSheep(5);
is( $gone->NumExplodingSheep, 5,    'NumExplodingSheep() set'           );
is( $gone->numexplodingsheep, 5,    'numexplodingsheep() set'           );

is( $gone->Rating, 'PG', 'Rating() get again'    );
$gone->Rating('NC-17');
is( $gone->Rating, 'NC-17', 'Rating() set'          );
$gone->commit;

{
  my @films = eval { Film->retrieve_all };
  is (@films, 2, "We have 2 films in total");
}

my $gone_copy = Film->retrieve('Gone With The Wind');
ok( $gone->NumExplodingSheep == 5,  'commit()'      );
ok( $gone->Rating eq 'NC-17',       'commit() again'    );

# Grab the 'Bladerunner' entry.
Film->create({ Title       => 'Bladerunner',
               Director    => 'Bob Ridley Scott',
               Rating      => 'R',
               NumExplodingSheep => 0,  # Exploding electric sheep?
             });

my $blrunner = Film->retrieve('Bladerunner');
is( ref $blrunner, 'Film',    'retrieve() again'  );
is $blrunner->Title, 'Bladerunner', "Correct title";
is $blrunner->Director, 'Bob Ridley Scott', " and Director";
is $blrunner->Rating, 'R', " and Rating";
is $blrunner->NumExplodingSheep, 0, " and sheep";

# Make a copy of 'Bladerunner' and create an entry of the directors cut
my $blrunner_dc = $blrunner->copy({
  title => "Bladerunner: Director's Cut",
  rating => "15",
});
is( ref $blrunner_dc, 'Film', "copy() produces a film" );
is( $blrunner_dc->Title, "Bladerunner: Director's Cut", 'Title correct');
is( $blrunner_dc->Director, 'Bob Ridley Scott', 'Director correct');
is( $blrunner_dc->Rating, '15', 'Rating correct');
is( $blrunner_dc->NumExplodingSheep, 0, 'Sheep correct');

# Set up own SQL:
{
  Film->add_constructor(title_asc => "title LIKE ? ORDER BY title");
  Film->add_constructor(title_desc => "title LIKE ? ORDER BY title DESC");

  {
    my @films = Film->title_asc("Bladerunner%");
    is @films, 2, "We have 2 Bladerunners";
    is $films[0]->Title, $blrunner->Title, "Ordered correctly";
  }
  {
    my @films = Film->title_desc("Bladerunner%");
    is @films, 2, "We have 2 Bladerunners";
    is $films[0]->Title, $blrunner_dc->Title, "Ordered correctly";
  }
}

# Multi-column search
{
  my @films = $blrunner->search_like(title => "Bladerunner%", rating => '15');
  is @films, 1, "Only one Bladerunner is a 15";
}

# Inline SQL
{
  my @films = Film->retrieve_from_sql(qq{
    numexplodingsheep > 0
    ORDER BY title 
  });
  is @films, 2, "Inline SQL";
  is $films[0]->id, $btaste->id, "Correct film";
  is $films[1]->id, $gone->id, "Correct film";
}

{
  # Ishtar doesnt deserve an entry anymore.
  my $ishtar = Film->create( { Title => 'Ishtar' } );
  ok( Film->retrieve('Ishtar'), 'Ishtar created');
  $ishtar->delete;
  ok( !Film->retrieve('Ishtar'), 'Ishtar deleted'  );
}

# Find all films which have a rating of NC-17.
my @films = Film->search('Rating', 'NC-17');
is( scalar @films, 1, ' search returns one film');
is( $films[0]->id, $gone->id, ' ... the correct one');

# Find all films which were directed by Bob
@films = Film->search_like('Director', 'Bob %');
is( scalar @films, 3, ' search_like returns 3 films');
ok( eq_array([sort map { $_->id } @films], 
             [sort map { $_->id } $blrunner_dc, $gone, $blrunner]),
    'the correct ones'   );

# Test that a disconnect doesnt harm anything.
Film->db_Main->disconnect;
@films = Film->search({ Rating => 'NC-17' });
ok( @films == 1 && $films[0]->id eq $gone->id, 'auto reconnection'  );

# Test rollback().
my $orig_director = $btaste->Director;
$btaste->Director('Lenny Bruce');
is( $btaste->Director, 'Lenny Bruce', 'set new Director' );
$btaste->rollback;
is( $btaste->Director, $orig_director, 'rollback()'     );

{
	Film->autocommit(1);
	my $btaste2 = Film->retrieve($btaste->id);
	$btaste->NumExplodingSheep(18);
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_; };
	{
		my $btaste3 = Film->retrieve($btaste->id);
		is $btaste3->NumExplodingSheep, 18, "Class based AutoCommit";
		$btaste3->autocommit(0); # obj a/c should override class a/c
		is @warnings, 0, "No warnings so far";
		$btaste3->NumExplodingSheep(13);
	}
	is @warnings, 1, "DESTROY without commit warns";
	Film->autocommit(0);
}

{
	$btaste->autocommit(1);
	$btaste->NumExplodingSheep(32);
	my $btaste2 = Film->retrieve($btaste->id);
	is $btaste2->NumExplodingSheep, 32, "Object based AutoCommit";
	$btaste->autocommit(0);
}

# Primary key of 0
{ 
	ok my $zero = Film->create({ Title => 0, Rating => "U" }), "Create 0";
	ok my $ret = Film->retrieve(0), "Retrieve 0";
	is $ret->Title, 0, "Title OK";
	is $ret->Rating, "U", "Rating OK";
}

# Make sure that we can have other accessors. (Bugfix in 0.28)
{ 
  Film->mk_accessors(qw/temp1 temp2/);
  my $blrunner = Film->retrieve('Bladerunner');
  $blrunner->temp1("Foo");
  $blrunner->NumExplodingSheep(2);
  eval { $blrunner->commit };
  ok(!$@, "Other accessors");
}

{
  {
    ok my $byebye = DeletingFilm->create({ 
      Title       => 'Goodbye Norma Jean',
      Rating      => 'PG',
    }), "Add a deleting Film";

    isa_ok $byebye, 'DeletingFilm';
    isa_ok $byebye, 'Film';
    ok Film->retrieve('Goodbye Norma Jean'), "Fetch it back again";
  }
  my $film;
  eval { $film = Film->retrieve('Goodbye Norma Jean') };
  ok !$film, "It destroys itself";
}

