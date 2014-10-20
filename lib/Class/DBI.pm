package Class::DBI::__::Base;

require 5.00502;

use Class::Trigger 0.07;
use base qw(Class::Accessor Class::Data::Inheritable Ima::DBI);

package Class::DBI;

use strict;

use base "Class::DBI::__::Base";

use vars qw($VERSION);
$VERSION = '0.92';

use Class::DBI::ColumnGrouper;
use Class::DBI::Query;
use Carp ();

use overload
	'""' => sub { $_[0]->{ $_[0]->primary_column } },
	bool => sub { defined $_[0]->{ $_[0]->primary_column } },
	fallback => 1;

{
	my %deprecated = (
		croak            => "_croak",
		carp             => "_carp",
		min              => "minimum_value_of",
		max              => "maximum_value_of",
		normalize_one    => "_normalize_one",
		_primary         => "primary_column",
		primary          => "primary_column",
		primary_key      => "primary_column",
		essential        => "_essential",
		column_type      => "has_a",
		associated_class => "has_a",
		is_column        => "has_column",
		add_hook         => "add_trigger",
		run_sql          => "retrieve_from_sql",
		rollback         => "discard_changes",
		commit           => "update",
		autocommit       => "autoupdate",
		_commit_vals     => '_update_vals',
		_commit_line     => '_update_line',
	);

	no strict 'refs';
	while (my ($old, $new) = each %deprecated) {
		*$old = sub {
			my @caller = caller;
			warn
				"Use of '$old' is deprecated at $caller[1] line $caller[2]. Use '$new' instead\n";
			goto &$new;
			}
	}
}

#----------------------------------------------------------------------
# Our Class Data
#----------------------------------------------------------------------
__PACKAGE__->mk_classdata('__AutoCommit');
__PACKAGE__->mk_classdata('__hasa_list');
__PACKAGE__->mk_classdata('_table');
__PACKAGE__->mk_classdata('_table_alias');
__PACKAGE__->mk_classdata('sequence');
__PACKAGE__->mk_classdata('__columns');
__PACKAGE__->mk_classdata('__data_type');
__PACKAGE__->mk_classdata('iterator_class');
__PACKAGE__->iterator_class('Class::DBI::Iterator');
__PACKAGE__->__columns(Class::DBI::ColumnGrouper->new());
__PACKAGE__->__data_type({});

#----------------------------------------------------------------------
# SQL we'll need
#----------------------------------------------------------------------
__PACKAGE__->set_sql('MakeNewObj', <<'');
INSERT INTO %s (%s)
VALUES (%s)

__PACKAGE__->set_sql('Flesh', <<'');
SELECT %s
FROM   %s
WHERE  %s = ?

__PACKAGE__->set_sql('update', <<"");
UPDATE %s
SET    %s
WHERE  %s = ?

__PACKAGE__->set_sql('DeleteMe', <<"");
DELETE
FROM   %s
WHERE  %s = ?

__PACKAGE__->set_sql('Nextval', <<'');
SELECT NEXTVAL ('%s')

__PACKAGE__->set_sql('SearchSQL', <<'');
SELECT %s
FROM   %s
WHERE  %s

__PACKAGE__->set_sql(single => <<'');
SELECT %s
FROM   %s


#----------------------------------------------------------------------
# EXCEPTIONS
#----------------------------------------------------------------------

sub _carp {
	my ($self, $msg) = @_;
	Carp::carp($msg || $self);
	return;
}

sub _croak {
	my ($self, $msg) = @_;
	Carp::croak($msg || $self);
	return;
}

#----------------------------------------------------------------------
# SET UP
#----------------------------------------------------------------------

{
	my %Per_DB_Attr_Defaults = (
		pg     => { AutoCommit => 0 },
		oracle => { AutoCommit => 0 },
	);

	sub set_db {
		my ($class, $db_name, $data_source, $user, $password, $attr) = @_;

		# 'dbi:Pg:dbname=foo' we want 'Pg'. I think this is enough.
		my ($driver) = $data_source =~ /^dbi:(\w+?)/i;

		# Combine the user's attributes with our defaults.
		$attr = {
			FetchHashKeyName   => 'NAME_lc',
			ShowErrorStatement => 1,
			AutoCommit         => 1,
			ChopBlanks         => 1,
			%{ $Per_DB_Attr_Defaults{ lc $driver } || {} },
			%{ $attr || {} },
		};

		$class->_carp("Your database name should be 'Main'")
			unless $db_name eq "Main";

		$class->SUPER::set_db('Main', $data_source, $user, $password, $attr);
	}
}

sub table {
	my ($proto, $table, $alias) = @_;
	my $class = ref $proto || $proto;
	$class->_table($table)      if $table;
	$class->table_alias($alias) if $alias;
	return $class->_table || $class->_table($class->table_alias);
}

sub table_alias {
	my ($proto, $alias) = @_;
	my $class = ref $proto || $proto;
	$class->_table_alias($alias) if $alias;
	return $class->_table_alias || $class->_table_alias($class->_class_name);
}

sub _class_name {
	my $proto = shift;
	my $class = ref $proto || $proto;
	my @parts = split /::/, $class;
	return lc pop @parts;
}

sub columns {
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $group = shift || "All";
	return $class->_set_columns($group => @_) if @_;
	return $class->all_columns    if $group eq "All";
	return $class->primary_column if $group eq "Primary";
	return $class->_essential     if $group eq "Essential";
	return $class->__columns->group_cols($group);
}

sub _set_columns {
	my ($class, $group, @columns) = @_;
	my @cols = $class->_normalized(@columns);

	# Careful to take copy
	$class->__columns(Class::DBI::ColumnGrouper->clone($class->__columns)
			->add_group($group => @cols));
	$class->_mk_column_accessors(@columns);
	return @cols;
}

sub all_columns { shift->__columns->all_columns }

sub id { my $self = shift; $self->get($self->primary_column) }

sub primary_column { shift->__columns->primary }

sub _essential { shift->__columns->essential }

sub has_column {
	my ($class, $want) = @_;
	return $class->__columns->exists($class->_normalized($want));
}

sub has_real_column {    # is really in the database
	my ($class, $want) = @_;
	return $class->__columns->in_database($class->_normalized($want));
}

sub _check_columns {
	my ($class, @cols) = @_;
	$class->has_column($_)
		or return $class->_croak("$_ is not a column of $class") for @cols;
	return 1;
}

sub _groups2cols {
	my ($self, @groups) = @_;
	return $self->_unique_entries(map $self->columns($_), @groups);
}

sub _cols2groups {
	my ($self, @cols) = @_;
	my $colg = $self->__columns;
	my %found = map { $_ => 1 } map $colg->groups_for($_), @cols;
	return $self->_croak("@cols not in any groups") unless keys %found;
	return keys %found;
}

sub data_type {
	my $class    = shift;
	my %datatype = @_;
	while (my ($col, $type) = each %datatype) {
		$class->_add_data_type($col, $type);
	}
}

sub _add_data_type {
	my ($class, $col, $type) = @_;
	my $datatype = $class->__data_type;
	$datatype->{$col} = $type;
	$class->__data_type($datatype);
}

# Make a set of accessors for each of a list of columns. We construct
# the method name by calling accessor_name() and mutator_name() with the
# normalized column name.

# mutator_name will be the same as accessor_name unless you override it.

# If both the accessor and mutator are to have the same method name,
# (which will always be true unless you override mutator_name), a read-write
# method is constructed for it. If they differ we create both a read-only
# accessor and a write-only mutator.

sub _mk_column_accessors {
	my ($class, @columns) = @_;

	my %norm;
	@norm{@columns} = $class->_normalized(@columns);

	foreach my $col (@columns) {
		my %method = (
			ro => $class->accessor_name($col),
			wo => $class->mutator_name($col)
		);
		my $both = ($method{ro} eq $method{wo});
		foreach my $type (keys %method) {
			my $method   = $method{$type};
			my $maker    = $both ? "make_accessor" : "make_${type}_accessor";
			my $accessor = $class->$maker($norm{$col});
			my $alias    = "_${method}_accessor";
			$class->_make_method($_, $accessor) for ($method, $alias);
		}
	}
}

sub _make_method {
	my ($class, $name, $method) = @_;
	return if defined &{"$class\::$name"};
	$class->_carp("Column '$name' in $class clashes with built-in method")
		if defined &{"Class::DBI::$name"}
		and not($name eq "id" and $class->primary_column eq "id");
	no strict 'refs';
	*{"$class\::$name"} = $method;
	return unless (my $norm = $class->_normalized($name)) ne $name;
	$class->_make_method($norm => $method);
}

sub accessor_name {
	my ($class, $column) = @_;
	return $column;
}

sub mutator_name {
	my ($class, $column) = @_;
	return $class->accessor_name($column);
}

sub autoupdate {
	my $proto = shift;
	ref $proto ? $proto->_obj_autoupdate(@_) : $proto->_class_autoupdate(@_);
}

sub _obj_autoupdate {
	my ($self, $set) = @_;
	my $class = ref $self;
	$self->{__AutoCommit} = $set if defined $set;
	defined $self->{__AutoCommit}
		? $self->{__AutoCommit}
		: $class->_class_autoupdate;
}

sub _class_autoupdate {
	my ($class, $set) = @_;
	$class->__AutoCommit($set) if defined $set;
	return $class->__AutoCommit;
}

sub find_or_create {
	my $class = shift;
	my $hash = ref $_[0] eq "HASH" ? shift: {@_};
	my ($exists) = $class->search(%$hash);
	return defined($exists) ? $exists : $class->create($hash);
}

