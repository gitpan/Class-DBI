use strict;
use Test::More tests => 26;
@YA::Film::ISA = 'Film';

BEGIN {
	require './t/testlib/Film.pm';
	require './t/testlib/Director.pm';
	Film->CONSTRUCT;
	Director->CONSTRUCT;
}
ok( my $btaste = Film->retrieve('Bad Taste'), "We have Bad Taste");
ok( my $pj = $btaste->Director, "Bad taste has a director");
ok( !ref($pj), ' ... which is not an object');

ok(Film->has_a('director' => 'Director'), "Link Director table");
ok( Director->create({ 
	Name       => 'Peter Jackson',
	Birthday   => -300000000,
	IsInsane   => 1
}), 'create Director' );

ok $btaste = Film->retrieve('Bad Taste'), "Reretrieve Bad Taste";
ok( $pj = $btaste->Director, "Bad taste now hasa() director");
ok( $pj->isa('Director'), ' ... which isa->Director');
is( $pj->id, 'Peter Jackson', ' ... and is the correct director');

# Oh no!  Its Peter Jacksons even twin, Skippy!  Born one minute after him.
my $sj = Director->create({ 
	Name       => 'Skippy Jackson',
	Birthday   => (-300000000 + 60),
	IsInsane   => 1,
});


{
	eval { $btaste->Director($btaste) };
	like $@, qr/is not a Director/, "Can't set film as director";
	is $btaste->Director->id, $pj->id, "PJ still the director";
}

is $sj->id, 'Skippy Jackson', 'Create new director - Skippy';
Film->has_a('codirector' => 'Director');
{
	eval { $btaste->CoDirector("Skippy Jackson") };
	is $@, "", "Auto inflates";
	isa_ok $btaste->CoDirector, "Director";
	is $btaste->CoDirector->id, $sj->id, "To skippy";
}

$btaste->CoDirector($sj);
$btaste->commit;
is( $btaste->CoDirector->Name, 'Skippy Jackson', 'He co-directed' );
is( $btaste->Director->Name, 'Peter Jackson', "Didnt interfere with each other" );

{ # Inheriting hasa
	my $btaste = YA::Film->retrieve('Bad Taste');
	is( ref($btaste->Director), 'Director', 'inheriting hasa()' );
	is( ref($btaste->CoDirector), 'Director', 'inheriting hasa()' );
	is( $btaste->CoDirector->Name, 'Skippy Jackson', ' ... correctly');
}

{ 
	$sj = Director->retrieve('Skippy Jackson');
	$pj = Director->retrieve('Peter Jackson');

	my $fail;
	eval { 
		$fail = YA::Film->create({ 
			Title          => 'Tastes Bad',
			Director       => $sj,
			codirector     => $btaste,
			Rating         => 'R',
			NumExplodingSheep => 23
		});
	};
	ok $@, "Can't have film as codirector: $@";
	is $fail, undef, "We didn't get anything";

	my $tastes_bad = YA::Film->create({ 
		Title          => 'Tastes Bad',
		Director       => $sj,
		codirector     => $pj,
		Rating         => 'R',
		NumExplodingSheep => 23
	});
	is( $tastes_bad->Director->Name, 'Skippy Jackson', 'Director' );
	is( $tastes_bad->_director_accessor->Name, 'Skippy Jackson', 'director_accessor');
	is( $tastes_bad->codirector->Name, 'Peter Jackson', 'codirector' );
	is( $tastes_bad->_codirector_accessor->Name, 'Peter Jackson', 'codirector_accessor' );
}
