package Class::DBI::ColumnGrouper;

=head1 NAME

Class::DBI::ColumnGrouper - Columns and Column Groups

=head1 SYNOPSIS

	my $colg = Class::DBI::ColumnGrouper->new;
	   $colg->add_group(People => qw/star director producer/);

	my @cols = $colg->group_cols($group);
	my @groups = $colg->groups_for($column);

	my @all = $colg->all_columns;
	my $pri_col = $colg->primary;

	if ($colg->column_exists($column_name)) { ... }

=head1 DESCRIPTION

Each Class::DBI class maintains a list of its columns as class data.
This provides an interface to that. You probably don't want to be dealing
with this directly.

=head1 METHODS

=cut

use strict;

sub unique { my %seen; map { $seen{$_}++ ? () : $_ } @_; }

=head2 new

	my $colg = Class::DBI::ColumnGrouper->new;

A new blank ColumnnGrouper object.

=cut

sub new { 
	bless { 
		_groups => {}, 
		_cols   => {},
	}, shift;
}

sub clone {
	my ($class, $prev) = @_;
	bless { 
		_groups => { map { $_ => [ $prev->group_cols($_) ] } keys %{$prev->{_groups}} },
		_cols   => { map { $_ => { map { $_ => 1 } $prev->groups_for($_)  } } $prev->all_columns}
	}, $class;
}
	
=head2 add_group

	$colg->add_group(People => qw/star director producer/);

This adds a list of columns as a column group.

=cut

sub add_group {
	my ($self, $group, @cols) = @_;
	$self->add_group(Primary => $cols[0]) 
		if ($group eq "All" or $group eq "Essential") 
			and not $self->primary;
	$self->add_group(Essential => @cols) 
		if $group eq "All" and !$self->essential;
	@cols = unique($self->primary, @cols) if $group eq "Essential";
	$self->{_cols}->{$_}->{$group} = 1 foreach @cols;
	$self->{_groups}->{$group} = \@cols;
	$self;
}

=head2 group_cols

	my @colg = $cols->group_cols($group);

This returns a list of all columns which are in the given group.

=cut

sub group_cols {
	my ($self, $group) = @_;
	return $self->all_columns if $group eq "All";
	@{ $self->{_groups}->{$group} || [] }
}

=head2 groups_for

	my @groups = $colg->groups_for($column);

This returns a list of all groups of which the given column is a member.

=cut

sub groups_for {
	my ($self, $col) = @_;
	keys %{ $self->{_cols}->{$col} };
}

=head2 all_columns

	my @all = $colg->all_columns;

This returns a list of all columns.

=head2 primary

	my $pri_col = $colg->primary;

This returns the name of the primary key column.

=head2 essential

	my @essential_cols = $colg->essential;

This returns a list of the columns in the Essential group.

=cut


sub all_columns { keys %{+shift->{_cols}} }

sub primary { 
	my($primary) = shift->group_cols('Primary');
	return $primary;
}

sub essential { 
	my $self = shift; 
	my @cols = $self->group_cols('Essential');
	return @cols ? @cols : $self->all_columns;
}

=head2 column_exists

	if ($colg->column_exists($column_name)) { ... }
 
=cut

sub exists {
	my ($self, $col) = @_;
	exists $self->{_cols}->{$col};
}


1;