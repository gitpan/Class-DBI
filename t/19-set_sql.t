use strict;
use Test::More;

BEGIN {
	eval "use DBD::SQLite";
	plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 9);
}

INIT {
	use lib 't/testlib';
	use Film;
	Film->CONSTRUCT;
}

my $f1 = Film->create({ title => 'A', director => 'AA', rating => 'PG' });
my $f2 = Film->create({ title => 'B', director => 'BA', rating => 'PG' });
my $f3 = Film->create({ title => 'C', director => 'AA', rating => '15' });
my $f4 = Film->create({ title => 'D', director => 'BA', rating => '18' });
my $f5 = Film->create({ title => 'E', director => 'AA', rating => '18' });

Film->set_sql(
	pgs => qq{
	SELECT __ESSENTIAL__
	FROM   __TABLE__
	WHERE  __TABLE__.rating = 'PG'
	ORDER BY title DESC 
});

{
	(my $sth = Film->sql_pgs())->execute;
	my @pgs = Film->sth_to_objects($sth);
	is @pgs, 2, "Execute our own SQL";
	is $pgs[0]->id, $f2->id, "get F2";
	is $pgs[1]->id, $f1->id, "and F1";
}

{
	my @pgs = Film->search_pgs;
	is @pgs, 2, "SQL creates search() method";
	is $pgs[0]->id, $f2->id, "get F2";
	is $pgs[1]->id, $f1->id, "and F1";
};

Film->set_sql(
	rating => qq{
	SELECT __ESSENTIAL__
	FROM   __TABLE__
	WHERE  rating = ?
	ORDER BY title DESC 
});

{
	my @pgs = Film->search_rating('18');
	is @pgs, 2, "Can pass parameters to created search()";
	is $pgs[0]->id, $f5->id, "F5";
	is $pgs[1]->id, $f4->id, "and F4";
};

