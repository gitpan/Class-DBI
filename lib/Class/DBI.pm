package Class::DBI;

require 5.00502;

use strict;

use vars qw($VERSION);
$VERSION = 0.03;

use Carp::Assert;
use base qw(Class::Accessor Ima::DBI);

# Little trick to allow goto &Class::DBI::AUTOLOAD to work.
*AUTOLOAD = \&Class::Accessor::AUTOLOAD;

use protected qw(__Changed __AutoCommit __OrigValues);

use constant TRUE       => (1==1);
use constant FALSE      => !TRUE;
use constant SUCCESS    => TRUE;
use constant FAILURE    => FALSE;
use constant YES        => TRUE;
use constant NO         => FALSE;

=pod

=head1 NAME

  Class::DBI - Simple SQL-based object persistance


=head1 SYNOPSIS

  package Film;
  use base qw(Class::DBI);
  use public qw( Title Director Rating NumExplodingSheep );

  # Tell Class::DBI a little about yourself.
  Film->table('Movies');
  Film->columns('Primary', 'Title');
  Film->set_db('Main', 'dbi:mysql', 'me', 'noneofyourgoddamnedbusiness');


  #-- Meanwhile, in a nearby piece of code! --#
  use Film;

  # Create a new film entry for Bad Taste.
  $btaste = Film->new({ Title       => 'Bad Taste',
                        Director    => 'Peter Jackson',
                        Rating      => 'R',
                        NumExplodingSheep   => 1
                      });
  
  # Retrieve the 'Gone With The Wind' entry from the database.
  my $gone = Film->retrieve('Gone With The Wind');
  
  # Shocking new footage found reveals bizarre Scarlet/sheep scene!
  $gone->NumExplodingSheep(5);
  $gone->Rating('NC-17');
  $gone->commit;

  # Grab the 'Bladerunner' entry.
  my $blrunner = Film->retrieve('Bladerunner');

  # Make a copy of 'Bladerunner' and create an entry of the director's
  # cut from it.
  my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");

  # Ishtar doesn't deserve an entry anymore.
  Film->retrieve('Ishtar')->delete;

  # Find all films which have a rating of PG.
  @films = Film->search('Rating', 'PG');

  # Find all films which were directed by Bob
  @films = Film->search_like('Director', 'Bob %');


=head1 DESCRIPTION

I hate SQL.  You hate SQL.  We all hate SQL.  Alas, we often find the
need to make our objects persistant and like it or not an SQL database
is usually the most flexible solution.

This module is for setting up a reasonably efficient, reasonably
simple, reasonably extendable persistant object with as little SQL and
DBI knowledge as possible.

Its a subclass of Class::Accessor and uses that scheme to
automatically set up accessors for each public data field in your
class.  These accessors control access to the underlying database.

=head2 How to set it up

Here's a fairly quick set of steps on how to make your class
persistant.  More details about individual methods will follow.

=over 4

=item I<Set up a database.>

You must have an existing database set up, have DBI.pm installed and
the necessary DBD:: driver module for that database.  See L<DBI> and
the documentation of your particular database for details.

=item I<Set up a table for your objects to be stored in.>

Class::DBI works on a simple one class/one table model.  It is
your responsibility to set up that table, automating the process would
introduce too many complications.

Using our Film example, you might declare a table something like this:

  CREATE TABLE Movies (
         Title      VARCHAR(255)    PRIMARY KEY,
         Director   VARCHAR(80),
         Rating     CHAR(5),    /* to fit at least 'NC-17' */
         NumExplodingSheep      INTEGER
  )

=item I<Inherit from Class::DBI.>

It is prefered that you use base.pm to do this rather than appending
directly to @ISA as your class may have to inherit some protected data
fields from Class::DBI and this is important if you're using
pseudohashes.

  package Film;
  use base qw(Class::DBI);

=item I<Declare your public data members.>

This can be done using fields.pm or public.pm.  The names of your
fields should match the columns in your database, one to one.
Class::DBI (via Class::Accessor) will use this
information to determine how to create accessors.

  use public qw( Title Director Rating NumExplodingSheep );

=item I<Declare the name of your table>

Inform Class::DBI what table you will be storing your objects
in.  This is the table you set up eariler.

  Film->table('Movies');

=item I<Declare which field is your primary key>

One of your fields must be a unique identifier for each object.  This
will be the primary key in your database.  Class::DBI needs
this piece of information in order to construct the proper SQL
statements to access your stored objects.

  Film->columns('Primary', 'Title');

