package Class::DBI;

require 5.00502;

use strict;

use vars qw($VERSION);
$VERSION = '0.90';

use Class::DBI::Iterator;
use Class::DBI::ColumnGrouper;
use Class::Trigger 0.03;
use UNIVERSAL::require;
use base qw(Class::Accessor Class::Data::Inheritable Ima::DBI);

{
	my %deprecated = (
		croak => "_croak",
		carp => "_carp",
		min => "minimum_value_of",
		max => "maximum_value_of",
		normalize_one => "_normalize_one",
		_primary => "primary_column",
		primary => "primary_column",
		primary_key => "primary_column",
		essential => "_essential",
		column_type => "has_a",
		associated_class => "has_a",
		is_column => "has_column",
		add_hook => "add_trigger",
		run_sql => "retrieve_from_sql",
	);

	no strict 'refs';
	while (my ($old, $new) = each %deprecated) {
		*$old = sub {
			my @caller = caller;
			warn "Use of '$old' is deprecated at $caller[1] line $caller[2]. Use '$new' instead\n";
			goto &$new;
	 	}
	}
}

sub _croak { require Carp; Carp::croak($_[1] || $_[0]) }
sub _carp  { require Carp; Carp::carp($_[1] || $_[0])  }

#----------------------------------------------------------------------
# Our Class Data
#----------------------------------------------------------------------
__PACKAGE__->mk_classdata('__AutoCommit');
__PACKAGE__->mk_classdata('__hasa_columns');
__PACKAGE__->mk_classdata('__hasa_list');
__PACKAGE__->mk_classdata('_table');
__PACKAGE__->mk_classdata('sequence');
__PACKAGE__->mk_classdata('__columns');
__PACKAGE__->mk_classdata('__data_type');
__PACKAGE__->mk_classdata('__on_failed_create');
__PACKAGE__->__columns(Class::DBI::ColumnGrouper->new());
__PACKAGE__->__on_failed_create(sub { die });
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

__PACKAGE__->set_sql('commit', <<"");
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
# SET UP
#----------------------------------------------------------------------

{
	my %Per_DB_Attr_Defaults = (
		mysql  => { AutoCommit => 1 },
		pg     => { AutoCommit => 0, ChopBlanks => 1 },
		oracle => { AutoCommit => 0, ChopBlanks => 1 },
		csv    => { AutoCommit => 1 },
		ram    => { AutoCommit => 1 },
	);

	sub set_db {
		my($class, $db_name, $data_source, $user, $password, $attr) = @_;

		# 'dbi:Pg:dbname=foo' we want 'Pg'. I think this is enough.
		my($driver) = $data_source =~ /^dbi:(.*?):/i;

		# Combine the user's attributes with our defaults.
		$attr = {} unless defined $attr;
		my $default_attr = $Per_DB_Attr_Defaults{lc $driver} || {};
		$attr = { %$default_attr, %$attr };

		_carp("Your database name should be 'Main'") unless $db_name eq "Main";
		$class->SUPER::set_db('Main', $data_source, $user, $password, $attr);
	}
}


sub table {
	my $proto = shift;
	my $class = ref $proto || $proto;
	$class->_table(shift()) if @_;
	return $class->_table || $class->_table($class->_class_name);
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
	$class->__columns(
		Class::DBI::ColumnGrouper
			->clone($class->__columns)
			->add_group($group => @cols)
	);
	$class->_mk_column_accessors(@columns);
	return @cols;
}

sub all_columns { shift->__columns->all_columns }

sub id { my $self = shift; $self->get($self->primary_column) }

sub primary_column { shift->__columns->primary }

sub _essential  { shift->__columns->essential }

sub has_column {
	my ($class, $want) = @_;
	return $class->__columns->exists( $class->_normalized($want) );
}

sub _check_columns {
	my ($class, @cols) = @_;
	$class->has_column($_) or _croak "$_ is not a column of $class" for @cols;
	return 1;
}

sub _groups2cols {
	my ($self, @groups) = @_;
	return $self->_unique_entries(map $self->columns($_), @groups);
}

sub _cols2groups {
	my($self, @cols) = @_;
	my $colg = $self->__columns;
	my %found = map { $_ => 1 } map $colg->groups_for($_), @cols;
	_croak "@cols not in any groups!" unless keys %found;
	return keys %found;
}

sub data_type {
	my $class = shift;
	my %datatype = @_;
	while (my($col, $type) = each %datatype) {
		$class->_add_data_type($col, $type);
	}
}

sub _add_data_type {
	my($class, $col, $type) = @_;
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
	my($class, @columns) = @_;

	my %norm; @norm{@columns} = $class->_normalized(@columns);

	foreach my $col (@columns) {
		my %method = (
			ro => $class->accessor_name($col),
			wo => $class->mutator_name($col)
		);
		my $both = ($method{ro} eq $method{wo});
		foreach my $type (keys %method) {
			my $method = $method{$type};
			my $maker = $both ? "make_accessor" : "make_${type}_accessor";
			my $accessor = $class->$maker($norm{$col});
			my $alias    = "_${method}_accessor";
			$class->_make_method($_, $accessor) for ($method, $alias);
		}
	}
}