sub create {
	my $class = shift;
	my $info  = shift;
	return $class->_croak("create needs a hashref") unless ref $info eq 'HASH';
	my @cols = $class->all_columns;
	my $colmap = {};    # XX could be cached for performance improvement

	foreach my $col (@cols) {
		my $mutator  = $class->mutator_name($col);
		my $accessor = $class->accessor_name($col);
		$colmap->{$mutator}  = $col if $mutator  ne $col;
		$colmap->{$accessor} = $col if $accessor ne $col;
	}

	$class->normalize_hash($info);    # column names
	foreach my $key (keys %$info) {
		my $col = $colmap->{$key} or next;
		$info->{$col} = delete $info->{$key};
	}
	$class->normalize_column_values($info);
	$class->validate_column_values($info);

	return $class->_create($info);
}

sub _create {
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $data  = shift;

	$class->normalize_hash($data);    # normalize column names
	$class->_check_columns(keys %$data);

	my $primary = $class->primary_column;
	$data->{$primary} ||= $class->_next_in_sequence if $class->sequence;

	# Build dummy object, flesh it out, and call trigger
	my $self = $class->_init;
	@{$self}{ keys %$data } = values %$data;
	$self->call_trigger('before_create');

	# Reinstate data : TODO make _insert_row operate on object, not $data
	my ($real, $temp) = ({}, {});
	foreach my $col (grep exists $self->{$_}, $self->all_columns) {
		($class->has_real_column($col) ? $real : $temp)->{$col} = $self->{$col};
	}
	$self->_insert_row($real);
	$self->{$primary} = $real->{$primary};

	my @discard_columns = grep $_ ne $primary, keys %$real;
	$self->call_trigger('after_create', discard_columns => \@discard_columns);
	$self->call_trigger('create');    # For historic reasons...

	# Empty everything back out again!
	delete $self->{$_} for @discard_columns;
	return $self;
}

sub _find_primary_value {
	my ($self, $sth) = @_;
	$sth->execute;
	my $val = ($sth->fetchrow_array)[0];
	$sth->finish;
	return $val;
}

sub _next_in_sequence {
	my $self = shift;
	return $self->_find_primary_value($self->sql_Nextval($self->sequence));
}

sub _auto_increment_value {
	my $self = shift;
	my $dbh  = $self->db_Main;

	# the DBI will provide a standard attribute soon, meanwhile...
	my $id = $dbh->{mysql_insertid}    # mysql
		|| eval { $dbh->func('last_insert_rowid') };    # SQLite
	$self->_croak("Can't get last insert id") unless defined $id;
	return $id;
}

sub _insert_row {
	my $self = shift;
	my $data = shift;
	eval {
		my @columns = keys %$data;
		my $sth     = $self->sql_MakeNewObj(
			$self->table,
			join (', ', @columns),
			join (', ', map $self->_column_placeholder($_), @columns),
		);
		$self->_bind_param($sth, \@columns);
		$sth->execute(values %$data);
		my $primary_column = $self->primary_column;
		$data->{$primary_column} = $self->_auto_increment_value
			unless defined $data->{$primary_column};
	};
	if ($@) {
		my $class = ref $self;
		return $self->_croak(
			"Can't insert new $class: $@",
			err    => $@,
			method => 'create'
		);
	}
	return 1;
}

sub _bind_param {
	my ($class, $sth, $keys) = @_;
	my $datatype = $class->__data_type or return;
	for my $i (0 .. $#$keys) {
		if (my $type = $datatype->{ $keys->[$i] }) {
			$sth->bind_param($i + 1, undef, $type);
		}
	}
}

sub new { my $proto = shift; $proto->create(@_); }
sub _init { bless {}, shift; }

sub retrieve {
	my $class = shift;
	my $id    = shift;
	return unless defined $id;
	return $class->_croak("Can't retrieve a reference") if ref($id);
	my @rows = $class->search($class->primary_column => $id);
	return $rows[0];
}

# Get the data, as a hash, but setting certain values to whatever
# we pass. Used by copy() and move().
# This can take either a primary key, or a hashref of all the columns
# to change.
sub _data_hash {
	my $self    = shift;
	my @columns = $self->all_columns;
	my %data;
	@data{@columns} = $self->get(@columns);
	my $primary_column = $self->primary_column;
	delete $data{$primary_column};
	if (@_) {
		my $arg = shift;
		my %arg = ref($arg) ? %$arg : ($primary_column => $arg);
		@data{ keys %arg } = values %arg;
	}
	return \%data;
}

sub copy {
	my $self = shift;
	return $self->create($self->_data_hash(@_));
}

#----------------------------------------------------------------------
# CONSTRUCT
#----------------------------------------------------------------------

sub construct {
	my ($proto, $data) = @_;
	my $class = ref $proto || $proto;
	return $class->_croak("construct() is a protected method of Class::DBI")
		unless caller->isa("Class::DBI") || caller->isa("Class::DBI::Iterator");

	my @wantcols = $class->_normalized(keys %$data);
	my $self     = $class->_init;
	@{$self}{@wantcols} = values %$data;
	$self->call_trigger('select');
	return $self;
}

sub move {
	my $class   = shift;
	my $old_obj = shift;
	return $old_obj->_croak("Can't move to an unrelated class")
		unless $class->isa(ref $old_obj)
		or $old_obj->isa($class);
	return $class->create($old_obj->_data_hash(@_));
}

sub delete {
	my $self = shift;
	return $self->_search_delete(@_) if not ref $self;
	$self->call_trigger('before_delete');
	$self->call_trigger('delete');    # For historic reasons...
	$self->_cascade_delete;
	eval {
		my $sth = $self->sql_DeleteMe($self->table, $self->primary_column);
		$sth->execute($self->id);
	};
	if ($@) {
		return $self->_croak(
			"Can't delete " . ref($self) . " " . $self->id . ": $@",
			err => $@);
	}
	$self->call_trigger('after_delete');
	undef %$self;
	bless $self, 'Class::Deleted';
	return 1;
}

sub _search_delete {
	my ($class, @args) = @_;
	my $it = $class->search_like(@args);
	while (my $obj = $it->next) { $obj->delete }
	return 1;
}

sub _cascade_delete {
	my $self    = shift;
	my $class   = ref($self);
	my %cascade = %{ $class->__hasa_list || {} };
	foreach my $remote (keys %cascade) {
		$_->delete foreach $remote->search($cascade{$remote} => $self->id);
	}
}

# Return the placeholder to be used in UPDATE and INSERT queries. Usually
# you'll want this just to return '?', as per the default. However, this
# lets you set, for example, that a column should always be CURDATE()
# [MySQL doesn't allow this as a DEFAULT value] by subclassing:
#
# sub _column_placeholder {
#   my ($self, $column) = @_;
#   if ($column eq "entry_date") {
#     return "IF(1, CURDATE(), ?)";
#   }
#   return "?";
# }

sub _column_placeholder { '?' }

sub update {
	my $self  = shift;
	my $class = ref($self)
		or return $self->_croak("Can't call update as a class method");

	$self->call_trigger('before_update');
	if (my @changed_cols = $self->is_changed) {
		my $sth =
			$self->sql_update($self->table, $self->_update_line,
			$self->primary_column);
		$class->_bind_param($sth, [ $self->is_changed ]);
		my $rows = eval { $sth->execute($self->_update_vals, $self->id); };
		if ($@) {
			return $self->_croak(
				"Can't update " . ref($self) . " " . $self->id . ": $@",
				err => $@);
		}

		# enable this once new fixed DBD::SQLite is released:
		if (0 and $rows != 1) {    # should always only update one row
			my $msg_prefix = "Can't update $class (" . $self->id . ")";
			$self->_croak("$msg_prefix: row not found") if $rows == 0;
			$self->_croak("$msg_prefix: updated more than one row");
		}

		$self->call_trigger('after_update', discard_columns => \@changed_cols);

		# delete columns that changed (in case adding to DB modifies them again)
		delete $self->{$_} for @changed_cols;
		delete $self->{__Changed};
	}
	return 1;
}

sub _update_line {
	my $self = shift;
	join (', ', map "$_ = " . $self->_column_placeholder($_),
		$self->is_changed);
}

sub _update_vals {
	my $self = shift;
	map $self->{$_}, $self->is_changed;
}

sub DESTROY {
	my ($self) = shift;
	if (my @changed = $self->is_changed) {
		my ($class, $id) = (ref $self, $self->{ $self->primary_column });
		$self->_carp("$class $id destroyed without saving changes to "
				. join (', ', @changed));
	}
}

sub discard_changes {
	my $self = shift;
	return $self->_croak("Can't discard_changes while autoupdate is on")
		if $self->autoupdate;
	delete $self->{$_} foreach $self->is_changed;
	delete $self->{__Changed};
	return 1;
}

# We override the get() method from Class::Accessor to fetch the data for
# the column (and associated) columns from the database, using the _flesh()
# method. We also allow get to be called with a list of keys, instead of
# just one.

sub get {
	my ($self, @keys) = @_;
	return $self->_croak("Can't fetch data as class method") unless ref $self;
	return $self->_croak("Can't get() nothing!")             unless @keys;

	if (my @fetch_cols = grep !exists $self->{$_}, @keys) {
		$self->_flesh($self->_cols2groups(@fetch_cols));
	}

	return $self->{ $keys[0] } if @keys == 1;
	return @{$self}{@keys};
}

sub _flesh {
	my ($self, @groups) = @_;
	my @real_groups = grep $_ ne "TEMP", @groups;
	my @want = grep !exists $self->{$_}, $self->_groups2cols(@real_groups);
	if (@want) {
		my $id = $self->{ $self->primary_column };
		$self->_croak("Can't flesh an object with no primary key")
			unless defined $id;
		my $sth = $self->_run_query('Flesh', $self->primary_column, $id, \@want);
		my $row = $sth->fetchrow_arrayref
			or $self->_croak("Can't fetch extra columns for " . $self->id);
		$sth->finish;
		@{$self}{@want} = @$row;
		$self->call_trigger('select');
	}
	return 1;
}