=item I<Declare a database connection>

Class::DBI needs to know how to access the database.  It does
this through a DBI connection which you set up.  Set up is by calling
the set_db() method and declaring a database connection named 'Main'.

  Film->set_db('Main', 'dbi:mysql', 'user', 'password');

set_db() is inherited from Ima::DBI.  See that module's man page for
details.

=item I<Done.>

All set!  You can now use the constructors (new(), copy() and
retrieve()) destructors (delete()) and all the accessors and other
garbage provided by Class::DBI.  Make some new objects and
muck around a bit.  Watch the table in your database as your object
does its thing and see things being stored, changed and deleted.

=back

Is it not nifty?  Worship the module.


=head1 METHODS

The following provided methods make the assumption that you're using
either a hash or a pseudohash as your underlying data structure for
your object.

=head2 Life and Death - Constructors and Destructors

The following are methods provided for convenience to create, retrieve
and delete stored objects.  Its not entirely one-size fits all and you
might find it necessary to override them.

=over 4

=item B<new>

    $obj = Class->new(\%data);

This is a constructor to create a new object and store it in the
database.  %data consists of the initial information to place in your
object and the database.  The keys of %data match up with the public
fields of your objects and the values are the initial settings of
those fields.

$obj is an instance of Class built out of a hash reference.

  # Create a new film entry for Bad Taste.
  $btaste = Film->new({ Title       => 'Bad Taste',
                        Director    => 'Peter Jackson',
                        Rating      => 'R',
                        NumExplodingSheep   => 1
                      });

=cut

sub new {
  my($proto, $data) = @_;
  my($class) = ref $proto || $proto;
  
  my $self = $class->_init;

  # There shouldn't be more input than we have columns for.
  assert($self->columns >= keys %$data) if DEBUG;

  # Everything in %data should be a column.
  assert( !grep { !$self->is_column($_) } keys %$data ) if DEBUG;

  # You -must- have a table defined.
  assert( $self->table ) if DEBUG;

  # Alas, since I can't know how many items will be in %$data I cannot
  # preconstruct this SQL statement.
  my $sql = '';
  $sql .= 'INSERT INTO '.$self->table."\n";
  $sql .= '('. join(', ', keys %$data) .")\n";
  $sql .= 'VALUES ('. join(', ', ('?') x keys %$data). ")\n";

  eval {
    $self->db_Main->do($sql, undef,
                       @{$data}{keys %$data});
  };
  if($@) {
    $self->DBIwarn('New', 'create');
    return;
  }

  # Create our object by ID because the database may have filled out
  # alot of default rows that we don't know about yet.
  my($primary_col) = $self->columns('Primary');
  $self = $class->retrieve($data->{$primary_col});

  return $self;
}

sub _init {
    my($class) = shift;
    my($self) = {};

    $self->{__Changed} 		= {};
	$self->{__OrigValues} 	= {};

	return bless $self, $class;
}

=pod

=item B<retrieve>

  $obj = Class->retrieve($id);

Given an ID it will retrieve an object with that ID from the database.

  my $gone = Film->retrieve('Gone With The Wind');

=cut

__PACKAGE__->make_sql('GetMe',
					  sub {
						  my($class) = @_;

						  return <<"";
                    SELECT    ${\( join(', ', $class->columns('Essential')) )}
                    FROM      ${\( $class->table )}
                    WHERE     ${\( $class->columns('Primary') )} = ?

                      }
                     );

sub retrieve {
    my($proto, $id) = @_;
    my($class) = ref $proto || $proto;
    
    my($id_col) = $class->columns('Primary');
    
	my $data;
    eval {
        my $sth = $class->sql_GetMe;
        $sth->execute($id);
        $data = $sth->fetchrow_hashref;
        $sth->finish;
    };
    if ($@) {
        $class->DBIwarn($id, 'GetMe');
        return;
    }
    
    return unless defined $data;
    
    return $class->construct($data);
}


sub construct {
    my($proto, $data) = @_;
    my($class) = ref $proto || $proto;

    my $self = $class->_init;
    @{$self}{keys %$data} = values %$data;

	return $self;
}
    


=pod

=item B<copy>

  $new_obj = $obj->copy($new_id);

This creates a copy of the given $obj both in memory and in the
database.  The only difference is that the $new_obj will have a new
primary identifier of $new_id.

    my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");

=cut

