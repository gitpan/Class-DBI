package Class::DBI;

=head1 NAME

  Class::DBI - Simple Database Abstraction

=head1 SYNOPIS and DESCRIPTION

The main user-guide for Class::DBI can be found in
L<Class::DBI::Tutorial>. You should probably be reading that instead
of this.

The documention in this package provides more advanced information for
writing more complex subclasses.

=head1 METHODS

=cut

require 5.00502;

use strict;

use vars qw($VERSION);
$VERSION = '0.30';

use Carp::Assert;
use base qw(Class::Accessor Class::Data::Inheritable Ima::DBI
            Class::Fields::Fuxor Class::Fields);
use Class::Fields::Attribs;

use protected qw(__Changed __AutoCommit);

use constant TRUE       => (1==1);
use constant FALSE      => !TRUE;
use constant SUCCESS    => TRUE;
use constant FAILURE    => FALSE;
use constant YES        => TRUE;
use constant NO         => FALSE;

sub croak { require Carp; Carp::croak(@_) }
sub carp  { require Carp; Carp::carp(@_)  }

=head2 create

This is a constructor to create a new object and store it in the
database.  It calls _insert_row with the hashref, which in turn will
call _next_in_sequence if applicable. The hasa() checks should be split
out into another helper method.

=cut

__PACKAGE__->set_sql('MakeNewObj', <<'', 'Main');
INSERT INTO %s
       (%s)
VALUES (%s)

__PACKAGE__->set_sql('LastInsertID', <<'', 'Main');
SELECT LAST_INSERT_ID()

__PACKAGE__->set_sql('Nextval', <<'', 'Main');
SELECT NEXTVAL ('%s')

sub create {
  my $proto = shift;
  my $class = ref $proto || $proto;
  my $table = $class->table or croak "Can't create without a table";
  my $self  = $class->_init;
  my $data  = shift;
  croak 'data to create() must be a hashref' unless ref $data eq 'HASH';
  $self->normalize_hash($data);

  $self->has_column($_) or croak "$_ is not a column" foreach keys %$data;

  # If a primary key wasn't given, use the sequence if we have one.
  if( $self->sequence && !_safe_exists($data, $self->primary) ) {
    $data->{$self->primary} = $self->_next_in_sequence;
  }

  # Look for values which can be objects.
  my $hasa_cols = $class->__hasa_columns || {};
  $class->normalize_hash($hasa_cols);

  # For each column which can be an object (ie. hasa() was set) see if
  # we were given an object and replace it with its id().
  while( my($col, $want_class) = each %$hasa_cols) {
    if (_safe_exists($data, $col) && ref $data->{$col}) {
      my $obj = $data->{$col};
      unless( $obj->isa($want_class) ) {
        croak sprintf
          "$class expects an object of class $want_class for $col.  Got %s.",
           $obj->isa($want_class);
      }
      $data->{$col} = $obj->id;
    }
  }

  $self->_insert_row($data) or return;

  # Fetch ourselves back from the database, in case of defaults etc.
  return $class->retrieve($data->{$self->primary});
}

sub _next_in_sequence {
  my $self = shift;
  my $sth = $self->sql_Nextval($self->sequence);
     $sth->execute;
  my $val = ($sth->fetchrow_array)[0];
     $sth->finish;
  return $val;
}

sub _insert_row {
  my $self = shift;
  my $data = shift;
  eval {
    # Enter a new row into the database containing our object's information.
    my $sth = $self->sql_MakeNewObj(
      $self->table,
      join(', ', keys %$data),
      join(', ', map $self->_column_placeholder($_), keys %$data),
    );
    $sth->execute(values %$data);
    # If we still don't have a primary key, try AUTO_INCREMENT.
    unless( _safe_exists($data, $self->primary) ) {
      $sth = $self->sql_LastInsertID;
      $sth->execute;
      $data->{$self->primary} = ($sth->fetch)[0];
      $sth->finish;
    }
  };
  if($@) {
    $self->DBIwarn('New', 'MakeNewObj');
    return;
  }
  return 1;
}

=head2 new

This is a B<deprecated> synonym for create().  Class::DBI originally
used new() to create new objects but it caused confusion as to whether
new() would retrieve or create new objects.  Now you can choose what
new() can do.