# We also override set() from Class::Accessor so we can keep track of
# changes, and either write to the database now (if autoupdate is on),
# or when update() is called.
sub set {
	my $self          = shift;
	my $column_values = {@_};

	$self->normalize_column_values($column_values);
	$self->validate_column_values($column_values);

	while (my ($column, $value) = each %$column_values) {
		$self->SUPER::set($column, $value);

		# We increment instead of setting to 1 because it might be useful to
		# someone to know how many times a value has changed between updates.
		$self->{__Changed}{$column}++ if $self->has_real_column($column);
		eval { $self->call_trigger("after_set_$column") };    # eg inflate
		if ($@) {
			delete $self->{$column};
			return $self->_croak("after_set_$column trigger error: $@", err => $@);
		}
	}

	$self->update if $self->autoupdate;
	return 1;
}

sub is_changed { keys %{ shift->{__Changed} } }

# By default do nothing. Subclasses should override if required.
#
# Given a hash ref of column names and proposed new values,
# edit the values in the hash if required.
# For create $self is the class name (not an object ref).
sub normalize_column_values {
	my ($self, $column_values) = @_;
}

# Given a hash ref of column names and proposed new values
# validate that the whole set of new values in the hash
# is valid for the object in relation to it's current values
# For create $self is the class name (not an object ref).
sub validate_column_values {
	my ($self, $column_values) = @_;
	my @errors;
	while (my ($column, $value) = each %$column_values) {
		eval { $self->call_trigger("before_set_$column", $value, $column_values) };
		push @errors, $column => $@ if $@;
	}
	return $self->_croak(
		"validate_column_values error: " . join (" ", @errors),
		method => 'validate_column_values',
		data   => {@errors}
		)
		if @errors;
}

# We override set_sql() from Ima::DBI so it has a default database connection.
sub set_sql {
	my ($class, $name, $sql, $db) = @_;
	$db = 'Main' unless defined $db;
	$class->SUPER::set_sql($name, $sql, $db);
	$class->_generate_search_sql($name);
	return 1;
}

sub _generate_search_sql {
	my ($class, $name) = @_;
	my $method = "search_$name";
	defined &{"$class\::$method"}
		and return $class->_carp("$method() already exists");
	my $sql_method = "sql_$name";
	no strict 'refs';
	*{"$class\::$method"} = sub {
		my ($class, @args) = @_;
		(my $sth = $class->$sql_method())->execute(@args);
		return $class->sth_to_objects($sth);
	};
}

sub dbi_commit   { my $proto = shift; $proto->SUPER::commit(@_); }
sub dbi_rollback { my $proto = shift; $proto->SUPER::rollback(@_); }

#----------------------------------------------------------------------
# Constraints
#----------------------------------------------------------------------

sub add_constraint {
	my ($class, $name, $column, $code) = @_;
	$class->_invalid_object_method('add_constraint()') if ref $class;
	return $class->_croak("Constraint needs a name")         unless $name;
	return $class->_croak("Constraint $name needs a column") unless $column;
	$class->_check_columns($column);
	return $class->_croak("Constraint $name needs a code reference")
		unless $code;
	return $class->_croak("Constraint $name '$code' is not a code reference")
		unless ref($code) eq "CODE";

	$column = $class->_normalized($column);
	$class->add_trigger(
		"before_set_$column" => sub {
			my ($self, $value, $column_values) = @_;
			$code->($value, $self, $column, $column_values)
				or return $self->_croak(
				"$class $column fails '$name' constraint with '$value'");
		}
	);
}

sub add_trigger {
	my ($self, $name, @args) = @_;
	return $self->_croak("on_setting trigger no longer exists")
		if $name eq "on_setting";
	$self->_carp(
		"$name trigger deprecated: use before_$name or after_$name instead")
		if ($name eq "create" or $name eq "delete");
	$self->SUPER::add_trigger($name => @args);
}

#----------------------------------------------------------------------
# Inflation
#----------------------------------------------------------------------

__PACKAGE__->mk_classdata('__hasa_rels');
__PACKAGE__->__hasa_rels({});

sub has_a {
	my ($class, $column, $a_class, %meths) = @_;
	%meths = () unless keys %meths;
	$class->_invalid_object_method('has_a()') if ref $class;
	$class->_check_columns($column);
	$column = $class->_normalized($column);
	return $class->_croak("$class $column needs an associated class")
		unless $a_class;
	_require_class($a_class);
	$class->_extend_class_data(__hasa_rels => $column => [ $a_class, %meths ]);
	$class->add_trigger(select              => _inflate_to_object($column));
	$class->add_trigger("after_set_$column" => _inflate_to_object($column));
	$class->add_trigger(before_create       => _deflate_object($column, 1));
	$class->add_trigger(before_update       => _deflate_object($column));
}

sub _inflate_to_object {
	my $col = shift;
	return sub {
		my $self = shift;
		return if not defined $self->{$col};
		my ($a_class, %meths) = @{ $self->__hasa_rels->{$col} };
		if (my $obj = ref $self->{$col}) {
			return if UNIVERSAL::isa($obj, $a_class);
			return $self->_croak(
				"Can't inflate $col to $a_class using '$self->{$col}': $obj is not a $a_class"
			);
		}
		my $get = $meths{'inflate'}
			|| ($a_class->isa('Class::DBI') ? "_simple_bless" : "new");
		my $obj =
			(ref $get eq "CODE")
			? $get->($self->{$col})
			: $a_class->$get($self->{$col});
		return $self->_croak(
			"Can't inflate $col to $a_class via $get using '$self->{$col}'")
			unless ref $obj;  # use ref as $obj may be overloaded and appear 'false'
		$self->{$col} = $obj;
		}
}

sub _simple_bless {
	my ($class, $pri) = @_;
	return bless { $class->primary_column => $pri }, $class;
}

sub _deflate_object {
	my ($col, $always) = @_;
	return sub {
		my $self = shift;
		$self->{$col} = $self->_deflated_column($col)
			if ($always or $self->{__Changed}->{$col});
	};
}

sub _deflated_column {
	my ($self, $col, $val) = @_;
	$val ||= $self->{$col} if ref $self;
	return $val unless ref $val;
	my $relation = $self->__hasa_rels->{$col} or return $val;
	my ($a_class, %meths) = @$relation;
	my $deflate = $meths{'deflate'} || '';
	return $self->_croak("Can't deflate $col: $val is not a $a_class")
		unless UNIVERSAL::isa($val, $a_class);
	return $val->$deflate() if $deflate;
	return $val->id if UNIVERSAL::isa($val => 'Class::DBI');
	return "$val";
}

#----------------------------------------------------------------------
# SEARCH
#----------------------------------------------------------------------

sub _run_query {
	my ($class, $type, $sel, $val, $col) = @_;
	return Class::DBI::Query->new(
		{
			owner        => $class,
			essential    => $col,
			sqlname      => $type,
			where_clause => $sel
		}
	)->run($val);
}

sub retrieve_from_sql {
	my ($class, $sql, @vals) = @_;
	$sql =~ s/^\s*(WHERE)\s*//i;
	my $sth = Class::DBI::Query->new(
		{
			owner        => $class,
			where_clause => $sql
		}
	)->run(\@vals);
	return $class->sth_to_objects($sth);
}

sub search_like { shift->_do_search(LIKE => @_) }
sub search      { shift->_do_search("="  => @_) }

sub _do_search {
	my ($proto, $search_type, @args) = @_;
	my $class = ref $proto || $proto;

	@args = %{ $args[0] } if ref $args[0] eq "HASH";
	my (@cols, @vals);
	my $search_opts = @args % 2 ? pop @args : {};
	while (my ($col, $val) = splice @args, 0, 2) {
		$col = $class->_normalized($col) or next;
		$class->_check_columns($col);
		push @cols, $col;
		push @vals, $class->_deflated_column($col, $val);
	}

	my $query = Class::DBI::Query->new({ owner => $class });
	$query->add_restriction("$_ $search_type ?") foreach @cols;
	$query->order_by($search_opts->{order_by}) if $search_opts->{order_by};

	my $sth = $query->run(\@vals);
	return $class->sth_to_objects($sth);
}

#----------------------------------------------------------------------
# CONSTRUCTORS
#----------------------------------------------------------------------

__PACKAGE__->add_constructor(retrieve_all => '');
__PACKAGE__->make_filter(ordered_search   => '%s = ? ORDER BY %s');
__PACKAGE__->make_filter(between          => '%s >= ? AND %s <= ?');

sub add_constructor {
	shift->_make_query(_run_constructor => @_);
}

sub make_filter {
	shift->_make_query(_run_filter => @_);
}

sub _make_query {
	my $class  = shift;
	my $runner = shift;
	$class->_invalid_object_method('add_constructor()') if ref $class;
	my $method = shift
		or return $class->_croak("Can't make_filter() without a method name");
	defined &{"$class\::$method"}
		and return $class->_carp("$method() already exists");

	# Create the query
	my $fragment = shift;
	my $query    = "SELECT %s FROM %s";
	$query .= " WHERE $fragment" if $fragment;
	$class->set_sql("_filter_$method" => $query);

	# Create the method
	no strict 'refs';
	*{"$class\::$method"} = sub {
		my $self = shift;
		$self->$runner("_filter_$method" => @_);
	};
}

sub _run_constructor {
	my ($proto, $filter, @args) = @_;
	my $class = ref $proto || $proto;

	my (@cols, @vals);
	if (ref $args[0] eq "ARRAY") {
		@cols = map $class->_normalized($_), @{ shift () };
		$class->_check_columns(@cols);
		@vals = @{ shift () };
	} else {
		@cols = ();
		@vals = @args;
	}
	my $sth = $class->_run_query($filter, \@cols, \@vals) or return;
	return $class->sth_to_objects($sth);
}