sub _make_method {
	my ($class, $name, $method) = @_;
	return if defined &{"$class\::$name"};
	warn "Column '$name' clashes with built-in method" 
		if defined &{"Class::DBI::$name"} 
			and not ($name eq "id" and $class->primary_column eq "id");
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

sub autocommit {
	my $proto = shift;
	ref $proto ? $proto->_obj_autocommit(@_) : $proto->_class_autocommit(@_);
}

sub _obj_autocommit {
	my ($self, $set) = @_;
	my $class = ref $self;
	$self->{__AutoCommit} = $set if defined $set;
	defined $self->{__AutoCommit} 
		? $self->{__AutoCommit} : $class->_class_autocommit;
}

sub _class_autocommit {
	my ($class, $set) = @_;
	$class->__AutoCommit($set) if defined $set;
	return $class->__AutoCommit;
}

sub find_or_create {
	my $class = shift;
	my $hash = ref $_[0] eq "HASH" ? shift : {@_};
	my ($exists) = $class->search(%$hash);
	return $exists || $class->create($hash);
}

sub create {
	my $class = shift;
	my $info = shift or $class->_croak("Can't create nothing");
	_croak 'data to create() must be a hashref' unless ref $info eq 'HASH';
	my @cols = $class->columns('All');
	my %colmap = ();

	foreach my $col (@cols) {
		my $mutator  = $class->mutator_name($col);
		my $accessor = $class->accessor_name($col);
		$colmap{$mutator}  = $col if $mutator  ne $col;
		$colmap{$accessor} = $col if $accessor ne $col;
	}

	$class->normalize_hash($info);
	foreach my $key (keys %$info) {
		if (my $col = $colmap{$key}) { $info->{$col} = delete $info->{$key} }
	}
	return $class->_create($info);
}

sub _create {
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $data  = shift;

	$class->_check_columns(keys %$data);

	my $primary = $class->primary_column;
	$data->{$primary} ||= $class->_next_in_sequence if $class->sequence;

	$class->normalize_hash($data);

	# Build dummy object, flesh it out, and call trigger
	my $self = $class->_init;
	@{$self}{keys %$data} = values %$data;
	$self->call_trigger('before_create');

	# Reinstate data : TODO make _insert_row operate on object, not $data
	$data = { map exists $self->{$_} ? ($_ => $self->{$_}) : (), $self->columns };
	$self->_insert_row($data) or $self->_failed_create; # or _croak "Can't insert row: $@";
	$self->{$primary} = $data->{$primary};
	$self->call_trigger('after_create');
	$self->call_trigger('create'); # For historic reasons...

	# Empty everything back out again!
	delete $self->{$_} for grep $_ ne $self->primary_column, keys %$data;
	return $self;
}

sub _failed_create {
	my $self = shift;
	my $class = ref $self || $self;
	$class->__on_failed_create->();
}

sub on_failed_create { 
	my ($class, $subref) = @_;
	ref($subref) eq "CODE" or _croak "On failed create needs a subref";
	$class->__on_failed_create($subref);
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
	return $self->_find_primary_value(
		$self->sql_Nextval($self->sequence)
	);
}

sub _auto_increment_value { shift->db_Main->{mysql_insertid} }

sub _insert_row {
	my $self = shift;
	my $class = ref($self);
	my $data = $self->_tidy_creation_data(shift);
	eval {
		my $sth = $self->sql_MakeNewObj(
			$self->table,
			join(', ', keys %$data),
			join(', ', map $self->_column_placeholder($_), keys %$data),
		);
		$class->_bind_param($sth, [ keys %$data ]);
		$sth->execute(values %$data);
		$data->{$self->primary_column} ||= $self->_auto_increment_value;
	};
	if($@) {
		$self->DBIwarn("New $class", 'MakeNewObj');
		return;
	}
	return 1;
}

sub _bind_param {
	my($class, $sth, $keys) = @_;
	my $datatype = $class->__data_type;
	for my $i (0..$#$keys) {
		if (my $type = $datatype->{$keys->[$i]}) {
			$sth->bind_param($i + 1, undef, $type);
		}
	}
}

sub new   { my $proto = shift; $proto->create(@_); }
sub _init { my $class = shift; bless { __Changed => {} }, $class; }

sub retrieve {
	my $class = shift;
	my $id = shift;
	return unless defined $id;
	_croak "Cannot retrieve a reference" if ref($id);
	my @rows = $class->search($class->primary_column => $id);
	return $rows[0];
}

# Get the data, as a hash, but setting certain values to whatever
# we pass. Used by copy() and move().
# This can take either a primary key, or a hashref of all the columns
# to change.
sub _data_hash {
	my $self     = shift;
	my @columns  = $self->columns;
	my %data; @data{@columns} = $self->get(@columns);
	delete $data{$self->primary_column};
	if (@_) {
		my $arg = shift;
		my %arg = ref($arg) ? %$arg : ( $self->primary_column => $arg );
		@data{keys %arg} = values %arg;
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
	_croak("construct() is a protected method of Class::DBI")
		unless caller->isa("Class::DBI");

	my @wantcols = $class->_normalized(keys %$data);
	my $self = $class->_init;
	@{$self}{@wantcols} = values %$data;
	$self->call_trigger('select');
	return $self;
}

sub move {
	my $class = shift;
	my $old_obj = shift;
	_croak "You can only move to a related class"
		unless $class->isa(ref $old_obj) or $old_obj->isa($class);
	return $class->create($old_obj->_data_hash(@_));
}

sub delete {
	my $self = shift;
	$self->call_trigger('before_delete');
	$self->call_trigger('delete'); # For historic reasons...
	$self->_cascade_delete;
	eval {
		my $sth = $self->sql_DeleteMe($self->table, $self->columns('Primary'));
		$sth->execute($self->id);
	};
	if($@) {
		$self->DBIwarn($self->id, 'Delete');
		return;
	}
	$self->call_trigger('after_delete');
	undef %$self;
	bless $self, 'Class::Deleted';
	return 1;
}

sub _cascade_delete {
	my $self = shift;
	my $class = ref($self);
	my %cascade = %{$class->__hasa_list || {}};
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

sub commit {
	my $self = shift;
	my $class = ref($self) or _croak "commit() called as class method";

	$self->call_trigger('before_update');
	if (my @changed_cols = $self->is_changed) {
		my $sth = $self->sql_commit($self->table, $self->_commit_line, $self->primary_column);
		$class->_bind_param($sth, [ $self->is_changed ]);
		eval {
			$sth->execute($self->_commit_vals, $self->id);
		};
		if ($@) {
			$self->DBIwarn("Cannot commit: $@", "commit");
			return;
		}
		$self->{__Changed} = {};
		# Repopulate ourselves.
		delete $self->{$_} for @changed_cols;
		$self->_flesh('All');
	}
	$self->call_trigger('after_update');
	return 1;
}

sub _commit_line {
	my $self = shift;
	join(', ', map "$_ = " . $self->_column_placeholder($_), $self->is_changed)
}

sub _commit_vals {
	my $self = shift;
	map $self->{$_}, $self->is_changed;
}

sub DESTROY {
	my($self) = shift;
	if( my @changes = $self->is_changed ) {
		_carp ($self->id .' in class '. ref($self) .
			' destroyed without saving changes to column(s) '.
			join(', ', map { "'$_'" } @changes) . ".");
	}
}

sub rollback {
	my $self = shift;
	my $class = ref $self;
	_croak 'rollback() used while autocommit is on' if $self->autocommit;
	delete $self->{$_} foreach $self->is_changed;
	$self->{__Changed} = {};
	return 1;
}

# We override the get() method from Class::Accessor to fetch the data for
# the column (and associated) columns from the database, using the _flesh()
# method. We also allow get to be called with a list of keys, instead of
# just one.

sub get {
	my($self, @keys) = @_;
	_croak "Can't fetch data as class method" unless ref $self;
	_croak "Can't get() nothing!" unless @keys;

	if (my @fetch_cols = grep !exists $self->{$_}, @keys) {
		$self->_flesh($self->_cols2groups(@fetch_cols));
	}

	return $self->{$keys[0]} if @keys == 1;
	return @{$self}{@keys};
}

sub _flesh {
	my ($self, @groups) = @_;
	my @want = grep !exists $self->{$_}, $self->_groups2cols(@groups);
	if (@want) {
		my $sth = $self->_run_query('Flesh', $self->primary_column, $self->id, \@want);
		my @row = $sth->fetchrow_array;
		$sth->finish;
		@{$self}{@want} = @row;
		$self->call_trigger('select');
	}
	return 1;
}

# We also override set() from Class::Accessor so we can keep track of
# changes, and either write to the database now (if autocommit is on),
# or when commit() is called.
sub set {
	my ($self, $key, $value) = @_;
	my $class = ref($self);
	$self->SUPER::set($key, $value);
	eval { $self->call_trigger('on_setting') };
	if ($@) { delete $self->{$key}; die $@; }
	# We increment instead of setting to 1 because it might be useful to
	# someone to know how many times a value has changed between commits.
	$self->{__Changed}{$key}++ if $class->has_column($key);
	$self->commit if $self->autocommit;
	return 1;
}

sub is_changed { keys %{shift->{__Changed}} }

# We override set_sql() from Ima::DBI so it has a default database connection.
sub set_sql {
	my ($class, $name, $sql, $db) = @_;
	$db = 'Main' unless defined $db;
	$class->SUPER::set_sql($name, $sql, $db);
}

sub dbi_commit   { my $proto = shift; $proto->SUPER::commit(@_);   }
sub dbi_rollback { my $proto = shift; $proto->SUPER::rollback(@_); }

#----------------------------------------------------------------------
# Constraints
#----------------------------------------------------------------------
sub add_constraint {
	my $class = shift;
	$class->_invalid_object_method('add_constraint()') if ref $class;
	my $name = shift or $class->_croak("Constraint needs a name");
	my $column = shift or $class->_croak("Constraint needs a column");
	$class->_check_columns($column);
	my $code = shift or $class->_croak("Constraint needs a code reference");
	ref($code) eq "CODE" or $class->_croak("$code is not a code reference");
	my $constraint = sub {
		my $self = shift;
		my $value = $self->$column();
		$code->($value) 
			or die "$column fails '$name' constraint with $value";
	};
	$class->add_trigger(
		before_create => $constraint,
		on_setting    => $constraint,
	);
}

#----------------------------------------------------------------------
# Inflation
#----------------------------------------------------------------------
sub has_a {
	my ($class, $column, $a_class, %meths) = @_;
	%meths = () unless keys %meths;
	$class->_invalid_object_method('has_a()') if ref $class;
	$class->_check_columns($column);
	$column = $class->_normalized($column);
	$class->_croak("$column needs an associated class") unless $a_class;
	$a_class->require;
 	$class->add_trigger(select        => _inflate_to_object($column => $a_class, %meths));
 	$class->add_trigger(on_setting    => _inflate_to_object($column => $a_class, %meths));
	$class->add_trigger(before_create => _deflate_object($column => $a_class, %meths));
	$class->add_trigger(before_update => _deflate_object($column => $a_class, %meths));
}

sub _inflate_to_object {
	my ($col, $a_class, %meths) = @_;
	return sub {
		my $self = shift;
		return if not defined $self->{$col};
		if (my $obj = ref $self->{$col}) {
			UNIVERSAL::isa($obj, $a_class) ? return : die "$obj is not a $a_class";
		}
		my $get = $meths{'inflate'} 
			|| ($a_class->isa('Class::DBI') ? "retrieve" : "new");
		my $obj = (ref $get eq "CODE")
			? $get->($self->{$col}) 
			: $a_class->$get($self->{$col})
			or die "No such $a_class: $self->{$col}";
		$self->{$col} = $obj;
	}
}

sub _deflate_object {
	my ($col, $a_class, %meths) = @_;
	my $deflate = $meths{'deflate'} || '';
	return sub {
		my $self = shift;
		my $obj = $self->{$col};
		return $obj unless ref $obj;
		die "$obj is not a $a_class" unless UNIVERSAL::isa($obj, $a_class);
		$self->{$col} = 
			UNIVERSAL::isa($obj, 'Class::DBI') ? $obj->id  : 
			$deflate                           ? $obj->$deflate()
                                         : "$obj";
	}
}

#----------------------------------------------------------------------
# SEARCH
#----------------------------------------------------------------------

sub search_like { shift->_do_search(LIKE => @_) }
sub search      { shift->_do_search("="  => @_) }

sub _do_search {
	my ($proto, $search_type, @args) = @_;
	my $class = ref $proto || $proto;
	@args = %{$args[0]} if ref $args[0] eq "HASH"; 
	my (@cols, @vals);
	while (my ($col, $val) = splice @args, 0, 2) {
		$col = $class->_normalized($col) or next;
		$class->_check_columns($col);
		push @cols, $col;
		push @vals, $val;
	}
	my $sql = join " AND ", map " $_ $search_type ? ", @cols;
	return $class->retrieve_from_sql($sql => @vals);
}

sub retrieve_from_sql {
	my ($proto, $sql, @vals) = @_;
	my $class = ref $proto || $proto;
	my $sth = $class->_run_query(SearchSQL => [$sql], \@vals) or die "No sth";
	return $class->sth_to_objects($sth);
}


#----------------------------------------------------------------------
# CONSTRUCTORS
#----------------------------------------------------------------------

__PACKAGE__->add_constructor(retrieve_all => '');
__PACKAGE__->make_filter(ordered_search => '%s = ? ORDER BY %s');
__PACKAGE__->make_filter(between => '%s >= ? AND %s <= ?');

sub add_constructor {
	shift->_make_query(_run_constructor => @_);
}

sub make_filter {
	shift->_make_query(_run_filter => @_);
}

sub _make_query { 
	my $class = shift;
	my $runner = shift;
	$class->_invalid_object_method('add_constructor()') if ref $class;
	my $method = shift or _croak("make_filter() needs a method name");
	defined &{"$class\::$method"} and return _carp("$method() already exists");
	# Create the query
	my $fragment = shift;
	my $query = "SELECT %s FROM %s";
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
		@cols = map $class->_normalized($_), @{shift()};
		$class->_check_columns(@cols);
		@vals = @{shift()};
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
		 @args = %{$args[0]} if ref $args[0] eq "HASH"; # Uck.
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
	my (%data, @rows);
	$sth->bind_columns( \( @data{ @{$sth->{NAME} } } ));
	push @rows, { %data } while $sth->fetch;
	return $class->_ids_to_objects(\@rows);
}
*_sth_to_objects = \&sth_to_objects;


sub _ids_to_objects {
	my ($class, $data) = @_;
	return defined wantarray 
			? wantarray 
				? map $class->construct($_), @$data
				: Class::DBI::Iterator->new($class => $data)
		 	: $#$data + 1;
}

# my $sth = $self->_run_query($query, $select_col, $select_val, $return_col);
# Runs the query set up as $query, e.g.
#
# SELECT %s
# FROM   %s
# WHERE  %s = ?
#
# Substituting the values for $return_col, $class->table and $select_col
# into the query via sprintf and executing with $select_val.
# 
# If any of $select_col, $select_val or $return_col are list references they
# will be expanded accordingly.
# 
# If $return_col is not specified, then 'Essential' will be used instead.

sub _run_query {
	my $proto = shift;
	my $class = ref $proto || $proto;
	my ($type, $sel, $val, $col) = @_;

	$class->_croak("No database connection defined") 
		unless $class->can('db_Main');
	my @sel_cols = ref $sel ? @$sel : ($sel);
	my @sel_vals = ref $val ? @$val : ($val);

	# croak "Number of placeholders must equal the number of columns"
	# unless @sel_cols == @sel_vals;

	my @ret_cols = $col
		 ? ref $col ? @$col : ($col)
		 : $class->_essential;

	my $sql_method = "sql_$type";
	my $cols = join ", ", @ret_cols;

	my $sth;
	eval {
		$sth = $class->$sql_method($cols, $class->table, @sel_cols);
		$sth->execute(@sel_vals);
	};
	if($@) {
		$class->DBIwarn("$type in $class" => $sth->{Statement});
		return;
	}
	return $sth;
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
	$class->_single_value_select("MAX($col)")
}

sub minimum_value_of {
	my ($class, $col) = @_;
	$class->_single_value_select("MIN($col)")
}

sub _single_value_select {
	my ($class, $select) = @_;
	my $sth;
	my $val = eval {
		$sth = $class->sql_single($select, $class->table);
		$sth->execute;
		my @row = $sth->fetchrow_array;
		$row[0];
	};
	if ($@) {
		$class->DBIwarn('single value select', $sth->{Statement});
		return;
	}
	return $val;
}

#----------------------------------------------------------------------
# NORMALIZATION
#----------------------------------------------------------------------
sub _normalized {
	my $self = shift;
	my @data = @_;
	my @return = map {
		s/^.*\.//;   # Chop off the possible table & database names.
		tr/ \t\n\r\f\x0A/______/; # Translate whitespace to _
		lc;
	} @data;
	return wantarray ? @return : $return[0];
}

sub normalize {
	my($self, $colref) = @_;
	_croak "Normalize needs a listref" unless ref $colref eq 'ARRAY';
	$_ = $self->_normalized($_) foreach @$colref;
	return 1;
}

sub _normalize_one {
	my ($self, $col) = @_;
	$$col = $self->_normalized($$col);
}

sub normalize_hash {
		my($self, $hash) = @_;
		my(@normal_cols, @cols);

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
	_carp "$method should be called as a class method not an object method";
}

#----------------------------------------------------------------------
# RELATIONSHIPS
#----------------------------------------------------------------------

sub hasa {
	my ($class, $f_class, $f_col) = @_;
	$f_class->require;

	# Store the relationship
	my $hasa_columns = $class->__hasa_columns || {};
		 $hasa_columns->{$f_col} = $f_class;
	$class->__hasa_columns($hasa_columns);

	my $obj_key = "__${f_class}_${f_col}_Obj";
	$class->columns($obj_key, $f_col);

	my $method = {
		ro => $class->accessor_name($f_col),
		wo => $class->mutator_name($f_col),
	};

	{
		my $for_acc = "_" . $method->{ro} . "_accessor";
		my $for_mut = "_" . $method->{wo} . "_accessor";
		my $mutator = sub {
			my $self = shift;
			my $obj = shift;
			$self->_croak("'$obj' is not an object of type '$f_class'") 
				unless ref $obj eq $f_class;
			$self->{$obj_key} = $obj;
			$self->$for_mut($obj->id);
		};

		my $accessor = sub {
			my $self = shift;
			die "Can't set via $method->{ro}" if @_;
			if (not defined $self->{$obj_key}) {
				my $obj_id = $self->$for_acc() or return;
				$self->{$obj_key} = $f_class->retrieve($obj_id) or
					$self->_croak("Can't retrieve $f_class ($obj_id)");
			}
			return $self->{$obj_key};
		};

		my $common = sub {
			my $self = shift;
			$mutator->($self, @_) if @_;
			return $accessor->($self);
		};

		{
			local $SIG{__WARN__} = sub {};
			no strict 'refs';

			if ($for_acc eq $for_mut) {
				*{"$class\::$method->{ro}"} = $common;
			} else {
				*{"$class\::$method->{ro}"} = $accessor;
				*{"$class\::$method->{wo}"} = $mutator;
			}
		}
	} 
	return 1;
}

sub _tidy_creation_data {
	my ($class, $data) = @_;
	my $hasa_cols = $class->__hasa_columns || {};
	$class->normalize_hash($hasa_cols);
	foreach my $col (keys %$hasa_cols) {
		next unless exists $data->{$col} and ref $data->{$col};
		my $want_class = $hasa_cols->{$col};
		my $obj = $data->{$col};
		$class->_croak("$obj is not a $want_class")
			unless $obj->isa($want_class);
		$data->{$col} = $obj->id;
	}
	return $data;
}


#----------------------------------------------------------------------
# has many stuff
#----------------------------------------------------------------------

sub hasa_list {
	my $class = shift;
	$class->has_many(@_[2, 0, 1], { nohasa => 1 });
}

sub has_many {
	my ($class, $accessor, $f_class, $f_key, $args) = @_;
	$class->_croak("has_many needs an accessor name") unless $accessor;
	$class->_croak("has_many needs a foreign class") unless $f_class;
	$class->can($accessor) 
		and return $class->_carp("$accessor method already exists in $class\n");

	my $f_method = "";
	if (ref $f_class eq "ARRAY") {
		($f_class, $f_method) = @$f_class;
	}
	$f_class->require;

	if (ref $f_key eq "HASH") { # didn't supply f_key, this is really $args
		$args = $f_key;
		$f_key = "";
	}

	$f_key ||= $class->_class_name;

	if (ref $f_key eq "ARRAY") {
		$class->_croak("Multiple foreign keys not implemented") if @$f_key > 1;
		$f_key = $f_key->[0];
	}
	$class->_extend_hasa_list($f_class => $f_key);

	{
		no strict 'refs';
		*{"$class\::$accessor"} = sub {
			my $self = shift;
			$self->_croak("$accessor is read-only") if @_;
			# Need to preserve context, in case of iterator request
			return defined $args->{sort} 
				? $f_method 
					? map $_->$f_method(), $f_class->ordered_search(
							$f_key => $self->id, 
							$args->{sort} => undef,
						)
					: $f_class->ordered_search(
							$f_key => $self->id,
							$args->{sort} => undef,
						)

				: $f_method 
					? map $_->$f_method(),
							$f_class->search($f_key => $self->id)
					: $f_class->search($f_key => $self->id)
		};

		my $creator = "add_to_$accessor";
		*{"$class\::$creator"} = sub {
			my ($self, $data) = @_;
			my $class = ref($self) or _croak "$creator called as class method";
			_croak "$creator needs data" unless ref($data) eq "HASH";
			$data->{$f_key} = $self->id;
			$f_class->create($data);
		};
	}
}

sub _extend_hasa_list {
	my $class = shift;
	$class->_extend_class_data(__hasa_list => @_)
}

#----------------------------------------------------------------------
# might have
#----------------------------------------------------------------------

# Video->might_have(plot => Videolog::Plot => (import methods));

sub might_have {
	my ($class, $method, $foreign_class, @methods) = @_;
	$foreign_class->require;
	$class->add_trigger(before_update => sub { shift->$method()->commit });
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
	my $hashref = $class->$struct() || {};
		 $hashref->{$key} = $value;
	$class->$struct($hashref);
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
	$cd->commit;

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
the documentation of your particular database for details.

=item I<Set up a table for your objects to be stored in.>

Class::DBI works on a simple one class/one table model.  It is your
responsibility to have your database already set up. Automating that
process is outside the scope of Class::DBI.

Using our CD example, you might declare a table something like this:

	CREATE TABLE cd (
		cdid   INTEGER   PRIMARY KEY,
		artist INTEGER, # references 'artist'
		title  VARCHAR(255),
		year   CHAR(4),
	);

=item I<Inherit from Class::DBI.>

It is prefered that you use base.pm to do this rather than setting
@ISA, as your class may have to inherit some protected data fields.

	package CD;
	use base 'Class::DBI';

=item I<Declare a database connection>

Class::DBI needs to know how to access the database.  It does this
through a DBI connection which you set up.  Set up is by calling the
set_db() method and declaring a database connection named 'Main'.
(Note that this connection MUST be called 'Main', and so Class::DBI will
actually ignore this argument and pass 'Main' up to Ima::DBi anyhow).

	CD->set_db('Main', 'dbi:mysql', 'user', 'password');

We also set up some default attributes depending on the type of database
we're dealing with: For instance, if MySQL is detected, AutoCommit will
be turned on, whereas under Oracle, ChopBlanks is turned on. The defaults
can be extended or overriden by passing your own $attr hashref as the
5th argument.

[See L<Ima::DBI> for more details on set_db()]

=item I<Declare the name of your table>

Inform Class::DBI what table you are using for this class:

	CD->table('cd');

=item I<Declare your columns.>

This is done using the columns() method. In the simplest form, you tell
it the name of all your columns (primary key first):

	CD->columns(All => qw/cdid artist title year/);

For more information about how you can more efficiently declare your
columns, L<"Lazy Population">

=item I<Done.>

That's it! You now have a class with methods to create(), retrieve(),
copy(), move(), search() for and delete() objects from your table, as well
as accessors and mutators for each of the columns in that object (row).

=back

Let's look at all that in more detail:

=head1 CLASS METHODS

=head2 set_db

	__PACKAGE__->set_db('Main', $data_source, $user, $password, \%attr);

For details on this method, L<Ima::DBI>.

The special connection named 'Main' must always be set.  Connections
are inherited.

It's often wise to set up a "top level" class for your entire application
to inherit from, rather than directly from Class::DBI.  This gives you
a convenient point to place system-wide overrides and enhancements to
Class::DBI's behavior.  It also lets you set the Main connection in one
place rather than scattering the connection info all over the code.

	package My::Class::DBI;

	use base 'Class::DBI';
	__PACKAGE__->set_db('Main', 'dbi:foo', 'user', 'password');

	package My::Other::Thing;
	use base 'My::Class::DBI';

Class::DBI helps you along a bit to set up the database connection.
set_db() normally provides its own default attributes on a per database
basis.  For instance, if MySQL is detected, AutoCommit will be turned on.
Under Oracle, ChopBlanks is turned on.  As more databases are tested,
more defaults will be added.

The defaults can always be overridden by supplying your own %attr.

=head2 table

	__PACKAGE__->table($table);

	$table = Class->table;
	$table = $obj->table;

An accessor to get/set the name of the database table in which this
class is stored.  It -must- be set.

Table information is inherited by subclasses, but can be overridden.

=head2 sequence

	__PACKAGE__->sequence($sequence_name);

	$sequence_name = Class->sequence;
	$sequence_name = $obj->sequence;

If you are using a database which supports sequences, then you should
declare this using the sequence() method.

		__PACKAGE__->columns(Primary => 'id');
		__PACKAGE__->sequence('class_id_seq');

Class::DBI will use the sequence to generate primary keys when objects
are created yet the primary key is not specified.

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

If the primary column is not in %data, create() will assume it is to be
generated.  If a sequence() has been specified for this Class, it will
use that.  Otherwise, it will assume the primary key can be generated
by AUTO_INCREMENT and attempt to use that.

If the class has declared relationships with foreign classes via
has_a(), you can pass an object to create() for the value of that key.
Class::DBI will Do The Right Thing.

If the create() fails, then by default we throw a fatal exception. If
you wish to change this behaviour, you can set up your own subroutine
to be called at this point using 'on_failed_create'. For example, to do
nothing at all you would set up:

	__PACKAGE__->on_failed_create( sub { } );

=head2 find_or_create

	my $cd = CD->find_or_create({ artist => 'U2', title => 'Boy' });

This checks if a CD can be found to match the information passed, and
if not creates it. 

=head2 delete

	$obj->delete;

Deletes this object from the database and from memory. If you have set up
any relationships using has_many, this will delete the foreign elements
also, recursively (cascading delete).

$obj is no longer usable after this call.

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
which can return the objects required one at a time. This should help
considerably with memory when accessing a large number of search results.

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

=head1 COPY AND MOVE

=head2 copy

	$new_obj = $obj->copy;
	$new_obj = $obj->copy($new_id);
	$new_obj = $obj->copy({ title => 'new_title', rating => 18 });

This creates a copy of the given $obj both in memory and in the
database.  The only difference is that the $new_obj will have a new
primary identifier.

A new value for the primary key can be suppiler, otherwise the
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

For transfering objects from one class to another.  Similar to copy(), an
instance of Sub::Class is created using the data in $old_obj (Sub::Class
is a subclass of $old_obj's subclass).  Like copy(), you can supply
$new_id as the primary key of $new_obj (otherwise the usual sequence or
autoincrement is used), or a hashref of multiple new values.

=head1 TRIGGERS

	__PACKAGE__->add_trigger(before_create => \&call_before_create);
	__PACKAGE__->add_trigger(after_create  => \&call_after_create);

	__PACKAGE__->add_trigger(before_delete => \&call_before_delete);
	__PACKAGE__->add_trigger(after_delete  => \&call_after_delete);

	__PACKAGE__->add_trigger(before_update => \&call_before_update);
	__PACKAGE__->add_trigger(after_update  => \&call_after_update);

	__PACKAGE__->add_trigger(select        => \&call_after_select);

It is possible to set up triggers that will be called immediately after
a SELECT, or either side of a DELETE, UPDATE or CREATE. You can create
any number of triggers for each point, but you cannot specify the order
in which they will be run. Each will be passed the object being dealt
with (whose values you may change if required), and return values will
be ignored. 

=head1 CONSTRAINTS

	__PACKAGE__->add_constraint('name', column => \&check_sub);

	# e.g.

	__PACKAGE__->add_constraint('over18', age => \&check_age);

	sub check_age { 
		my $value = shift;
		return $value >= 18;
	}

It is also possible to set up constraints on the values that can be set
on a column. Attempting to create a object where this constraint fails,
or to update the value of an existing object with an invalid value,
will result in an error.

Note 1: This will only prevent you from setting these values through a
the provided create() or set() methods. It will always be possible to
bypass this if you try hard enough.

=head1 INSTANCE METHODS

=head2 accessors

Class::DBI inherits from Class::Accessor and thus provides accessor
methods for every column in your subclass.  It overrides the get()
and set() methods provided by Accessor to automagically handle database
writing.

=head2 changing your accessor names

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

=head2 manual vs auto commit

There are two modes for the accessors to work in.  Manual commit and
autocommit.  This is sort of analagous to the manual vs autocommit in
DBI, but is not implemented in terms of this.  What it simply means
is this... when in autocommit mode every time one calls an accessor to
make a change the change will immediately be written to the database.
Otherwise, if autocommit is off, no changes will be written until commit()
is explicitly called.

This is an example of manual committing:

		# The calls to NumExplodingSheep() and Rating() will only make the
		# changes in memory, not in the database.  Once commit() is called
		# it writes to the database in one swell foop.
		$gone->NumExplodingSheep(5);
		$gone->Rating('NC-17');
		$gone->commit;

And of autocommitting:

		# Turn autocommitting on for this object.
		$gone->autocommit(1);

		# Each accessor call causes the new value to immediately be written.
		$gone->NumExplodingSheep(5);
		$gone->Rating('NC-17');

Manual committing is probably more efficient than autocommiting and
it provides the extra safety of a rollback() option to clear out all
unsaved changes.  Autocommitting is more convient for the programmer.

If changes are left uncommitted or not rolledback when the object is
destroyed (falls out of scope or the program ends) then Class::DBI's
DESTROY method will print a warning about unsaved changes.

=head2 autocommit

		__PACKAGE__->autocommit($on_or_off);
		$commit_style = Class->autocommit;

		$obj->autocommit($on_or_off);
		$commit_style = $obj->autocommit;

This is an accessor to the current style of autocommitting.  When called
with no arguments it returns the current autocommitting state, true for
on, false for off.  When given an argument it turns autocommiting on
and off.  A true value turns it on, a false one off.  When called as a
class method it will control the committing style for every instance of
the class.  When called on an individual object it will control committing
for just that object, overriding the choice for the class.

	__PACKAGE__->autocommit(1);     # Autocommit is now on for the class.

	$obj = Class->retrieve('Aliens Cut My Hair');
	$obj->autocommit(0);      # Shut off autocommitting for this object.

The commit setting for an object is not stored in the database.

Autocommitting is off by default.

B<NOTE> This has I<nothing> to do with DBI's AutoCommit attribute.

=head2 commit

		$obj->commit;

Any changes you make to your object are gathered together, and only sent
to the database upon a commit() call.

Note: If you have transactions turned on (but see L<"TRANSACTIONS"> below) 
you will need to also call dbi_commit(), as this commit() merely calls
UPDATE on the database).

If you call commit() when autocommit is on, it'll just silently do
nothing.

=head2 rollback

	$obj->rollback;

Removes any changes you've made to this object since the last commit.
Currently this simply reloads the values from the database.  This can
have concurrency issues.

If you're using autocommit this method will throw an exception.

=head2 is_changed

	my $changed = $obj->is_changed;
	my @changed_keys = $obj->is_changed;

Indicates if the given $obj has uncommitted changes.  Returns a list of
keys which have changed.

=head2 id

	$id = $obj->id;

Returns a unique identifier for this object.  It's the equivalent of
$obj->get($self->columns('Primary'));

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

has_a(), might_have() and has_many() will try to require the relevant
foreign class for you.  If the require fails, it will assume it's not a
simple require (ie. Foreign::Class isn't in Foreign/Class.pm) and that
you've already taken care of it and ignore the warning.

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
		SELECT artist.id, SUM(cd.id) AS cds
		  FROM artist, cd
		 WHERE artist.id = cd.artist
		 GROUP BY artist.id
		 ORDER BY cds DESC
		 LIMIT 10
	});

Then you can set up a method that executes these are returns the relevant
objects:

  sub top_ten {
    my $class = shift;
    my $sth = $class->sql_top_ten;
       $sth->execute;
    return $class->sth_to_objects($sth);
  }

The $sth which we use to return the objects here is a normal DBI-style
statement handle, sof if your results can't even be turned into objects
easily, you can still call $sth->fetchrow_array etc and return whatever
data you choose.

If you want to write new methods which are inheritable by your subclasses
you must be careful not to hardcode any information about your class's
table name or primary key, and instead use the table() and columns()
methods instead.

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

		CD->columns(Primary   => 'cdid');
		CD->columns(Essential => qw/artist title/);
		CD->columns(Others    => qw/year runlength/);

Now when you fetch back a CD it will come pre-loaded with the 'artist'
and 'title' fields. Fetching the 'year' will mean another visit to
the database, but will bring back the 'runlength' whilst it's there.
This can potentially increase performance.

If you don't like this behavior, then just add all your columns to the
'All' group, and Class::DBI will load everything at once.

=head2 columns

	my @all_columns  = $class->columns;
	my @columns      = $class->columns($group);

	my $primary      = $class->primary_column;
	my @essential    = $class->_essential;

There are three 'reserved' groups.  'All', 'Essential' and 'Primary'.

B<'All'> are all columns used by the class.  If not set it will be
created from all the other groups.

B<'Primary'> is the single primary key column for this class.  It I<must>
be set before objects can be used.  (Multiple primary keys are not
supported).  If 'All' is given but not 'Primary' it will assume
the first column in 'All' is the primary key.

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

Class::DBI does not cope well with transactions, much preferring
auto-commit to be turned on in your database. In particular:

=over 4

=item 1

Your database handles are B<shared> with possibly many other totally
unrelated classes.  This means if you commit one class's handle you
might actually be committing another class's transaction as well.

=item 2

A single class might have many database handles.  Even worse, if you're
working with a subclass it might have handles you're not aware of!

=back

There no plans in the near future to improve this situation. If you find
yourself using Class::DBI in a transactional environment, you should
try to keep the scope of your transactions small, preferably down to the
scope of a single method. You may also wish to explore the commit() and
rollback() methods of Ima::DBI. (To disambiguate from the commit() and
rollback() method in Class::DBI which express very different concepts,
we provide dbi_commit() and dbi_rollback() as thin wrappers to the
Ima::DBI versions.)

=head1 CAVEATS

=head2 Single column primary keys only

Composite primary keys are not supported. There are currently no plans
to change this, unless someone really wants to convince me otherwise.

=head2 Don't change the value of your primary column

Altering the primary key column currently causes Bad Things to happen.
I should really protect against this.

=head1 TODO

=head2 Cookbook

I plan to include a 'Cookbook' of typical tricks and tips. Please send
me your suggestions.

=head2 Make all internal statements use fully-qualified columns

=head1 SUPPORTED DATABASES

Theoretically this should work with almost any standard RDBMS. Of course,
in the real world, we know that that's not true. We know that this works
with MySQL, PostgrSQL and SQLite, each of which have their own additional
subclass on CPAN that you may with to explore if you're using any of these.


	L<Class::DBI::mysql>, L<Class::DBI::Pg>, L<Class::DBI::SQLite>

For the most part it's been reported to work with Oracle and
Sybase. Beyond that lies The Great Unknown(tm). If you have access to
other databases, please give this a test run, and let me know the results.

This is known not to work with DBD::RAM

=head1 CURRENT AUTHOR

Tony Bowden <classdbi@tmtm.com>

=head1 AUTHOR EMERITUS

Michael G Schwern <schwern@pobox.com>

=head1 THANKS TO

Uri Gutman, Damian Conway, Mike Lambert, Tatsuhiko Miyagawa and the
POOP group.

=head1 MAILING LISTS

There are two mailings lists devoted to Class::DBI, a 'users' list for
general queries on the use of Class::DBI, bug reports, and suggestions
for improvements or new features, and a 'developers' list for more
detailed discussion on the innards, and technical details of implementing
new ideas.

To join the users list visit http://groups.kasei.com/mail/info/cdbi-talk.

To join the developers list visit http://groups.kasei.com/mail/info/cdbi-dev.  

=head1 TALK TO ME

If you use this in production code, you might like to consider mailing
me at L<classdbi@tmtm.com> to let me know. Then, if I decide to change
the interface to anything, I'll let you know first.

I like getting feedback anyway, so feel free to mail me if you use this at
all, and like it, or don't use it because you don't like it. Or whatever.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

http://poop.sourceforge.net/ provides a document comparing a variety
of different approaches to database persistence, such as Class::DBI,
Alazabo, Tangram, SPOPS etc.

CPAN contains a variety of other modules that can be used with Class::DBI:
L<Class::DBI::Join>, L<Class::DBI::FromCGI> etc.

For a full list see:
  http://search.cpan.org/search?query=Class%3A%3ADBI

Class::DBI is built on top of L<Ima::DBI>, L<Class::Accessor> and
L<Class::Data::Inheritable>.

=cut

