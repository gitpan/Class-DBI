use strict;
use Test::More tests => 30;

{
  local $SIG{__WARN__} = sub { like $_[0], qr/clashes with built-in method/, $_[0] };
  require './t/testlib/Film.pm';
  sub Class::DBI::sheep { ok 0; }

  require './t/testlib/Actor.pm';

  Film->create_movies_table;
  Actor->create_actors_table;
  Actor->hasa(Film => 'film');
}


sub Film::accessor_name {
	my ($class, $col) = @_;
	return "sheep" if lc $col eq "numexplodingsheep";
	return $col;
}

sub Actor::accessor_name {
	my ($class, $col) = @_;
	return "movie" if lc $col eq "film";
	return $col;
}

my $data = {
	Title       => 'Bad Taste',
	Director    => 'Peter Jackson',
	Rating      => 'R',
};

eval {
	local $data->{NumExplodingSheep} = 1;
	ok my $bt = Film->create($data), "Modified accessor - with column name";
	isa_ok $bt, "Film";
};
is $@, '', "No errors";

eval {
	local $data->{sheep} = 1;
	ok my $bt = Film->create($data), "Modified accessor - with accessor";
	isa_ok $bt, "Film";
};
is $@, '', "No errors";

{
	local *Film::mutator_name;
	local *Film::mutator_name =	sub {
		my ($class, $col) = @_;
		return "set_sheep" if lc $col eq "numexplodingsheep";
		return $col;
	};

	eval {
		local $data->{set_sheep} = 1;
		ok my $bt = Film->create($data), "Modified mutator - with mutator";
		isa_ok $bt, "Film";
	};
	is $@, '', "No errors";

	eval {
		local $data->{NumExplodingSheep} = 1;
		ok my $bt = Film->create($data), "Modified mutator - with column name";
		isa_ok $bt, "Film";
	};
	is $@, '', "No errors";

	eval {
		local $data->{sheep} = 1;
		ok my $bt = Film->create($data), "Modified mutator - with accessor";
		isa_ok $bt, "Film";
	};
	is $@, '', "No errors";

}

{
	my $p_data = {
		name  => 'Peter Jackson',
		film  => 'Bad Taste',
	};
	my $bt = Film->create($data);
	my $ac = Actor->create($p_data);

	eval { my $f = $ac->film };
	like $@, qr/Can't locate object method "film"/, "no hasa film";

	eval {
	  ok my $f = $ac->movie, "hasa movie";
		isa_ok $f, "Film";
		is $f->id, $bt->id, " - Bad Taste";
	};
	is $@, '', "No errors";

	{
		local $data->{Title} = "Another film";
		my $film = Film->create($data);

	  eval { $ac->film($film) };
		ok $@, $@;
		like $@, qr/Can't/, "Can't set via film()";

	  eval { $ac->movie($film) };
		ok $@, $@;
		like $@, qr/Can't/, "Can't set via movie()";

	  eval { 
		  ok $ac->set_film($film), "Set movie through hasa";
			$ac->commit;
	    ok my $f = $ac->movie, "hasa movie";
		  isa_ok $f, "Film";
		  is $f->id, $film->id, " - Another Film";
		};
		is $@, '', "No problem";
	}

}