sub _run_filter {
	my ($proto, $filter, @args) = @_;
	my $class = ref $proto || $proto;
	@args = %{ $args[0] } if ref $args[0] eq "HASH";    # Uck.
	my (@cols, @vals);
	while (my ($col, $val) = splice @args, 0, 2) {
		$col = $class->_normalized($col) or next;
		$class->_check_columns($col);
		push @cols, $col;
		push @vals, $val if defined $val;
	}
	my $sth = $class->_run_query($filter, \@cols, \@vals) or return;
	return $class->sth_to_objects($sth);
}

sub sth_to_objects {
	my ($class, $sth) = @_;
	$class->_croak("Don't have a statement handle") unless $sth;
	my (%data, @rows);
	$sth->bind_columns(\(@data{ @{ $sth->{NAME_lc} } }));
	push @rows, {%data} while $sth->fetch;
	return $class->_ids_to_objects(\@rows);
}
*_sth_to_objects = \&sth_to_objects;

sub _my_iterator {
	my $self  = shift;
	my $class = $self->iterator_class;
	_require_class($class);
	return $class;
}

sub _ids_to_objects {
	my ($class, $data) = @_;
	return $#$data + 1 unless defined wantarray;
	return map $class->construct($_), @$data if wantarray;
	return $class->_my_iterator->new($class => $data);
}

#----------------------------------------------------------------------
# SINGLE VALUE SELECTS. 
#  need a name for these.
#----------------------------------------------------------------------

sub count_all {
	my $class = shift;
	$class->_single_value_select('COUNT(*)');
}

sub maximum_value_of {
	my ($class, $col) = @_;
	$class->_single_value_select("MAX($col)");
}

sub minimum_value_of {
	my ($class, $col) = @_;
	$class->_single_value_select("MIN($col)");
}

sub _single_value_select {
	my ($class, $select) = @_;
	my $sth;
	my $val = eval {
		$sth = $class->sql_single($select, $class->table);
		$sth->execute;
		my @row = $sth->fetchrow_array;
		$sth->finish;
		$row[0];
	};
	if ($@) {
		return $class->_croak(
			"Can't select for $class using '$sth->{Statement}': $@",
			err => $@);
	}
	return $val;
}

#----------------------------------------------------------------------
# NORMALIZATION
#----------------------------------------------------------------------
sub _normalized {
	my $self = shift;
	my @return = map {
		s/^.*\.//;                 # Chop off the possible table & database names.
		tr/ \t\n\r\f\x0A/______/;  # Translate whitespace to _
		lc;
	} @_;
	return wantarray ? @return : $return[0];
}

sub normalize {
	my ($self, $colref) = @_;
	return $self->_croak("Normalize needs a listref")
		unless ref $colref eq 'ARRAY';
	my @normalized = $self->_normalized(@$colref);
	$_ = shift @normalized foreach @$colref;    # clobber'em
	return 1;
}

sub _normalize_one {
	my ($self, $col) = @_;
	$$col = $self->_normalized($$col);
}

sub normalize_hash {
	my ($self, $hash) = @_;
	my (@normal_cols, @cols);

	@normal_cols = @cols = keys %$hash;
	$self->normalize(\@normal_cols);

	@{$hash}{@normal_cols} = delete @{$hash}{@cols};

	return 1;
}

sub _unique_entries {
	my ($class, %tmp) = shift;
	return grep !$tmp{$_}++, @_;
}

sub _invalid_object_method {
	my ($self, $method) = @_;
	$self->_carp(
		"$method should be called as a class method not an object method");
}

#----------------------------------------------------------------------
# RELATIONSHIPS
#----------------------------------------------------------------------

sub hasa {
	my ($class, $f_class, $f_col) = @_;
	$class->_carp("hasa() is deprecated in favour of has_a(). Using it instead.");
	$class->has_a($f_col => $f_class);
}

sub hasa_list {
	my $class = shift;
	$class->_carp("hasa_list() is deprecated in favour of has_many()");
	$class->has_many(@_[ 2, 0, 1 ], { nohasa => 1 });
}

sub has_many {
	my ($class, $accessor, $f_class, $f_key, $args) = @_;
	return $class->_croak("has_many needs an accessor name") unless $accessor;
	return $class->_croak("has_many needs a foreign class")  unless $f_class;
	$class->can($accessor)
		and return $class->_carp("$accessor method already exists in $class\n");

	my @f_method = ();
	if (ref $f_class eq "ARRAY") {
		($f_class, @f_method) = @$f_class;
	}
	_require_class($f_class);

	if (ref $f_key eq "HASH") {    # didn't supply f_key, this is really $args
		$args  = $f_key;
		$f_key = "";
	}

	$f_key ||= $class->table_alias;

	if (ref $f_key eq "ARRAY") {
		return $class->_croak("Multiple foreign keys not implemented")
			if @$f_key > 1;
		$f_key = $f_key->[0];
	}
	$class->_extend_hasa_list($f_class => $f_key);

	{

		# This stuff is highly experimental and will probably change beyond
		# recognition. Use at your own risk...
		my $query = Class::DBI::Query->new({ owner => $f_class });

		$query->kings($class, $f_class);
		$query->add_restriction(sprintf "%s.%s = %s.%s",
			$f_class->table_alias, $f_key, $class->table_alias,
			$class->primary_column);

		my $run_search = sub {
			my ($self, @search_args) = @_;
			if (ref $self) {
				unshift @search_args, ($f_key => $self->id);
				push @search_args, { order_by => $args->{sort} }
					if defined $args->{sort};
				return $f_class->search(@search_args);
			} else {
				my %kv    = @search_args;
				my $query = $query->clone;
				$query->add_restriction("$_ = ?") for keys %kv;
				my $sth = $query->run(values %kv);
				return $f_class->sth_to_objects($sth);
			}
		};

		no strict 'refs';
		*{"$class\::$accessor"} = @f_method
			? sub {
			return wantarray
				? do {
				my @ret = $run_search->(@_);
				foreach my $meth (@f_method) { @ret = map $_->$meth(), @ret }
				@ret;
				}
				: $run_search->(@_)->set_mapping_method(@f_method);
			}
			: $run_search;

		my $creator = "add_to_$accessor";
		*{"$class\::$creator"} = sub {
			my ($self, $data) = @_;
			my $class = ref($self)
				or return $self->_croak("$creator called as class method");
			return $self->_croak("$creator needs data") unless ref($data) eq "HASH";
			$data->{$f_key} = $self->id;
			$f_class->create($data);
		};
	}
}

sub _extend_hasa_list {
	my $class = shift;
	$class->_extend_class_data(__hasa_list => @_);
}

#----------------------------------------------------------------------
# might have
#----------------------------------------------------------------------

# Video->might_have(plot => Videolog::Plot => (import methods));

sub might_have {
	my ($class, $method, $foreign_class, @methods) = @_;
	_require_class($foreign_class);
	$class->add_trigger(before_update => sub { shift->$method()->update });
	no strict 'refs';
	*{"$class\::$method"} = sub {
		my $self = shift;
		$self->{"_${method}_object"} ||= $foreign_class->retrieve($self->id);
	};
	foreach my $meth (@methods) {
		*{"$class\::$meth"} = sub {
			my $self = shift;
			my $for_obj = $self->$method() or return;
			$for_obj->$meth(@_);
		};
	}
}

#----------------------------------------------------------------------
# misc stuff
#----------------------------------------------------------------------

sub _extend_class_data {
	my ($class, $struct, $key, $value) = @_;
	my %hash = %{ $class->$struct() || {} };
	$hash{$key} = $value;
	$class->$struct(\%hash);
}

sub _require_class {
	my $class = shift;

	# return quickly if class already exists
	no strict 'refs';
	return if exists ${"$class\::"}{ISA};
	return if eval "require $class";

	# Only ignore "Can't locate" errors from our eval require.
	# Other fatal errors (syntax etc) must be reported (as per base.pm).
	return if $@ =~ /^Can't locate .*? at \(eval /;
	chomp $@;
	Carp::croak($@);
}

1;

__END__

=head1 NAME

	Class::DBI - Simple Database Abstraction

=head1 SYNOPSIS

	package Music::DBI;
	use base 'Class::DBI';
	Music::DBI->set_db('Main', 'dbi:mysql', 'username', 'password');

	package Artist;
	use base 'Music::DBI';
	Artist->table('artist');
	Artist->columns(All => qw/artistid name/);
	Artist->has_many('cds', 'CD' => artist);

	package CD;
	use base 'Music::DBI';
	CD->table('cd');
	CD->columns(All => qw/cdid artist title year/);
	CD->has_many('tracks', 'Track' => 'cd', { sort => 'position' });
	CD->has_a(artist => 'CD::Artist');
	CD->has_a(reldate => 'Time::Piece',
		inflate => sub { Time::Piece->strptime(shift => "%Y-%m-%d") },
		deflate => 'ymd',
	}

	CD->might_have(liner_notes => LinerNotes => qw/notes/);

	package Track;
	use base 'Music::DBI';
	Track->table('track');
	Track->columns(All => qw/trackid cd position title/); 

	#-- Meanwhile, in a nearby piece of code! --#

	my $artist = Artist->create({ artistid => 1, name => 'U2' });

	my $cd = $artist->add_to_cds({ 
		cdid   => 1,
		title  => 'October',
		year   => 1980,
	});

	# Oops, got it wrong.
	$cd->year(1981);
	$cd->update;

	# etc.

	while (my $track = $cd->tracks) {
		print $track->position, $track->title
	}

	$cd->delete; # also deletes the tracks

	my $cd  = CD->retrieve(1);
	my @cds = CD->retrieve_all;
	my @cds = CD->search(year => 1980);
	my @cds = CD->search_like(title => 'October%');

=head1 DESCRIPTION

Class::DBI provides a convenient abstraction layer to a database.

It not only provides a simple database to object mapping layer, but can
be used to implement several higher order database functions (triggers,
referential integrity, cascading delete etc.), at the application level,
rather than at the database.

This is particularly useful when using a database which doesn't support
these (such as MySQL), or when you would like your code to be portable
across multiple databases which might implement these things in different
ways.