sub copy {
    my($self, $new_id) = @_;

    my($primary_col) = $self->columns('Primary');
    my @columns		 = $self->columns;
    return $self->new( { (map { ($_ => $self->get($_) ) } @columns),
						 $primary_col => $new_id
					   });
}

=pod

=item B<delete>

  $obj->delete;

Deletes this object from the database and from memory.  $obj is no
longer usable after this call.

=cut

__PACKAGE__->make_sql('Delete',
                      sub {
                          my($class) = shift;

                          return <<"";
                          DELETE 
                          FROM      ${\( $class->table )}
                          WHERE     ${\( $class->columns('Primary') )} = ?

                      }
                     );

sub delete {
    my($self) = shift;

    eval {
        $self->sql_Delete->execute($self->id);
    };
    if($@) {
        $self->DBIwarn($self->id, 'Delete');
        return;
    }

    undef %$self;
    bless $self, 'Class::Deleted';

    return SUCCESS;
}

=pod

=back

=head2 Accessors

Class::DBI inherits from Class::Accessor and thus
provides accessor methods for every public field in your subclass.  It
overrides the get() and set() methods provided by Accessor to
automagically handle database transactions.

There are two modes for the accessors to work in.  Manual commit and
autocommit.  This is sort of analagous to the manual vs autocommit in
DBI, but is not implemented in terms of this.  What it simply means is
this... when in autocommit mode every time one calls an accessor to
make a change the change will immediately be written to the database.
Otherwise, if autocommit is off, no changes will be written until
commit() is explicitly called.

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

Manual committing is probably more efficient than autocommiting and it
provides the extra safety of a rollback() option to clear out all
unsaved changes.  Autocommitting is more convient for the programmer.

If changes are left uncommitted or not rolledback when the object is
destroyed (falls out of scope or the program ends) then Class::DBI's
DESTROY method will print a warning about unsaved changes.

=over 4

=item B<autocommit>

    Class->autocommit($on_or_off);
    $commit_style = Class->autocommit;

    $obj->autocommit($on_or_off);
    $commit_style = $obj->autocommit;

This is an accessor to the current style of autocommitting.  When
called with no arguments it returns the current autocommitting state,
true for on, false for off.  When given an argument it turns
autocommiting on and off.  A true value turns it on, a false one off.
When called as a class method it will control the committing style for
every instance of the class.  When called on an individual object it
will control committing for just that object, overriding the choice
for the class.

  Class->autocommit(1);     # Autocommit is now on for the class.
  
  $obj->retrieve('Aliens Cut My Hair');
  $obj->autocommit(0);      # Shut off autocommitting for this object.

The commit setting for an object is not stored in the database.

Autocommitting is off by default.

=cut

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
            no strict 'refs';
            ${$class.'::__AutoCommit'} = $on_or_off;
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
		no strict 'refs';
        if( defined ${$class.'::__AutoCommit'} ) {
            return ${$class.'::__AutoCommit'};
        }
        
        # Default setting is off.
        return NO;
    }
}
            
=pod

=item B<commit>

    $obj->commit;

Writes any changes you've made via accessors to disk.  There's nothing
wrong with using commit() when autocommit is on, it'll just silently
do nothing.

=cut

#'#
sub commit {
    my($self) = shift;

    my $table = $self->table;
    assert( defined $table ) if DEBUG;

    if( $self->is_changed ) {
		my @changed_cols = keys %{$self->{__Changed}};
        my($primary_col) = $self->columns('Primary');

        # Alas, this must be generated on the fly.
        my $sql = '';
        $sql .= "UPDATE $table\n";
        $sql .= 'SET '. join( ', ', map { "$_ = ?" } @changed_cols) ."\n";
        $sql .= "WHERE $primary_col = ?";

        eval {
            $self->db_Main->do($sql, undef,
                               (map { $self->{$_} } @changed_cols),
                               $self->id
                              );
        };
        if($@) {
            $self->DBIwarn( $primary_col, 'commit' );
            return;
        }

        $self->{__Changed} 		= {};
		$self->{__OrigValues} 	= {};
    }

    return SUCCESS;
}

=pod

=item B<rollback>

  $obj->rollback;

Removes any changes you've made to this object since the last commit.

If you're using autocommit this method will throw an exception.

=cut