To pick, simply subclass like so...

  package My::Class::DBI;
  use base qw(My::Class::DBI);

  # Make new() synonymous with retrieve()
  sub new {
      my($proto) = shift;
      $proto->retrieve(@_);
  }

If you wish to alter the way retrieve() works, be sure to put that
code in retrieve() and not new() or else Class::DBI won't use it.

=cut

sub new   { my $proto = shift; $proto->create(@_); }
sub _init { my $class = shift; bless { __Changed => {} }, $class; }

=head2 construct

  my $obj = Class->construct(\%data);

This is a B<protected> method and shouldn't be called by any but
Class::DBI subclasses.  This is ENFORCED!

Constructs a new object based solely on the %data given.  It treats
that data just like the columns of a table, key is the column name,
value is the value of that column.  This is very handy for cheaply
setting up lots of objects that you have the data for without
going to the database.

Basically, instead of doing one SELECT to get a bunch of IDs and then
feeding those individually to retreive() (and thus doing more SELECT
calls), you can do one SELECT to get the essential data of an object
(by asking columns('Essential')) and feed that data to construct().

Look at the implementation of search() for a good example of its use as
well as "Constructing a bunch of persistent objects efficiently" in
the Class::DBI paper.

=cut

sub construct {
  my ($proto, $data) = @_;
  my $class = ref $proto || $proto;
  croak("construct() is a protected method of Class::DBI!")
    unless caller->isa("Class::DBI");

  my @columns = $class->_normalized(keys %$data);
  my $self = $class->_init;
  @{$self}{@columns} = values %$data;
  return $self;
}

=head2 retrieve

Given a primary key value it will retrieve an object with that ID from
the database.  It simply calls search(), with the primary key.

=cut

sub retrieve {
  my $class = shift;
  my $id = shift or return;
  croak "Cannot retrieve a reference" if ref($id);
  my @rows = $class->_run_search('Search', $class->primary, $id);
  return $rows[0];
}

=head2 copy / move

  my $new_obj = $obj->copy;
  my $new_obj = $obj->copy($new_id);
  my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");

  my $new_obj = Sub::Class->move($old_obj);
  my $new_obj = Sub::Class->move($old_obj, $new_id);

These create a copy of the given $obj both in memory and in the
database. However, where copy() will insert the data into the
same table, move() will insert it into the table of a subclass.

If provided, $new_id will be used as the new primary key, otherwise the
usual sequence or autoincrement will be used.

=cut

# Get the data, as a hash, but setting the primary key to whatever
# we pass. Used by copy() and move()

sub _data_hash {
    my $self     = shift;
    my @columns  = $self->columns;
    my %data; @data{@columns} = $self->get(@columns);
    delete $data{$self->primary};
           $data{$self->primary} = shift if @_;
    return \%data;
}
   
sub copy {
  my $self = shift;
  return $self->create($self->_data_hash(@_));
}

sub move {
  my $class = shift;
  my $old_obj = shift;
  croak "You can only move to a related class"
    unless $class->isa(ref $old_obj) or $old_obj->isa($class);
  return $class->create($old_obj->_data_hash(@_));
}

=head2 delete

  $obj->delete;

Deletes this object from the database and from memory.  $obj is no longer
usable after this call.

=cut

__PACKAGE__->set_sql('DeleteMe', <<"", 'Main');
DELETE
FROM    %s
WHERE   %s = ?

sub delete {
  my $self = shift;
  eval {
    my $sth = $self->sql_DeleteMe($self->table, $self->columns('Primary'));
    $sth->execute($self->id);
  };
  if($@) {
    $self->DBIwarn($self->id, 'Delete');
    return;
  }
  undef %$self;
  bless $self, 'Class::Deleted';
  return SUCCESS;
}

=head2 autocommit

This is basically a wrapper around the __AutoCommit class data.

=cut

__PACKAGE__->mk_classdata('__AutoCommit');

# I don't really like how this method is written.
sub autocommit {
    my($proto) = shift;
    my $class = ref $proto || $proto;

    if(@_) {
        my $on_or_off = $_[0];
        if( ref $proto ) {
            my $self = $proto;
            $self->{__AutoCommit} = $on_or_off;
        }
        else {
            $class->__AutoCommit($on_or_off);
        }
        return SUCCESS;
    }
    else {
        # Check for an explicity autocommit setting, first the object then
        # the class.
        if( ref $proto ) {
            my $self = $proto;
            return $self->{__AutoCommit} if defined $self->{__AutoCommit};
        }

        return $class->__AutoCommit;
    }
}