In short, Class::DBI aims to make it simple to introduce 'best
practice' when dealing with data stored in a relational database.

=head2 How to set it up

=over 4

=item I<Set up a database.>

You must have an existing database set up, have DBI.pm installed and
the necessary DBD:: driver module for that database.  See L<DBI> and
the documentation of your particular database and driver for details.

=item I<Set up a table for your objects to be stored in.>

Class::DBI works on a simple one class/one table model.  It is your
responsibility to have your database tables already set up. Automating that
process is outside the scope of Class::DBI.

Using our CD example, you might declare a table something like this:

	CREATE TABLE cd (
		cdid   INTEGER   PRIMARY KEY,
		artist INTEGER, # references 'artist'
		title  VARCHAR(255),
		year   CHAR(4),
	);

=item I<Set up an application base class>

It's usually wise to set up a "top level" class for your entire
application to inherit from, rather than have each class inherit
directly from Class::DBI.  This gives you a convenient point to
place system-wide overrides and enhancements to Class::DBI's behavior.

	package Music::DBI;
	use base 'Class::DBI';

(It is prefered that you use base.pm to do this rather than setting
@ISA, as your class may have to inherit some protected data fields).

=item I<Give it a database connection>

Class::DBI needs to know how to access the database.  It does this
through a DBI connection which you set up by calling the set_db()
method.

	Music::DBI->set_db('Main', 'dbi:mysql:', 'user', 'password');

By calling the method in your application base class all the
table classes that inherit from it will share the same connection.

The first parameter is the name for this database connection and
it must be 'Main' for Class::DBI to function.  See L</set_db> below
and L<Ima::DBI> for more details on set_db().

=item I<Set up each Class>

	package CD;
	use base 'Music::DBI';

Each class will inherit from your application base class, so you don't need to
repeat the information on how to connect to the database.

=item I<Declare the name of your table>

Inform Class::DBI what table you are using for this class:

	CD->table('cd');

=item I<Declare your columns.>

This is done using the columns() method. In the simplest form, you tell
it the name of all your columns (primary key first):

	CD->columns(All => qw/cdid artist title year/);

For more information about how you can more efficiently use subsets of your
columns, L<"Lazy Population">

=item I<Done.>

That's it! You now have a class with methods to create(), retrieve(),
search() for, update() and delete() objects from
your table, as well as accessors and mutators for each of the columns
in that object (row).

=back

Let's look at all that in more detail:

=head1 CLASS METHODS

=head2 set_db

	__PACKAGE__->set_db('Main', $data_source, $user, $password, \%attr);

For details on this method, L<Ima::DBI>.

The special connection named 'Main' must always be set.  Connections
are inherited so it's usual to call set_db() just in your application
base class.

	package Music::DBI;
	use base 'Class::DBI';

	Music::DBI->set_db('Main', 'dbi:foo:', 'user', 'password');

	package My::Other::Table;
	use base 'Music::DBI';

Class::DBI helps you along a bit to set up the database connection.
set_db() provides its own default attributes depending on the driver name
in the data_source parameter. The most significant of which is AutoCommit.
The DBI defaults AutoCommit on but Class::DBI will default it to off
if the database driver is Oracle or Pg, so that transactions are used.

The set_db() method also provides defaults for these attributes:

	FetchHashKeyName	=> 'NAME_lc',
	ShowErrorStatement	=> 1,
	AutoCommit		=> 1,
	ChopBlanks		=> 1,

The defaults can always be overridden by supplying your own \%attr parameter.

=head2 table

	__PACKAGE__->table($table);

	$table = Class->table;
	$table = $obj->table;

An accessor to get/set the name of the database table in which this
class is stored.  It -must- be set.

Table information is inherited by subclasses, but can be overridden.

=head2 table_alias

	package Shop::Order;
	__PACKAGE__->table('orders');
	__PACKAGE__->table_alias('orders');

When Class::DBI constructs SQL, it aliases your table name to a name
representing your class. However, if your class's name is an SQL reserved
word (such as 'Order') this will cause SQL errors. In such cases you
should supply your own alias for your table name (which can, of course,
be the same as the actual table name).

This can also be passed as a second argument to 'table':

	__PACKAGE-->table('orders', 'orders');

As with table, this is inherited but can be overriden.

=head2 sequence

	__PACKAGE__->sequence($sequence_name);

	$sequence_name = Class->sequence;
	$sequence_name = $obj->sequence;

If you are using a database which supports sequences and you want
to use a sequence to automatically supply values for the primary
key of a table, then you should declare this using the sequence()
method:

	__PACKAGE__->columns(Primary => 'id');
	__PACKAGE__->sequence('class_id_seq');

Class::DBI will use the sequence to generate a primary key value
when objects are created without one.

If you are using a database with AUTO_INCREMENT (e.g. MySQL) then
you do not need this, and a create() which does not specify a primary
key will fill this in automagically.

=head1 CONSTRUCTORS and DESTRUCTORS

The following are methods provided for convenience to create, retrieve
and delete stored objects.  It's not entirely one-size fits all and you
might find it necessary to override them.

=head2 create

	my $obj = Class->create(\%data);

This is a constructor to create a new object and store it in the database.

%data consists of the initial information to place in your object and
the database.  The keys of %data match up with the columns of your
objects and the values are the initial settings of those fields.

	my $cd = CD->create({ 
		cdid   => 1,
		artist => $artist,
		title  => 'October',
		year   => 1980,
	});

If the table has a single primary key column and that column value
is not defined in %data, create() will assume it is to be generated.
If a sequence() has been specified for this Class, it will use that.
Otherwise, it will assume the primary key can be generated by
AUTO_INCREMENT and attempt to use that.

The C<before_create>($self) trigger is invoked directly after storing
the supplied values into the new object and before inserting the record
into the database.

If the class has declared relationships with foreign classes via
has_a(), you can pass an object to create() for the value of that key.
Class::DBI will Do The Right Thing.

After the new record has been inserted into the database the data
for non-primary key columns is discarded from the object. If those
columns are accessed again they'll simply be fetched as needed.
This ensures that the data in the application is consistant with
what the database I<actually> stored.

The C<after_create> trigger is invoked after the database insert
has executed and is passed ($self, discard_columns => \@discard_columns).
The trigger code can modify the discard_columns array to affect
which columns are discarded.  For example:

	Class->add_trigger(after_create => sub {
		my ($self, %args) = @_;
		my $discard_columns = $args{discard_columns};
		# don't discard any columns, we trust that the
		# database will not have modified them.
		@$discard_columns = ();
	});

Take care to not discard a primary key column unless you know what you're doing.

=head2 find_or_create

	my $cd = CD->find_or_create({ artist => 'U2', title => 'Boy' });

This checks if a CD can be found to match the information passed, and
if not creates it. 

=head2 delete

	$obj->delete;
	CD->delete(year => 1980, title => 'Greatest %');

Deletes this object from the database and from memory. If you have set up
any relationships using has_many, this will delete the foreign elements
also, recursively (cascading delete).  $obj is no longer usable after this call.

If called as a class method, deletes all objects matching the search
criteria given.  Each object found will be deleted in turn, so cascading
delete and other triggers will be honoured.

The C<before_delete> trigger is when an object instance is about
to be deleted. It is invoked before any cascaded deletes.
The C<after_delete> trigger is invoked after the record has been
deleted from the database and just before the contents in memory
are discarded.

=head1 RETRIEVING OBJECTS

We provide a few simple search methods, more to show the potential of
the class than to be serious search methods.

=head2 retrieve

	$obj = Class->retrieve($id);

Given an ID it will retrieve the object with that ID from the database.

	my $cd = CD->retrieve(1) or die "No such cd";

=head2 retrieve_all

	my @objs = Class->retrieve_all;
	my $iterator = Class->retrieve_all;

Retrieves objects for all rows in the database. This is probably a
bad idea if your table is big, unless you use the iterator version.

=head2 search

	@objs = Class->search(column1 => $value, column2 => $value ...);

This is a simple search for all objects where the columns specified are
equal to the values specified e.g.:

	@cds = CD->search(year => 1990);
	@cds = CD->search(title => "Greatest Hits", year => 1990);

=head2 search_like

	@objs = Class->search_like(column1 => $like_pattern, ....);

This is a simple search for all objects where the columns specified are
like the values specified.  $like_pattern is a pattern given in SQL LIKE
predicate syntax.  '%' means "any one or more characters", '_' means
"any single character".

	@cds = CD->search_like(title => 'October%');
	@cds = CD->search_like(title => 'Hits%', artist => 'Various%');

=head1 ITERATORS

	my $it = CD->search_like(title => 'October%');
	while (my $cd = $it->next) {
		print $cd->title;
	}

Any of the above searches (including those defined by has_many) can
also be used as an iterator.  Rather than creating a list of objects
matching your criteria, this will return a Class::DBI::Iterator instance,
which can return the objects required one at a time.

Currently the iterator initially fetches all the matching row data into
memory, and defers only the creation of the objects from that data until
the iterator is asked for the next object. So using an iterator will
only save significant memory if your objects inflate substantially
on creation. 

In the case of has_many relationships with a mapping method, the mapping
method is not called until each time you call 'next'. This means that
if your mapping is not a one-to-one, the results will probably not be
what you expect.

=head2 Subclassing the Iterator

	CD->iterator_class('CD::Iterator');

You can also subclass the default iterator class to override its
functionality.  This is done via class data, and so is inherited into
your subclasses.

=head2 QUICK RETRIEVAL

	my $obj = Class->construct(\%data);

This is a B<protected> method and can only be called by subclasses.

It constructs a new object based solely on the %data given. It treats that
data just like the columns of a table, where key is the column name, and
value is the value in that column.  This is very handy for cheaply setting
up lots of objects from data for without going back to the database.

For example, instead of doing one SELECT to get a bunch of IDs and then
feeding those individually to retrieve() (and thus doing more SELECT
calls), you can do one SELECT to get the essential data of many objects
and feed that data to construct():

	 return map $class->construct($_), $sth->fetchall_hash;

