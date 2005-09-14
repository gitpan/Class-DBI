package Class::DBI::SearchGenerator;

use strict;
use warnings;
use List::Util ();

=head1 NAME

Class::DBI::SearchGenerator - construct SQL for searches

=head1 DESCRIPTION

This module provides an interface for generating SQL for Class::DBI
searches. It provides methods for manipulating the column/value pairs
and other options passed to search() methods, and can give you back
either the resulting objects, or a raw sth for your processing.

=head1 CONSTRUCTOR

=head2 new

	my $generator = Class::DBI::SearchGenerator->new(
		$cdbi, $search_type, @args
	);

This constructs a new SearchGenerator object. $cdbi is the Class::DBI
subclass we will be serching, $search_type is the search keyword ("=",
"LIKE" etc), and @args are the options passed to search by the user.

=cut

sub new {
	my ($me, $cdbi, $search_type, @args) = @_;
	bless {
		cdbi => ref $cdbi || $cdbi,
		search_type => $search_type,
		args        => [@args],
	} => $me;
}

=head1 METHODS

=head2 results

	my @objects = $generator->results;
	my @iterator = $generator->results;

This will return the objects resulting from running the search.

=cut

sub results {
	my $self = shift;
	return $self->cdbi->sth_to_objects($self->sth,
		[ grep defined, $self->vals ]);
}

=head2 sth

This will return the raw statement handle suitable for manipulating
yourself, created by interpolating sql_fragment() into sql_Retrieve.

=cut

sub sth {
	my $self = shift;
	return $self->cdbi->sql_Retrieve($self->sql_fragment);
}

=head1 ACCESSORS

There are a variety of methods available for you to override or
manipulate if you are wanting to change the way searches work:

=head2 args 

	my @args = $generator->args;

This will return the key/value pairs passed to search, after stripping
off any options also passed. This is a list, rather than a hash, as you
may be passing multiple criteria on the same column.

=cut

sub args {
	my $self = shift;
	$self->{_processed_args} ||= do {
		my @args = @{ $self->{args} };
		@args = %{ $args[0] } if ref $args[0] eq "HASH";
		$self->{opts} = @args % 2 ? pop @args : {};
		[@args];
	};
}

=head2 option

	my $value = $generator->option("order_by");

Returns any value passed through for the given option.

=cut

sub option {
	my ($self, $opt) = @_;
	return $self->_opts->{$opt};
}

sub _opts {
	my $self = shift;
	my $null = $self->args unless $self->{_processed_args};
	$self->{opts};
}

=head2 cdbi

	my $class = $generator->cdbi;

The Class::DBI subclass which we are searching.

=cut

sub cdbi { shift->{cdbi} }

=head2 cols / vals

	my @cols = $generator->cols;
	my @vals = $generator->vals;

This provides two unzipped lists from the key/value pairs passed by the
user into the search() function. cols() returns a list of
Class::DBI::Column objects, and vals() returns a list of (deflated)
values. vals() may contain undefs for NULL searches.

=cut

sub cols {
	my $self = shift;
	$self->_unzip unless defined $self->{_cols};
	@{ $self->{_cols} };
}

sub vals {
	my $self = shift;
	$self->_unzip unless defined $self->{_vals};
	@{ $self->{_vals} };
}

sub _unzip {
	my $self  = shift;
	my @args  = @{ $self->args };
	my $class = $self->cdbi;
	my (@cols, @vals);
	while (my ($col, $val) = splice @args, 0, 2) {
		my $column = $class->find_column($col)
			|| (List::Util::first { $_->accessor eq $col } $class->columns)
			|| $class->_croak("$col is not a column of $class");
		push @cols, $column;
		push @vals, $class->_deflated_column($column, $val);
	}
	$self->{_cols} = \@cols;
	$self->{_vals} = \@vals;
}

=head2 sql_fragment

This returns the fragment of SQL that will be interpolated into
	SELECT __ESSENTIAL__
	  FROM __TABLE__
	 WHERE %s

=cut

sub sql_fragment {
	my $self = shift;
	my @cols = $self->cols;
	my @vals = $self->vals;
	my $frag =
		join " AND ", map defined($vals[$_])
		? "$cols[$_] $self->{search_type} ?"
		: "$cols[$_] IS NULL", 0 .. $#cols;
	return $frag unless my $order = $self->option('order_by');
	return "$frag ORDER BY $order";
}

1;