=head2 _column_placeholder

  my $placeholder = $self->_column_placeholder($column_name);

Return the placeholder to be used in UPDATE and INSERT queries.  Usually
you'll want this just to return '?', as per the default.  However, this
lets you set, for example, that a column should always be CURDATE()
[MySQL doesn't allow this as a DEFAULT value] by subclassing:

  sub _column_placeholder {
    my ($self, $column) = @_;
    if ($column eq "entry_date") {
      return "IF(1, CURDATE(), ?)";
    }
    return "?";
  }

=cut

sub _column_placeholder { '?' }

=head2 commit

Writes any changes you've made via accessors to disk.  There's nothing
wrong with using commit() when autocommit is on, it'll just silently
do nothing. If the object is DESTROYed before you call commit() we will
issue a warning.

=cut

__PACKAGE__->set_sql('commit', <<"", 'Main');
UPDATE %s
SET    %s
WHERE  %s = ?

sub commit {
  my $self = shift;
  my $table = $self->table;
  assert( defined $table ) if DEBUG;

  if (my @changed_cols = $self->is_changed) {
    eval {
      my $sth = $self->sql_commit(
        $table,
        join( ', ', map "$_ = " . $self->_column_placeholder, @changed_cols),
        $self->primary
      );
        
      $sth->execute((map $self->{$_}, @changed_cols), $self->id);
    };
    if ($@) {
      $self->DBIwarn( "Cannot commit $table");
      return;
    }
    $self->{__Changed}  = {};
  }
  return SUCCESS;
}

sub DESTROY {
    my($self) = shift;
    if( my @changes = $self->is_changed ) {
        carp( $self->id .' in class '. ref($self) .
              ' destroyed without saving changes to column(s) '.
              join(', ', map { "'$_'" } @changes) . "."
            );
    }
}

=head2 rollback

Removes any changes you've made to this object since the last commit.
Currently this simply reloads the values from the database.  This can
have concurrency issues.

If you're using autocommit this method will throw an exception.

=cut

sub rollback {
    my($self) = shift;
    my($class) = ref $self;

    # rollback() is useless if autocommit is on.
    croak 'rollback() used while autocommit is on'
      if $self->autocommit;

    # Shortcut if there are no changes to rollback.
    return SUCCESS unless $self->is_changed;

    # Retrieve myself from the database again.
    my $data;
    eval {
        my $sth = $self->sql_GetMe(join(', ', $self->is_changed),
                                   $self->table,
                                   $self->primary
                                  );
        $sth->execute($self->id);
        $data = $sth->fetchrow_hashref;
        $sth->finish;
    };
    if ($@) {
        $self->DBIwarn($self->id, 'GetMe');
        return;
    }

    unless( defined $data ) {
        carp "rollback failed for ".$self->id." of class $class.";
        return;
    }

    $self->normalize_hash($data);

    # Make sure what we got from the database is what was changed.
    assert( join('', sort keys %$data) eq
            join('', sort $self->is_changed) ) if DEBUG;

    # Throw away our changes.
    @{$self}{keys %$data} = values %$data;
    $self->{__Changed}    = {};

    return SUCCESS;
}

=head2 get

We override the get() method from Class::Accessor to fetch the data for
the column (and associated) columns from the database, using the _flesh()
method. We also allow get to be called with a list of keys, instead of
just one.

=cut

sub get {
    my($self, @keys) = @_;

    my $col2group = $self->_get_col2group;

    my @null_keys = grep { !_safe_exists($self, $_) } @keys;
    $self->_flesh($self->_cols2groups(@null_keys)) if @null_keys;

    if(@keys == 1) {
        return $self->{$keys[0]};
    }
    elsif( @_ > 1 ) {
        return @{$self}{@keys};
    }
    else {
        assert(0) if DEBUG;
    }
}

sub id { $_[0]->get($_[0]->primary) }

__PACKAGE__->set_sql('Flesh', <<'');
SELECT  %s
FROM    %s
WHERE   %s = ?

sub _flesh {
    my($self, @groups) = @_;

    # Get a list of all columns in the given groups, removing
    # duplicates.
    my @cols = ();
    {
        my %tmp_cols;
        @cols = grep { !$tmp_cols{$_}++ } map { $self->columns($_) } @groups;
    }

    # Don't bother with columns that have already been fleshed.
    @cols = grep { !_safe_exists($self, $_) } @cols;

    return SUCCESS unless @cols;

    my $sth;
    eval {
        $sth = $self->sql_Flesh(join(', ', @cols),
                                $self->table,
                                $self->primary
                               );
        $sth->execute($self->id);
    };
    if($@) {
        $self->DBIwarn("Flesh", join(', ', @groups));
        return;
    }

    my @row = $sth->fetch;
    $sth->finish;
    assert(@row == @cols) if DEBUG;
    @{$self}{@cols} = @row;

    return SUCCESS;
}

sub _cols2groups {
  my($self, @cols) = @_;
   
  my %groups = ();
  my $col2group = $self->_get_col2group;

  foreach my $col (@cols) {
    $groups{$_}++ foreach @{$col2group->{$col}};
  }
   
  return grep !/^All$/, keys %groups;
}

=head2 set

We also override set() from Class::Accessor so we can keep track of
changes, and either write to the database now (if autocommit is on),
or when commit() is called.

=cut

sub set {
    my($self, $key) = splice(@_, 0, 2);

    # Only simple scalar values can be stored.
    assert( @_ == 1 and !ref $_[0] ) if DEBUG;

    my $value = shift;

    # Note the change for commit/rollback purposes.
    # We increment instead of setting to 1 because it might be useful to
    # someone to know how many times a value has changed between commits.

    $self->{__Changed}{$key}++ if $self->has_column($key);
    $self->SUPER::set($key, $value);
    $self->commit if $self->autocommit;

    return SUCCESS;
}

sub is_changed { keys %{shift->{__Changed}} }

=head2 set_db

We override set_db from Ima::DBI so that we can set up some default
attributes on a per database basis.  For instance, if MySQL is detected,
AutoCommit will be turned on.  Under Oracle, ChopBlanks is turned on.
As more databases are tested, more defaults will be added.

The defaults can be overridden by supplying your own $attr hashref as
the 6th argument.

=cut

{
  my %Per_DB_Attr_Defaults = (
   mysql        => { AutoCommit => 1 },
   pg           => { AutoCommit => 0, ChopBlanks => 1 },
   oracle       => { AutoCommit => 0, ChopBlanks => 1 },
   csv          => { AutoCommit => 1 },
   ram          => { AutoCommit => 1 },
  );

  sub set_db {
    my($class, $db_name, $data_source, $user, $password, $attr) = @_;

    # 'dbi:Pg:dbname=foo' we want 'Pg'  I think this is enough.
    my($driver) = $data_source =~ /^dbi:(.*?):/i;

    # Combine the user's attributes with our defaults.
    $attr = {} unless defined $attr;
    my $default_attr = $Per_DB_Attr_Defaults{lc $driver} || {};
    $attr = { %$default_attr, %$attr };

    $class->SUPER::set_db($db_name, $data_source, $user, $password, $attr);
  }
}

=head2 table / sequence

These are simple wrapper around the __table and __sequence class data.

=cut

__PACKAGE__->mk_classdata('__table');

sub table {
  my $proto = shift;
  my $class = ref $proto || $proto;
  $class->_invalid_object_method('table()') if @_ and ref $proto;
  $class->__table(@_);
}

__PACKAGE__->mk_classdata('__sequence');

sub sequence {
  my $proto = shift;
  my $class = ref $proto || $proto;
  $class->_invalid_object_method('sequence()') if @_ and ref $proto;
  $class->__sequence(@_);
}

sub _invalid_object_method {
  my ($self, $method) = @_;
  carp "$method should be called as a class method not an object method";
}

=item B<columns>

Columns is a wrapper to the __columns class data, but it's much more
complex than table() or sequence(). We provide primary() and essential()
as simple accessors to these methods (primary currently returns a scalar,
and essential a list).

When we declare a new group of columns we create an accessors for each
via _mk_column_accessors.

=cut

__PACKAGE__->mk_classdata('__columns');
__PACKAGE__->__columns({});

sub columns {
    my($proto, $group, @columns) = @_;
    my($class) = ref $proto || $proto;

    # Default to returning 'All' columns.
    $group = 'All' unless defined $group;

    # Get %__Columns from the class's namespace.
    my $class_columns = $class->__columns || {};

    if (@columns) {
        $class->_invalid_object_method('columns()') if ref $proto;
        # Since we're going to be mucking with the columns, we need to
        # copy $class_columns else we risk modifying our parent's info.
        my %columns = %$class_columns;

        $class->_mk_column_accessors(@columns);

        $class->normalize(\@columns);

        if( $group =~ /^Essential|All$/ and exists $columns{Primary}) {
            unless( grep $_ eq $class->primary, @columns ) {
                push @columns, $class->primary;
            }
        }

        foreach my $col (@columns) {
            $class->add_fields(PROTECTED, $col) unless
              $class->is_field($col);
        }

        # Group all these columns together in their group and All.
        # XXX Should this add to the group or overwrite?
        $columns{$group} = { map { ($_=>1) } @columns };
        @{$columns{All}}{@columns} = (1) x @columns
          unless $group eq 'All';

        # Force columns() to be overriden if necessary.
        $class->__columns(\%columns);

        $class->_flush_col2group;

        # This must happen at the end or else __columns() will trip
        # over itself.
        if( $group eq 'All' and !keys %{$columns{'Primary'}} ) {
            $class->columns('Primary', $columns[0]);
        }

        return SUCCESS;
    } else {
        # Build Essential if not already built.
        if( $group eq 'Essential' and !exists $class_columns->{Essential} ) {
            # Careful to make a copy.
            $class_columns->{Essential} = { %{$class_columns->{All}} };
        }

        unless ( exists $class_columns->{$group} ) {
            carp "'$group' is not a column group of '$class'";
            return;
        } else {
            return keys %{$class_columns->{$group}};
        }
    }
}

sub primary   { (shift->columns('Primary'))[0] }
sub essential { shift->columns('Essential') }

=head2 _mk_column_accessors

Make a set of accessors for each of a list of columns.  We construct
the method name by calling accessor_name() and mutator_name() with the
normalized column name. 

mutator_name will be the same as accessor_name unless you override it.

If both the accessor and mutator are to have the same method name,
(which will always be true unless you override mutator_name), a read-write
method is constructed for it. If they differ we create both a read-only
accessor and a write-only mutator.

=cut

sub _mk_column_accessors {
  my($class, @columns) = @_;

  my %norm; @norm{@columns} = $class->_normalized(@columns);

  foreach my $col (@columns) {
    my %method = (ro => $class->accessor_name($col),
                  wo => $class->mutator_name($col));

    my $both = ($method{ro} eq $method{wo});
    foreach my $type (keys %method) {
      my $method = $method{$type};
      my $maker = $both ? "make_accessor" : "make_${type}_accessor";
      my $accessor = $class->$maker($norm{$method});
      my $alias    = "_${method}_accessor";
      $class->_make_method($_, $accessor) for ($method, $alias);
    }
  }
}

sub _make_method {
  my ($class, $name, $method) = @_;
  no strict 'refs';
  *{"$class\::$name"} = $method unless defined &{"$class\::$name"};
}
  
sub accessor_name {
  my ($class, $column) = @_;
  return $column;
}

sub mutator_name {
  my ($class, $column) = @_;
  return $class->accessor_name($column);
}


=head2 has_column / is_column

has_column used to be called is_column. is_column is still provided as
an alias to it.

=cut

sub has_column {
  my $proto = shift;
  my $class = ref $proto || $proto;
  my $column = $class->_normalized(shift);
  my $col2group = $class->_get_col2group;
  return exists $col2group->{$column} ? scalar @{$col2group->{$column}} : 0;
}

*is_column = \&has_column;

=head2 _get_col2group / _make_col2group / _flush_col2gorup

We store the group => columns mappings in __Col2Group class data.

=cut

__PACKAGE__->mk_classdata('__Col2Group');

sub _get_col2group {
  my $proto  = shift;
  my $class  = ref $proto || $proto;
  my $col2group = $class->__Col2Group || {};
     $col2group = $class->_make_col2group if !keys %$col2group;
  return $col2group;
}

sub _make_col2group {
  my $class  = shift;
  my $col2group = {};
  while( my($group, $cols) = each %{$class->__columns} ) {
    push @{$col2group->{$_}}, $group foreach keys %$cols;
  }
  return $class->__Col2Group($col2group);
}

sub _flush_col2group {
    my $proto = shift;
    my $class = ref $proto || $proto;
       $class->__Col2Group({});
}

=head2 hasa

When we set up a hasa() relationship we store the relevant columns
in _hasa_columns class data. Then we make the accessor return an
instance of the connected class, rather than the value in the table.

_load_class() tries to require the relevant class for us.

=cut

__PACKAGE__->mk_classdata('__hasa_columns');

sub hasa {
    my($class, $foreign_class, @foreign_key_cols) = @_;

    my $foreign_col_accessor = "_".$foreign_key_cols[0]."_accessor";

    $class->_load_class($foreign_class);

    # This is so complicated to allow multiple columns leading to the
    # same class.
    my $obj_key = "__".$foreign_class."_".
                  join(':', @foreign_key_cols)."_Obj";

    # Setup the columns for this foreign class.
    $class->columns($obj_key, @foreign_key_cols);

    # Make sure pseudohashes know about the object key field.
    $class->add_fields(PROTECTED, $obj_key);

    my $hasa_columns = $class->__hasa_columns || {};
    @{$hasa_columns}{@foreign_key_cols} =
        ($foreign_class) x @foreign_key_cols;

    $class->__hasa_columns($hasa_columns);

    my $accessor = sub {
        my($self) = shift;
       
        if (@_) {             # setting
            my ($obj) = shift;
            $self->{$obj_key} = $obj;
           
            # XXX Have to fix this for mult-col foreign keys.
            $self->$foreign_col_accessor($obj->id);
        }
       
        # XXX Fix this, too.
        if ( not defined $self->{$obj_key} ) {
            my $obj_id = $self->$foreign_col_accessor();
            $self->{$obj_key} = $foreign_class->retrieve($obj_id) or
              croak("Can't retrieve $foreign_class ($obj_id)");
        }

        return $self->{$obj_key};
    };
     
    # This might cause a subroutine redefined warning.
    {
        local $^W = 0;
        no strict 'refs';
        *{$class."\::$foreign_key_cols[0]"} = $accessor;
    }
}

sub _load_class {
    my ($self, $foreign_class) = @_;

    no strict 'refs';

    # Gleefully stolen from base.pm
    unless (exists ${"$foreign_class\::"}{VERSION}) {
        eval "require $foreign_class";
        # Only ignore "Can't locate" errors from our eval require.
        # Other fatal errors (syntax etc) must be reported.
        die if $@ && $@ !~ /^Can't locate .*? at \(eval /; #';
        unless (%{"$foreign_class\::"}) {
            croak("Foreign class package \"$foreign_class\" is empty.\n",
                  "\t(Perhaps you need to 'use' the module ",
                  "which defines that package first.)");
        }
        ${"$foreign_class\::VERSION"} = "-1, set by Class::DBI"
            unless exists ${"$foreign_class\::"}{VERSION};
    }
}

=item B<hasa_list>

This creates a new (read-only) accessor method which will return a
instances of the foreign class.

=cut

sub hasa_list {
    my($class, $foreign_class, $foreign_keys, $accessor_name) = @_;

    $class->_load_class($foreign_class);

    croak "Multiple foreign primary keys not yet implemented"
      if @$foreign_keys > 1;

    my($foreign_key) = @$foreign_keys;

    my $accessor = sub {
        my $self = shift;
        croak "$accessor_name is read-only" if @_;
        return $foreign_class->search($foreign_key => $self->id);
    };

    {
        no strict 'refs';
        *{$class.'::'.$accessor_name} = $accessor;
    }
}

=item B<normalize>

  $obj->normalize(\@columns);

SQL is largely case insensitive.  Perl is largely not.  This can lead
to problems when reading information out of a database.  Class::DBI
does some data normalization.

There is no guarantee how a database will muck with the case of
columns, so to protect against things like DBI->fetchrow_hashref()
returning strangely cased column names (along with table names
appended to the front) we normalize all column names before using them
as data keys.

=item B<normalize_hash>

    $obj->normalize_hash(\%hash);

Given a %hash, it will normalize all its keys using normalize().
This is for convenience.

=cut

sub _normalized {
  my $self = shift;
  my @data = @_;
  my @return = map {
    s/^.*\.//;   # Chop off the possible table & database names.
    tr/ \t\n\r\f\x0A/______/;  # Translate whitespace to _
    lc;
  } @data;
  return wantarray ? @return : $return[0];
}

sub normalize {
  my($self, $colref) = @_;
  croak "Normalize needs a listref" unless ref $colref eq 'ARRAY';
  $_ = $self->_normalized($_) foreach @$colref;
  return 1;
}

sub normalize_one {
  my ($self, $col) = @_;
  $$col = $self->_normalized($$col);
}

sub normalize_hash {
    my($self, $hash) = @_;
    my(@normal_cols, @cols);

    @normal_cols = @cols = keys %$hash;
    $self->normalize(\@normal_cols);
   
    assert(@normal_cols == @cols) if DEBUG;

    @{$hash}{@normal_cols} = delete @{$hash}{@cols};

    return SUCCESS;
}

=head2 set_sql

We override set_sql() from Ima::DBI so it has a default database connection.

=cut

sub set_sql {
    my($class, $name, $sql, $db) = @_;
    $db = 'Main' unless defined $db;

    $class->SUPER::set_sql($name, $sql, $db);
}

=head2 dbi_commit / dbi_rollback

Simple aliases to commit() and rollback() in DBI, given different
names to distinguish them from the Class::DBI concepts of commit()
and rollback().

=cut

sub dbi_commit {
    my($proto, @db_names) = @_;
    $proto->SUPER::commit(@db_names);
}

sub dbi_rollback {
    my($proto, @db_names) = @_;
    $proto->SUPER::rollback(@db_names);
}


=head2 search / search_like

Simple search mechanism. This is currently through a series of helper
methods that will undoubtedly change in future releases as we abstract
the whole SQL concept further. Don't rely on any of the private methods
here.

=cut

__PACKAGE__->set_sql('GetMe', <<"", 'Main');
SELECT %s
FROM   %s
WHERE  %s = ?

__PACKAGE__->set_sql('Search', <<"", 'Main');
SELECT  %s
FROM    %s
WHERE   %s = ?

__PACKAGE__->set_sql('SearchLike', <<"", 'Main');
SELECT    %s
FROM      %s
WHERE     %s LIKE ?

sub search {
  my $self = shift;
  $self->_run_search('Search', @_);
}

sub search_like {
  my $self = shift;
  $self->_run_search('SearchLike', @_);
}

sub _run_search {
  my $proto = shift;
  my $class = ref $proto || $proto;
  my $SQL = shift;
     croak "Not enough arguments to search()" unless @_ == 2;
  my $key = $class->_normalized(shift);
     croak "$key is not a column" unless $class->has_column($key);
  my $val = shift;
  my $sth = $class->_run_query($SQL, [$key], [$val]) or return;
  return map $class->construct($_), $sth->fetchall_hash;
}

sub _run_query {
  my $class = shift;
  my ($type, $keys, $vals, $columns) = @_;
  $columns ||= [ $class->essential ];
  my $sth;
  eval {
    my $sql_method = "sql_$type";
    $sth = $class->$sql_method(
      join(', ', @$columns),
      $class->table,
      @$keys
    );
    $sth->execute(@$vals);
  };
  if($@) {
    $class->DBIwarn("Problems with $type");
    return;
  }
  return $sth;
}

# In perl < 5.6 exists() doesn't quite work the same on pseudohashes
# as on regular hashes.  In order to protect ourselves we define our own
# exists function.
use constant PERL_VERSION => $];
sub _safe_exists {
    my($hash, $key) = @_;
    # Because PERL_VERSION is constant this logic will
    # be optimized away in Perl >= 5.6 and reduce to a simple
    # statement.
    # Either its 5.6 or its a hash.  Either way exists() is
    # safe.
    if( PERL_VERSION >= 5.006 ) {
        return exists $hash->{$key};
    }
    else {
        # We can't use ref() since that won't work on objects.
        if( UNIVERSAL::isa($hash, 'HASH') ) {     # hash
            return exists $hash->{$key};
        }
        # Older than 5.6 and its a pseudohash.  exists() will always return
        # true, so we use defined() instead as a cheap hack.
        else {
            return defined $hash->{$key};
        }
    }
}

=head1 AUTHOR

Michael G Schwern <schwern@pobox.com> with much late-night help from
Uri Gutman, Damian Conway, Mike Lambert and the POOP group.

Now developed and maintained by Tony Bowden <kasei@tmtm.com>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