The construct() method creates a new empty object, loads in the
column values, and then invokes the C<select> trigger.

=head1 COPY AND MOVE

=head2 copy

	$new_obj = $obj->copy;
	$new_obj = $obj->copy($new_id);
	$new_obj = $obj->copy({ title => 'new_title', rating => 18 });

This creates a copy of the given $obj both in memory and in the
database.  The only difference is that the $new_obj will have a new
primary identifier.

A new value for the primary key can be suppiled, otherwise the
usual sequence or autoincremented primary key will be used. If you
wish to change values other than the primary key, then pass a hashref
of all the new values.

	my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");
	my $blrunner_unrated = $blrunner->copy({
		Title => "Bladerunner: Director's Cut",
		Rating => 'Unrated',
	});

=head2 move

	my $new_obj = Sub::Class->move($old_obj);
	my $new_obj = Sub::Class->move($old_obj, $new_id);
	my $new_obj = Sub::Class->move($old_obj, \%changes);

For transfering objects from one class to another. Similar to copy(), an
instance of Sub::Class is created using the data in $old_obj (Sub::Class
is a subclass of $old_obj's subclass). Like copy(), you can supply
$new_id as the primary key of $new_obj (otherwise the usual sequence or
autoincrement is used), or a hashref of multiple new values.

=head1 TRIGGERS

	__PACKAGE__->add_trigger(trigger_point_name => \&code_to_execute);

	# e.g.

	__PACKAGE__->add_trigger(after_create  => \&call_after_create);

It is possible to set up triggers that will be called at various
points in the life of an object. Valid trigger points are:

	before_create       (also used for deflation)
	after_create
	before_set_$column  (also used by add_constraint)
	after_set_$column   (also used for inflation and by has_a)
	before_update       (also used for deflation and by might_have)
	after_update
	before_delete
	after_delete
	select              (also used for inflation and by construct and _flesh)

[Note: Trigger points 'create' and 'delete' are deprecated and will be
removed in a future release.]

You can create any number of triggers for each point, but you cannot
specify the order in which they will be run. Each will be passed the
object being dealt with (whose values you may change if required),
and return values will be ignored.

All triggers are passed the object they are being fired for.
Some triggers are also passed extra parameters as name-value pairs.
The individual triggers are documented with the methods that trigger them.

=head1 CONSTRAINTS

	__PACKAGE__->add_constraint('name', column => \&check_sub);

	# e.g.

	__PACKAGE__->add_constraint('over18', age => \&check_age);

	# Simple version
	sub check_age { 
		my ($value) = @_;
		return $value >= 18;
	}

	# Cross-field checking - must have SSN if age < 18
	sub check_age { 
		my ($value, $self, $column_name, $changing) = @_;
		return 1 if $value >= 18;     # We're old enough. 
		return 1 if $changing->{SSN}; # We're also being given an SSN
		return 0 if !ref($self);      # This is a create, so we can't have an SSN
		return 1 if $self->ssn;       # We already have one in the database
		return 0;                     # We can't find an SSN anywhere
	}

It is also possible to set up constraints on the values that can be set
on a column. The constraint on a column is triggered whenever an object
is created and whenever that column is modified.

The constraint code is called with four parameters:

	- The new value to be assigned
	- The object it will be assigned to
	(or class name when initially creating an object)
	- The name of the column
	(useful if many constraints share the same code)
	- A hash ref of all new column values being assigned
	(useful for cross-field validation)

The constraints are applied to all the columns being set before the
object data is updated.  Attempting to create or update an object
where one or more constraint fail results in an exception and the object
remains unchanged.

Note 1: Constraints are implemented using before_set_$column triggers.
This will only prevent you from setting these values through a
the provided create() or set() methods. It will always be possible to
bypass this if you try hard enough.

Note 2: When an object is created constraints are currently only
checked for column names included in the parameters to create().
This is probably a bug and is likely to change in future.

=head1 DATA NORMALIZATION

Before an object is assigned data from the application (via create
or a set accessor) the normalize_column_values() method is called
with a reference to a hash containing the column names and the new
values which are to be assigned (after any validation and constraint
checking, as described below).

Currently Class::DBI does not offer any per-column mechanism here.
The default method is empty.  You can override it in your own classes
to normalize (edit) the data in any way you need. For example the
values in the hash for certain columns could be made lowercase.

The method is called as an instance method when the values of an
existing object are being changed, and as a class (static) method
when a new object is being created.

=head1 DATA VALIDATION

Before an object is assigned data from the application (via create
or a set accessor) the validate_column_values() method is called
with a reference to a hash containing the column names and the new
values which are to be assigned.

The method is called as an instance method when the values of an
existing object are being changed, and as a class (static) method
when a new object is being created.

The default method calls the before_set_$column trigger for
each column name in the hash. Each trigger is called inside an eval.
Any failures result in an exception after all have been checked.
The exception data is a reference to a hash which holds the
column name and error text for each trigger error.

When using this mechanism for form data validation, for example,
this exception data can be stored in an exception object, via a
custom _croak() method, and then caught and used to redisplay the
form with error messages next to each field which failed validation.

=head1 EXCEPTIONS

All errors that are generated, or caught and propagated, by Class::DBI
are handled by calling the _croak() method (as an instance method
if possible, or else as a class method).

The _croak() method is passed an error message and in some cases
some extra information as described below. The default behaviour
is simply to call Carp::croak($message).

Applications that require custom behaviour should override the
_croak() method in their application base class (or table classes
for table-specific behaviour). For example:

	use Error;

	sub _croak {
		my ($self, $message, %info) = @_;
		# convert errors into exception objects
		# except for duplicate insert errors which we'll ignore
		Error->throw(-text => $message, %info)
			unless $message =~ /^Can't insert .* duplicate/;
		return;
	}

The _croak() method is expected to trigger an exception and not
return. If it does return then it should use C<return;> so that an
undef or empty list is returned as required depending on the calling
context. You should only return other values if you are prepared to
deal with the (unsupported) consequences. 

For exceptions that are caught and propagated by Class::DBI, $message
includes the text of $@ and the original $@ value is available in $info{err}.
That allows you to correctly propagate exception objects that may have
been thrown 'below' Class::DBI (using Exception::Class::DBI for example). 

Exceptions generated by some methods may provide additional data in
$info{data} and, if so, also store the method name in $info{method}.
For example, the validate_column_values() method stores details of
failed validations in $info{data}. See individual method documentation
for what additional data they may store, if any.

Note that Class::DBI doesn't go out of its way to catch and propagate 
fatal errors from the DBI or elsewhere. There are some parts of
Class::DBI that invoke DBI calls without an eval { } wrapper. 
If the DBI detects an error then the default DBI RaiseError behaviour
will trigger an exception that does not pass through the _croak()
method.

=head1 WARNINGS

All warnings are handled by calling the _carp() method (as
an instance method if possible, or else as a class method).
The default behaviour is simply to call Carp::carp().

=head1 INSTANCE METHODS

=head2 accessors

Class::DBI inherits from Class::Accessor and thus provides individual
accessor methods for every column in your subclass.  It also overrides
the get() and set() methods provided by Accessor to automagically
handle database reading and writing.

=head2 the fundamental set() and get() methods

	$value = $obj->get($column_name);

	$obj->set($column_name, $value);

	$obj->set( %column_name_values );

These methods are the fundamental entry points for getting and
seting column values.  The extra accessor methods automatically
generated for each column of your table are simple wrappers that
call these get() and set() methods.

The set() method calls normalize_column_values() then
validate_column_values() before storing the values.
The C<before_set_$column> trigger is invoked by validate_column_values().
The C<after_set_$column> trigger is invoked after the new value has
been stored.

It is possible for an object to not have all its column data in memory
(due to lazy inflation).  If the get() method is called for such a column
then it will select the corresponding group of columns and then invoke
the C<select> trigger.

=head2 changing your column accessor method names

If you want to change the name of your accessors, you need to provide an
accessor_name() method, which will convert a column name to a method name.

e.g: if your local naming convention was to prepend the word 'customer'
to each column in the 'customer' table, so that you had the columns
'customerid', 'customername' and 'customerage', you would write:

	sub accessor_name {
		my ($class, $column) = @_;
		$column =~ s/^customer//;
		return $column;
	}

Your methods would now be $customer->id, $customer->name and
$customer->age rather than $customer->customerid etc.

Similarly, if you want to have distinct accessor and mutator methods,
you would provide a mutator_name() method which would return the name
of the method to change the value:

	sub mutator_name {
		my ($class, $column) = @_;
		return "set_$column";
	}

If you override the mutator_name, then the accessor method will be
enforced as read-only, and the mutator as write-only.

=head2 update vs auto update

There are two modes for the accessors to work in: manual update and
autoupdate (This is sort of analagous to the manual vs autocommit in
DBI). When in autoupdate mode, every time one calls an accessor to make a
change an UPDATE will immediately be sent to the database.  Otherwise,
if autoupdate is off, no changes will be written until update() is
explicitly called.

This is an example of manual updating:

	# The calls to NumExplodingSheep() and Rating() will only make the
	# changes in memory, not in the database.  Once update() is called
	# it writes to the database in one swell foop.
	$gone->NumExplodingSheep(5);
	$gone->Rating('NC-17');
	$gone->update;

And of autoupdating:

	# Turn autoupdating on for this object.
	$gone->autoupdate(1);

	# Each accessor call causes the new value to immediately be written.
	$gone->NumExplodingSheep(5);
	$gone->Rating('NC-17');

Manual updating is probably more efficient than autoupdating and
it provides the extra safety of a discard_changes() option to clear out all
unsaved changes.  Autoupdating can be more convient for the programmer.
Autoupdating is I<off> by default.

If changes are left un-updated or not rolledback when the object is
destroyed (falls out of scope or the program ends) then Class::DBI's
DESTROY method will print a warning about unsaved changes.

=head2 autoupdate

	__PACKAGE__->autoupdate($on_or_off);
	$update_style = Class->autoupdate;

	$obj->autoupdate($on_or_off);
	$update_style = $obj->autoupdate;

This is an accessor to the current style of auto-updating.  When called
with no arguments it returns the current auto-updating state, true for on,
false for off.  When given an argument it turns auto-updating on and off:
a true value turns it on, a false one off.

When called as a class method it will control the updating style for
every instance of the class.  When called on an individual object it
will control updating for just that object, overriding the choice for
the class.

	__PACKAGE__->autoupdate(1);     # Autoupdate is now on for the class.

	$obj = Class->retrieve('Aliens Cut My Hair');
	$obj->autoupdate(0);      # Shut off autoupdating for this object.

The update setting for an object is not stored in the database.

=head2 update

	$obj->update;

If L</autoupdate> is not enabled then changes you make to your
object are not reflected in the database until you call update().
It is harmless to call update() if there are no changes to be saved.
(If autoupdate is on there'll never be anything to save.)

Note: If you have transactions turned on (but see L<"TRANSACTIONS"> below) 
you will also need to call dbi_commit(), as update() merely issues the UPDATE
to the database).

After the database update has been executed, the data for columns
that have been updated are deleted from the object. If those columns
are accessed again they'll simply be fetched as needed. This ensures
that the data in the application is consistant with what the database
I<actually> stored.

When update() is called the C<before_update>($self) trigger is
always invoked immediately.

If any columns have been updated then the C<after_update> trigger
is invoked after the database update has executed and is passed:
  ($self, discard_columns => \@discard_columns, rows => $rows)

(where rows is the return value from the DBI execute() method).

The trigger code can modify the discard_columns array to affect
which columns are discarded.

For example:

	Class->add_trigger(after_update => sub {
		my ($self, %args) = @_;
		my $discard_columns = $args{discard_columns};
		# discard the md5_hash column if any field starting with 'foo'
		# has been updated - because the md5_hash will have been changed
		# by a trigger.
		push @$discard_columns, 'md5_hash' if grep { /^foo/ } @$discard_columns;
	});

Take care to not delete a primary key column unless you know what
you're doing.

The update() method returns the number of rows updated, which should
always be 1, or else -1 if no update was needed. If the record in the
database has been deleted, or its primary key value changed, then the
update will not affect any records and so the update() method will
return 0.

=head2 discard_changes

	$obj->discard_changes;

Removes any changes you've made to this object since the last update.
Currently this simply discards the column values from the object.

If you're using autoupdate this method will throw an exception.

=head2 is_changed

	my $changed = $obj->is_changed;
	my @changed_keys = $obj->is_changed;

Indicates if the given $obj has changes since the last update.  Returns a
list of keys which have changed.

=head2 id

	$id = $obj->id;

Returns a unique identifier for this object.  It's the equivalent of
$obj->get($self->columns('Primary'));

=head2 OVERLOADED OPERATORS

Class::DBI and its subclasses overload the perl builtin I<stringify>
and I<bool> operators. This is a significant convienience.

When a Class::DBI object reference is used in a string context it
will return the result of calling the id() method on itself.

This is especially useful for columns that have has_a() relationships.
For example, consider a table that has price and currency fields:

	package Widget;
	use base 'My::Class::DBI';
	Widget->table('widget');
	Widget->columns(All => qw/widgetid name price currency_code/);

	$obj = Widget->retrieve($id);
	print $obj->price . " " . $obj->currency_code;

The would print something like "C<42.07 USD>".  If the currency_code
field is later changed to be a foreign key to a new currency table then
$obj->currency_code will return an object reference instead of a plain
string. Without overloading the stringify operator the example would now
print something like "C<42.07 Widget=HASH(0x1275}>" and the fix would
be to change the code to add a call to id():

	print $obj->price . " " . $obj->currency_code->id;

However, with overloaded stringification, the original code continues
to work as before, with no code changes needed.

This makes it much simpler and safer to add relationships to exisiting
applications, or remove them later.

The perl builtin I<bool> operator is also overloaded so that a Class::DBI
object reference is always true unless the id() value is undefined. Thus
an object with an id() of zero is not considered false.

=head1 TABLE RELATIONSHIPS

Databases are all about relationships. And thus Class::DBI needs a way
for you to set up descriptions of your relationhips.

Currently we provide three such methods: 'has_a', 'has_many', and
'might_have'.

=head2 has_a

	CD->has_a(artist => 'CD::Artist');
	print $cd->artist->name;

	CD->has_a(reldate => 'Date::Simple');
	print $cd->reldate->format("%d %b, %Y");

	CD->has_a(reldate => 'Time::Piece',
		inflate => sub { Time::Piece->strptime(shift => "%Y-%m-%d") },
		deflate => 'ymd',
	}
	print $cd->reldate->strftime("%d %b, %Y");

We use 'has_a' to declare that the value we have stored in the column
is a reference to something else. Thus, when we access the 'artist'
method we don't just want that ID returned, but instead we inflate it
to this other object.

This might be another Class::DBI representation, in which case we will
call retrieve() on that class, or it can be any other object which
is either instantiated with new(), or by a given 'inflate' method, and
which can be 'deflated' either by stringification (such as Date::Simple),
or by the given 'deflate' method.

=head2 has_many

	CD->has_many('tracks', CD::Track => 'cd');
	my @tracks = $cd->tracks;

	my $track6 = $cd->add_to_tracks({ 
		position => 6,
		title    => 'Tomorrow',
	});

We use 'has_many' to declare that someone else is storing our primary
key in their table, and create a method which returns a list of all the
associated objects, and another method to create a new associated object.

In the above example we say that the table of the CD::Track class contains
our primary key in its 'cd' column, and that we wish to access all the
occasions of that (i.e. the tracks on this cd) through the 'tracks'
method.

We also create an 'add_to_tracks' method that adds a track to a given CD.
In this example this call is exactly equivalent to calling:

	my $track6 = CD::Track->create({
		cd       => $cd->id,
		position => 6,
		title    => 'Tomorrow',
	});

=head3 Limiting

	Artist->has_many(cds => 'CD');
	my @cds = $artist->cds(year => 1980);

When calling the has_many method, you can also supply any additional
key/value pairs for restricting the search. The above example will only
return the CDs with a year of 1980.

=head3 Ordering

	CD->has_many('tracks', 'Track' => 'cd', { sort => 'playorder' });

Often you wish to order the values returned from has_many. This can be
done by passing a hash ref containing a 'sort' value of the column by
wish you want to order.

=head3 Mapping

	CD->has_many('styles', [ 'StyleRef' => 'style' ], 'cd');

For many-to-many relationships, where we have a lookup table, we can avoid
having to set up a helper method to convert our list of cross-references
into the objects we really want, by adding the mapping method to our
foreign class declaration.

The above is exactly equivalent to:

	CD->has_many('_style_refs', 'StyleRef', 'cd');
	sub styles { 
		my $self = shift;
		return map $_->style, $self->_style_refs;
	}

=head2 might_have

	CD->might_have(method_name => Class => (@fields_to_import));

	CD->might_have(liner_notes => LinerNotes => qw/notes/);

	my $liner_notes_object = $cd->liner_notes;
	my $notes = $cd->notes; # equivalent to $cd->liner_notes->notes;

might_have() is similar to has_many() for relationships that can have
at most one associated objects. For example, if you have a CD database
to which you want to add liner notes information, you might not want
to add a 'liner_notes' column to your main CD table even though there
is no multiplicity of relationship involved (each CD has at most one
'liner notes' field). So, we create another table with the same primary
key as this one, with which we can cross-reference.

But you don't want to have to keep writing methods to turn the the
'list' of liner_notes objects you'd get back from has_many into the
single object you'd need. So, might_have() does this work for you. It
creates you an accessor to fetch the single object back if it exists,
and it also allows you import any of its methods into your namespace. So,
in the example above, the LinerNotes class can be mostly invisible -
you can just call $cd->notes and it will call the notes method on the
correct LinerNotes object transparently for you.

Making sure you don't have namespace clashes is up to you, as is correctly
creating the objects, but I may make these simpler in later versions.
(Particularly if someone asks for them!)

=head2 Class::DBI::Join

If none of these do exactly what you want, and you have more complex
many-to-many relationships, you may find Class::DBI::Join (available on
CPAN) to be useful.

=head2 Notes

has_a(), might_have() and has_many() check that the relevant class already
exists. If it doesn't then they try to load a module of the same name
using require.  If the require fails because it can't find the module
then it will assume it's not a simple require (i.e., Foreign::Class
isn't in Foreign/Class.pm) and that you will care of it and ignore the
warning. Any other error, such as a syntax error, triggers an exception.

NOTE: The two classes in a relationship do not have to be in the same
database, on the same machine, or even in the same type of database! It
is quite acceptable for a table in a MySQL database to be connected to
a different table in an Oracle database, and for cascading delete etc
to work across these. This should assist greatly if you need to migrate
a database gradually.


=head1 DEFINING SQL STATEMENTS

There are several main methods for setting up your own SQL queries:

For queries which could be used to create a list of matching objects
you can create a constructor method associated with this SQL and let
Class::DBI do the work for you, or just inline the entire query.

For more complex queries you need to fall back on the underlying Ima::DBI
query mechanism.

=head2 add_constructor

	__PACKAGE__->add_constructor(method_name => 'SQL_where_clause');

The SQL can be of arbitrary complexity and will be turned into:
	 SELECT (essential columns)
		 FROM (table name)
		WHERE <your SQL>

This will then create a method of the name you specify, which returns
a list of objects as with any built in query.

For example:

	CD->add_constructor(new_music => 'year > 2000');
	my @recent = CD->new_music;

You can also supply placeholders in your SQL, which must then be
specified at query time:

	CD->add_constructor(new_music => 'year > ?');
	my @recent = CD->new_music(2000);

=head2 retrieve_from_sql

	my @cds = CD->retrieve_from_sql(qq{
		artist = 'Ozzy Osbourne' AND
		title like "%Crazy"      AND
		year <= 1986
		ORDER BY year
		LIMIT 2,3
	});

On occassions where you want to execute arbitrary SQL, but don't want
to go to the trouble of setting up a constructor method, you can inline
the entire WHERE clause, and just get the objects back directly.

=head2 Ima::DBI queries

When you can't use 'add_constructor', e.g. when using aggregate functions,
you can fall back on the fact that Class::DBI inherits from Ima::DBI
and prefers to use its style of dealing with statemtents, via set_sql().

So, to add a query that returns the 10 Artists with the most CDs, you
could write (with MySQL):

	Artist->set_sql(most_cds => qq{
		SELECT artist.id, COUNT(cd.id) AS cds
		  FROM artist, cd
		 WHERE artist.id = cd.artist
		 GROUP BY artist.id
		 ORDER BY cds DESC
		 LIMIT 10
	});

This will automatically set up the method Artist->search_most_cds(), which 
executes this search and returns the relevant objects (or Iterator).

If you have placeholders in your query, you must pass the relevant
arguments when calling your search method.

This does the equivalent of:

	sub top_ten {
		my $class = shift;
		my $sth = $class->sql_most_cds;
		$sth->execute;
		return $class->sth_to_objects($sth);
	}

The $sth which we use to return the objects here is a normal DBI-style
statement handle, so if your results can't even be turned into objects
easily, you can still call $sth->fetchrow_array etc and return whatever
data you choose.

If you want to write new methods which are inheritable by your subclasses
you must be careful not to hardcode any information about your class's
table name or primary key, and instead use the table() and columns()
methods instead.

=head2 Class::DBI::AbstractSearch

	my @music = CD::Music->search_where(
		artist => [ 'Ozzy', 'Kelly' ],
		status => { '!=', 'outdated' },
	);

The L<Class::DBI::AbstractSearch> module, available from CPAN, is a
plugin for Class::DBI that allows you to write arbitrarily complex
searches using perl data structures, rather than SQL.

=head1 LAZY POPULATION

In the tradition of Perl, Class::DBI is lazy about how it loads your
objects.  Often, you find yourself using only a small number of the
available columns and it would be a waste of memory to load all of them
just to get at two, especially if you're dealing with large numbers of
objects simultaneously.

You should therefore group together your columns by typical usage, as
fetching one value from a group can also pre-fetch all the others in
that group for you, for more efficient access.

So for example, if we usually fetch the artist and title, but don't use
the 'year' so much, then we could say the following:

	CD->columns(Primary   => qw/cdid/);
	CD->columns(Essential => qw/artist title/);
	CD->columns(Others    => qw/year runlength/);

Now when you fetch back a CD it will come pre-loaded with the 'cdid',
'artist' and 'title' fields. Fetching the 'year' will mean another visit
to the database, but will bring back the 'runlength' whilst it's there.
This can potentially increase performance.

If you don't like this behavior, then just add all your non-primary key
columns to the one group, and Class::DBI will load everything at once.

=head2 Non-Persistent Fields

	CD->columns(TEMP => qw/nonpersistent/);

If you wish to have fields that act like columns in every other way, but
that don't actually exist in the database (and thus will not persist),
you can declare them as part of a column group of 'TEMP'.

=head2 columns

	my @all_columns  = $class->columns;
	my @columns      = $class->columns($group);

	my $primary      = $class->primary_column;
	my @essential    = $class->_essential;

There are four 'reserved' groups.  'All', 'Essential', 'Primary' and
'TEMP'.

B<'All'> are all columns used by the class.  If not set it will be
created from all the other groups.

B<'Primary'> is the single primary key column for this class.  It I<must>
be set before objects can be used.  (Multiple primary keys are not
supported).  

If 'All' is given but not 'Primary' it will assume the first column in
'All' is the primary key.

B<'Essential'> are the minimal set of columns needed to load and use
the object.  Only the columns in this group will be loaded when an object
is retrieve()'d.  It is typically used to save memory on a class that has
a lot of columns but where we mostly only use a few of them.  It will
automatically be set to B<'All'> if you don't set it yourself.
The 'Primary' column is always part of your 'Essential' group and
Class::DBI will put it there if you don't.

For simplicity we provide private 'primary_column' and '_essential' methods
which return these.

=head2 has_column

	Class->has_column($column);
	$obj->has_column($column);

This will return true if the given $column is a column of the class or
object.

=head1 DATA NORMALIZATION

SQL is largely case insensitive.  Perl is largely not.  This can lead
to problems when reading information out of a database.  Class::DBI
does some data normalization, and provides you some methods for
doing likewise.

=head2 normalize

	$obj->normalize(\@columns);

There is no guarantee how a database will muck with the case of columns,
so to protect against things like DBI->fetchrow_hashref() returning
strangely cased column names (along with table names appended to the
front) we normalize all column names before using them as data keys.

=head2 normalize_hash

	$obj->normalize_hash(\%hash);

Given a %hash, it will normalize all its keys using normalize().  This is
for convenience.

=head1 TRANSACTIONS

In general Class::DBI prefers auto-commit to be turned on in your
database, as there are several problems inherent in operating in a
transactional environment with Class::DBI. In particular:

=over 4

=item 1

Your database handles are B<shared> with possibly many other totally
unrelated classes.  This means if you commit one class's handle you
might actually be committing another class's transaction as well.

=item 2

A single class might have many database handles.  Even worse, if you're
working with a subclass it might have handles you're not aware of!

=back

However, as long as you are aware of these caveats, and try to keep the
scope of your transactions small, preferably down to the scope of a single
method, you should be able to work with transactions with few problems.

A nice idiom for this (courtesy of Dominic Mitchell) is:

	sub do_transaction {
		my $class = shift;
		my ( $code ) = @_;
		# Turn off AutoCommit for this scope.
		# A commit will occur at the exit of this block automatically,
		# when the local AutoCommit goes out of scope.
		local $class->db_Main->{ AutoCommit };

		# Execute the required code inside the transaction.
		eval { $code->() };
		if ( $@ ) {
			my $commit_error = $@;
			eval { $class->dbi_rollback }; # might also die!
			die $commit_error;
		}
	}

	And then you just call:

	Music::DBI->do_transaction( sub {
		my $artist = Artist->create({ name => 'Pink Floyd' });
		my $cd = $artist->add_to_cds({ 
			title => 'Dark Side Of The Moon', 
			year => 1974,
		});
	});

Now either both will get added, or the entire transaction will be
rolled back.

=head1 SUBCLASSING

The preferred method of interacting with Class::DBI is for you to write
a subclass for your database connection, with each table-class inheriting
in turn from it. 

As well as encapsulating the connection information in one place,
this also allows you to override default behaviour or add additional
functionality across all of your classes.

As the innards of Class::DBI are still in flux, you must exercise extreme
caution in overriding private methods of Class::DBI (those starting with
an underscore), unless they are explicitly mentioned in this documentation
as being safe to override. If you find yourself needing to do this,
then I would suggest that you ask on the mailing list about it, and
we'll see if we can either come up with a better approach, or provide
a new means to do whatever you need to do.

=head1 CAVEATS

=head2 Single column primary keys only

Composite primary keys are not yet supported. 

=head2 Don't change the value of your primary column

Altering the primary key column currently causes Bad Things to happen.
I should really protect against this.

=head1 COOKBOOK

I plan to include a 'Cookbook' of typical tricks and tips. Please send
me your suggestions.

=head1 SUPPORTED DATABASES

Theoretically this should work with almost any standard RDBMS. Of course,
in the real world, we know that that's not true. We know that this works
with MySQL, PostgrSQL, Oracle and SQLite, each of which have their own additional
subclass on CPAN that you may with to explore if you're using any of these.

	L<Class::DBI::mysql>, L<Class::DBI::Pg>, L<Class::DBI::Oracle>,
	L<Class::DBI::SQLite>

For the most part it's been reported to work with Sybase. Beyond that
lies The Great Unknown(tm). If you have access to other databases,
please give this a test run, and let me know the results.

This is known not to work with DBD::RAM. As a minimum it requires a
database that supports table aliasing, and a DBI driver that supports
placeholders.

=head1 CURRENT AUTHOR

Tony Bowden <classdbi@tmtm.com>

=head1 AUTHOR EMERITUS

Michael G Schwern <schwern@pobox.com>

=head1 THANKS TO

Tim Bunce, Tatsuhiko Miyagawa, Damian Conway, Uri Gutman, Mike Lambert
and the POOP group.

=head1 SUPPORT

Support for Class::DBI is via the mailing list. The list is used for
general queries on the use of Class::DBI, bug reports, patches, and
suggestions for improvements or new features.

To join the list visit http://groups.kasei.com/mail/info/cdbi-talk

The interface to Class::DBI is fairly stable, but there are still
occassions when we need to break backwards compatability. Such issues
will be raised on the list before release, so if you use Class::DBI in
a production environment, it's probably a good idea to keep a watch on
the list.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

http://poop.sourceforge.net/ provides a document comparing a variety
of different approaches to database persistence, such as Class::DBI,
Alazabo, Tangram, SPOPS etc.

CPAN contains a variety of other modules that can be used with Class::DBI:
L<Class::DBI::Join>, L<Class::DBI::FromCGI>, L<Class::DBI::AbstractSearch>,
L<Class::DBI::View>, L<Class::DBI::Loader> etc.

L<Class::DBI::SAK>, the Swiss Army Knife for Class::DBI attempts to
bring many of these together into one interface.

For a full list see:
	http://search.cpan.org/search?query=Class%3A%3ADBI&mode=module

Class::DBI is built on top of L<Ima::DBI>, L<Class::Accessor> and
L<Class::Data::Inheritable>.

=cut