#'#
sub rollback {
    my($self) = shift;

    # rollback() is useless if autocommit is on.
    if( $self->autocommit ) {
        require Carp;
        Carp::croak('rollback() used while autocommit is on');
    }

    # Shortcut if there are no changes to rollback.
    return SUCCESS unless $self->is_changed;

    # Stick the original values back into the object.
    @{$self}{keys %{$self->{__OrigValues}}} = values %{$self->{__OrigValues}};

    # Dump the original values and changes.
    $self->{__OrigValues} = {};
    $self->{__Changed}    = {};

    return SUCCESS;
}

sub DESTROY {
    my($self) = shift;
    
    if( $self->is_changed ) {
        require Carp;
        Carp::carp( $self->id .' in class '. ref $self .
                    ' destroyed without saving changes.');
    }
}


sub get {
	my($self, @keys) = @_;

	if(@keys == 1) {
		return $self->{$keys[0]};
	}
	elsif( @_ > 1 ) {
		return @{$self}{@_};
	}
	else {
		assert(0) if DEBUG;
	}
}


sub set {
    my($self, $key) = splice(@_, 0, 2);

    # Only simple scalar values can be stored.
    assert( @_ == 1 and !ref $_[0] ) if DEBUG;

    my $value = shift;

    # Store the original value for rollback purposes.
    $self->{__OrigValues}{$key} = $value unless 
      exists $self->{__OrigValues}{$key};

	# Note the change.
	$self->{__Changed}{$key} = 1;

    $self->SUPER::set($key, $value);

    $self->commit if $self->autocommit;

    return SUCCESS;
}

=pod

=item B<is_changed()>

  $obj->is_changed;

Indicates if the given $obj has uncommitted changes.

=cut

sub is_changed {
	my($self) = shift;
	return scalar keys %{$self->{__Changed}};
}

=pod

=back

=head2 Database information

=over 4

=item B<id>

  $id = $obj->id;

Returns a unique identifier for this object.  Its the equivalent of
$obj->get($self->columns('Primary'));

=cut

sub id {
	my($self) = shift;
    return $self->get($self->columns('Primary'));
}

=pod

=item B<table>

  Class->table($table);
  $table = Class->table;
  $table = $obj->table;

An accessor to get/set the name of the database table in which this
class is stored.  It -must- be set.

=cut

sub table {
    my($proto, $table) = @_;

    my($class) = ref $proto || $proto;

    no strict 'refs';
    
    if(defined $table) {
        if( ref $proto ) {
            require Carp;
            Carp::carp('It is prefered to call table() as a class method '.
                       '[Class->table($table)] rather than an object method '.
                       '[$obj->table($table)] when setting the table.');
        }
        ${$class.'::__TABLE'} = $table;
        return SUCCESS;
    }
    else {
        return ${$class.'::__TABLE'};
    }
}

=pod

=item B<columns>

  @all_columns  = $obj->columns;
  @columns      = $obj->columns($group);
  Class->columns($group, @columns);

This is an accessor to the names of the database columns of a class.
Its used to construct SQL statements to act on the class.

Columns are grouped together by typical usage, this can allow more
efficient access by loading all columns in a group at once.  This
basic version of the module does not take advantage of this but more
complex subclasses do.

There are three 'reserved' groups.  'All', 'Essential' and 'Primary'.

B<'All'> are all columns used by the class.  It will automatically be
generated from your public data fields if you don't set it yourself.

B<'Primary'> is the single primary key column for this class.  It I<must>
be set before objects can be used.

B<'Essential'> are the minimal set of columns needed to load and use
the object.  Its typically used so save memory on a class that has
alot of columns but most only uses a few of them.  It will
automatically be generated from C<Class->columns('All')> if you don't
set it yourself.

    Class->columns('Primary', 'Title');

If the $group is not given it will assume you want 'All'.

=cut

sub columns {
    my($proto, $group, @columns) = @_;
    my($class) = ref $proto || $proto;

    # Default to returning 'All' columns.
    $group = 'All' unless defined $group;

    # Get %__Columns from the class's namespace.
    no strict 'refs';
    my $class_columns = \%{$class.'::__Columns'};		

    if(@columns) {
        if( ref $proto ) {
            require Carp;
            Carp::carp('It is prefered to call columns() as a class method '.
                       '[Class->columns($group, @cols)] rather than an '.
                       'object method [$obj->columns($group, @cols)] when '.
                       'setting columns.');
        }
        $class_columns->{$group} = [@columns];
        return SUCCESS;
    }
    else {
		# Build $__Columns{All} if not already built.
		if( $group eq 'All' and !exists $class_columns->{All} ) {
			$class_columns->{All} = [$class->show_fields('Public')];
		}

		# Build $__Columns{Essential} if not already built.
		if( $group eq 'Essential' and !exists $class_columns->{Essential} ) {
			# Careful to make a copy.
			$class_columns->{Essential} = [@{$class_columns->{All}}];
		}

        unless ( exists $class_columns->{$group} ) {
            require Carp;
            Carp::carp("'$group' is not a column group of '$class'");
            return;
        } else {
            return @{$class_columns->{$group}};
        }
    }
}

=pod

=item B<is_column>

    Class->is_column($column);
    $obj->is_column($column);

This will return true if the given $column is a column of the class or
object.

=cut

sub is_column {
    my($proto, $column) = @_;
    my($class) = ref $proto || $proto;

    my $col2group = $class->_get_col2group;

    return scalar @{$col2group->{$column}};
}


sub _get_col2group {
    my($proto) = shift;
    my($class) = ref $proto || $proto;

    no strict 'refs';   
    my $col2group = \%{$class.'::__Col2Group'};

    # Build %__Col2Group if necessary.
    unless( keys %$col2group ) {
        while( my($group, $cols) = each %{$class.'::__Columns'} ) {
            foreach my $col (@$cols) {
                push @{$col2group->{$col}}, $group;
            }
        }
    }

    return $col2group;
}
    

=pod

=back

=head2 Defining SQL statements

Class::DBI inherits from Ima::DBI and prefers to use that class's
style of dealing with databases and DBI.  (Now is a good time to skim
Ima::DBI's man page).

In order to write new methods which are inheritable by your subclasses
you must be careful not to hardcode any information about your class's
table name or primary key.  However, it is more efficient to use
Ima::DBI::set_sql() to generate cached statement handles.

This clash between inheritability and efficiency is solved by
make_sql().  Through the magic of autoloading and closures make_sql()
lets you write cached SQL statement handles while still allowing them
to be inherited.

=over 4

=item B<make_sql>

    $obj->make_sql($sql_name, \&sql_generator);
    $obj->make_sql($sql_name, \&sql_generator, $db_name);

make_sql() works almost like Ima::DBI::set_sql() with two important
differences.  

Instead of simply giving it an SQL statement you must instead feed it
a subroutine which generates the necessary SQL statement.  This
routine is called as a method and takes no arguments.

Generally, a call to make_sql() looks something like this:

    # Define sql_GetFooBar()
    Class->make_sql('GetFooBar',
                    sub {
                        my($class) = shift;

						my $sql = '';
			$sql .= 'SELECT '. join(', ', $class->columns('Essential')  ."\n";
			$sql .= 'FROM   '. $class->table                ."\n";
			$sql .= 'WHERE  Foo = ? AND Bar = ?'

						return $sql;
					}
				   );

You must be careful not to hardcode information about your class's
table name or primary key column in your statement and instead use
the table() and columns() methods instead.

If you're creating an SQL statement that has no information about your
class in it (usually because its operating on a different table than
your class is stored in) then you may create your statement normally
using the set_sql() method inherited from Ima::DBI.

If $db_name is omitted it will assume you are using the 'Main'
connection.

=cut

#'#

# XXX Override set_sql, add a hash of $sths{$class} = $sth.
sub make_sql {
    my($proto, $sql_name, $sql_gen, $db_name) = @_;
    my($class) = ref $proto || $proto;

    $db_name = 'Main' unless defined $db_name;
	my $db_meth = $db_name;
	$db_meth =~ s/\s/_/g;
	$db_meth = "db_$db_meth";

# Its entirely possible for a class to define a statement while
# expecting its subclass to define the connection.
#    $class->can($db_meth) or
#	  die "There is no database connection named '$db_name' defined in $class";

	# We now do basically what set_sql() does except we have one
	# statement handle for each class.
	my %class_sths = ();

	my $sql_meth = $sql_name;
	$sql_meth =~ s/\s/_/g;
	$sql_meth = "sql_$sql_name";

	no strict 'refs';
	*{$class."::$sql_meth"} =
	  sub {
		  my $class = shift;
		  my $sth = $class_sths{$class};

		  my $dbh = $class->$db_meth();

		  # Calling prepare_cached over and over again is expensive.
		  # Again, we co-opt some of prepare_cached's functionality.
		  if ( !$sth ) {	# No $sth defined yet.
			  $sth = $dbh->prepare_cached($sql_gen->($class));
			  $class_sths{$class} = $sth;
			  bless $sth, 'Ima::DBI::st';
		  }
		  else {			# $sth defined.
			  # Check to see if the handle is active.
			  if( $sth->FETCH('Active') ) {
				  require Carp;
				  Carp::carp("'$sql_name' statement handle is still ".
							 "active!  Finishing for you.");
				  $sth->finish;
			  }
		  }

		  return $sth;
	  };
			  
    return SUCCESS;
}

=pod

=head2 Searching

We provide a few simple search methods, more to show the potential of
the class than to be serious search methods.

=over 4

=item B<search>

  @objs = Class->search($key, $value);
  @objs = $obj->search($key, $value);

This is a simple search through the stored objects for all objects
whose $key has the given $value.

    @films = Film->search('Rating', 'PG');

=cut

sub search {
    my($proto, $key, $value) = @_;
    my($class) = ref $proto || $proto;

    my $sth;
    eval {
        my $dbh = $class->db_Main;
		$sth = $dbh->prepare(<<"");
		SELECT    ${\( join(', ', $class->columns('Essential')) )}
        FROM      ${\( $class->table )}
        WHERE     $key = ?

        $sth->execute($value);
    };
    if($@) {
        $class->DBIwarn("'$key' -> '$value'", 'Search');
        return;
    }

    return map { $class->construct($_) } $sth->fetchall_hash;
}

=item B<search_like>

  @objs = Class->search_like($key, $like_pattern);
  @objs = $obj->search_like($key, $like_pattern);

A simple search for objects whose $key matches the $like_pattern
given.  $like_pattern is a pattern given in SQL LIKE predicate syntax.
'%' means "any one or more characters", '_' means "any single
character".

    # Search for movies directed by guys named Bob.
    @films = Film->search_like('Director', 'Bob %');

=cut

__PACKAGE__->make_sql('SearchLike',
                      sub {
                          my($class) = @_;

                          # XXX Not sure if WHERE ? = ? is valid.
                          return <<"";
                   SELECT    ${\( join(', ', $class->columns('Essential')) )}
                   FROM      ${\( $class->table )}
                   WHERE     ? LIKE ?

                      }
                     );

sub search_like {
    my($proto, $key, $pattern) = @_;
    my($class) = ref $proto || $proto;

    my $sth;
    eval {
		my $dbh = $class->db_Main;
        $sth = $dbh->prepare(<<"");
		SELECT    ${\( join(', ', $class->columns('Essential')) )}
        FROM      ${\( $class->table )}
        WHERE     $key LIKE ?

        $sth->execute($pattern);
    };
    if($@) {
        $class->DBIwarn("'$key' -> '$pattern'", 'SearchLike');
        return;
    }

    return map { $class->construct($_) } $sth->fetchall_hash;
}


=pod

=head1 CAVEATS

=head2 Only simple scalar values can be stored

SQL sucks in that lists are really complicated to store and hashes
practically require a whole new table.  Don't even start about
anything more complicated.  If you want to store a list you're going
to have to write the accessors for it yourself.  If you want to store
a hash you should probably consider making a new table and a new
class.

=head2 One table, one class

For every class you define one table.  Classes cannot be spread over
more than one table, this is too much of a headache to deal with.

=head2 Single column primary keys only

Having more than one column as your primary key in the SQL table is
currently not supported.  Why?  Its more complicated.  A later version
will support multi-column keys.

=head2 Careful with the autoloaders!

Class::DBI employs an autoloader (inherited from Class::Accessor) so
your subclass must be careful if you're defining your own autoloader.
You must be sure to call Class::DBI's autoloader should your own not
find a valid method.  For example:

    sub AUTOLOAD {
        my($self) = $_[0];

        my($func) = $AUTOLOAD =~ m/::([^:]+)$/;

        ### Try to autoload $func ###

        # If all else fails, pass the buck to Class::DBI.
        *Class::DBI::AUTOLOAD = \$AUTOLOAD;
        goto &Class::DBI::AUTOLOAD
    }

You must, of course, be careful not to modify @_ or $AUTOLOAD.


=head2 Define new SQL statements through make_sql()


=head1 AUTHOR

Michael G Schwern <schwern@pobox.com> with much late-night help from
Uri Gutman

=head1 SEE ALSO

L<Ima::DBI>, L<Class::Accessor>, L<public>, L<base>

=cut
