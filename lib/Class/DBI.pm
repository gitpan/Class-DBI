# $Id: DBI.pm,v 1.24 2000/09/12 04:35:29 schwern Exp $

package Class::DBI;

require 5.00502;

use strict;

use vars qw($VERSION);
$VERSION = '0.23';

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
        # We can't use ref() since that won't work on objects.  This is
        # a cheap hack to determine if its an array.
        unless( eval { @$hash } ) {     # hash
            return exists $hash->{$key};
        }
        # Older than 5.6 and its a pseudohash.  exists() will always return 
        # true, so we use defined() instead as a cheap hack.
        else {
            return defined $hash->{$key};
        }
    }
}


=pod

=head1 NAME

  Class::DBI - Simple Object Persistance


=head1 SYNOPSIS

  package Film;
  use base qw(Class::DBI);

  # Tell Class::DBI a little about yourself.
  Film->table('Movies');
  Film->columns(All     => qw( Title Director Rating NumExplodingSheep ));
  Film->columns(Primary => qw( Title ));
  Film->set_db('Main', 'dbi:mysql', 'me', 'noneofyourgoddamnedbusiness',
               {AutoCommit => 1});


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

Its uses a scheme to automatically set up accessors for each data
field in your class.  These accessors control access to the underlying
database.

=head2 How to set it up

Here's a fairly quick set of steps on how to make your class
persistant.  More details about individual methods will follow.

=over 4

=item I<Set up a database.>

You must have an existing database set up, have DBI.pm installed and
the necessary DBD:: driver module for that database.  See L<DBI> and
the documentation of your particular database for details.  

DBD::CSV works in a pinch.

=item I<Set up a table for your objects to be stored in.>

Class::DBI works on a simple one class/one table model.  It is your
responsibility to set up that table, automating the process would
introduce too many complications (unless somebody wants to convince me
otherwise).

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

=item I<Declare your columns.>

This can be done using columns().  The names of your fields should
match the columns in your database, one to one.  Class::DBI (via
Class::Accessor) will use this information to determine how to create
accessors.

  Film->columns(All => qw( Title Director Rating NumExplodingSheep ));

For more information about how you can more efficiently declare your columns,
L<"Lazy Population of Columns">

=item I<Declare the name of your table>

Inform Class::DBI what table you will be storing your objects
in.  This is the table you set up eariler.

  Film->table('Movies');

=item I<Declare which field is your primary key>

One of your fields must be a unique identifier for each object.  This
will be the primary key in your database.  Class::DBI needs
this piece of information in order to construct the proper SQL
statements to access your stored objects.

  Film->columns(Primary => 'Title');

=item I<Declare a database connection>

Class::DBI needs to know how to access the database.  It does
this through a DBI connection which you set up.  Set up is by calling
the set_db() method and declaring a database connection named 'Main'.

  Film->set_db('Main', 'dbi:mysql', 'user', 'password', {AutoCommit => 1});

set_db() is inherited from Ima::DBI.  See that module's man page for
details.

XXX I should probably make this even simpler.  set_db_main() or something.

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
object and the database.  The keys of %data match up with the columns
of your objects and the values are the initial settings of those
fields.

$obj is an instance of Class built out of a hash reference.

  # Create a new film entry for Bad Taste.
  $btaste = Film->new({ Title       => 'Bad Taste',
                        Director    => 'Peter Jackson',
                        Rating      => 'R',
                        NumExplodingSheep   => 1
                      });

If the primary column is not in %data, new() will assume it is to be
generated.  If a sequence() has been specified for this Class, it will
use that.  Otherwise, it will assume the primary key has an
AUTO_INCREMENT constraint on it and attempt to use that.

If the class has declared relationships with foreign classes via
hasa(), it can pass an object to new() for the value of that key.
Class::DBI will Do The Right Thing.


=cut

__PACKAGE__->set_sql('MakeNewObj', <<"SQL", 'Main');
INSERT INTO %s
       (%s)
VALUES (%s)
SQL


__PACKAGE__->set_sql('LastInsertID', <<'', 'Main');
SELECT LAST_INSERT_ID()


__PACKAGE__->set_sql('Nextval', <<'', 'Main');
SELECT NEXTVAL ('%s')


sub new {
    my($proto, $data) = @_;
    my($class) = ref $proto || $proto;
  
    my $self = $class->_init;
    my($primary_col) = $self->columns('Primary');

    $self->normalize_hash($data);

    # There shouldn't be more input than we have columns for.
    assert($self->columns >= keys %$data) if DEBUG;

    # Everything in %data should be a column.
    assert( !grep { !$self->is_column($_) } keys %$data ) if DEBUG;

    # You -must- have a table defined.
    assert( $self->table ) if DEBUG;

    # If a primary key wasn't given, use the sequence if we have one.
    if( $self->sequence && !_safe_exists($data, $primary_col) ) {
        my $sth = $self->sql_Nextval($self->sequence);        
        $sth->execute;
        $data->{$primary_col} = ($sth->fetchrow_array)[0];
    }

    # Look for values which can be objects.
    my $hasa_cols = $class->__hasa_columns || {};
    $class->normalize_hash($hasa_cols);

    while( my($col, $want_class) = each %$hasa_cols) {
        if( _safe_exists($data, $col) && ref $data->{$col} ) {
            my $obj = $data->{$col};
            unless( $obj->isa($want_class) ) {
                require Carp;
                Carp::croak(sprintf <<CARP, $obj->isa($want_class));
$class expects an object of class $want_class for $col.  Got %s.
CARP

            }

            $data->{$col} = $obj->id;
        }
    }
        

    eval {
        # Enter a new row into the database containing our object's
        # information.
        my $sth = $self->sql_MakeNewObj($self->table,
                                        join(', ', keys %$data),
                                        join(', ', ('?') x keys %$data)
                                       );
        $sth->execute(values %$data);

        # If we still don't have a primary key, try AUTO_INCREMENT.
        unless( _safe_exists($data, $primary_col) ) {
            $sth = $self->sql_LastInsertID;
            $sth->execute;
            $data->{$primary_col} = ($sth->fetch)[0];
            $sth->finish;
        }
    };
    if($@) {
        $self->DBIwarn('New', 'MakeNewObj');
        return;
    }

    # Create our object by ID because the database may have filled out
    # alot of default rows that we don't know about yet.
    $self = $class->retrieve($data->{$primary_col});

    return $self;
}

sub _init {
    my($class) = shift;
    my($self) = {};

    $self->{__Changed} = {};

    return bless $self, $class;
}

=pod

=item B<retrieve>

  $obj = Class->retrieve($id);

Given an ID it will retrieve an object with that ID from the database.

  my $gone = Film->retrieve('Gone With The Wind');

=cut

__PACKAGE__->set_sql('GetMe', <<"", 'Main');
SELECT %s
FROM   %s
WHERE  %s = ?


sub retrieve {
    my($proto, $id) = @_;
    my($class) = ref $proto || $proto;
    
    my($id_col) = $class->columns('Primary');
    
    my $data;
    eval {
        my $sth = $class->sql_GetMe(join(', ', $class->columns('Essential')),
                                    $class->table,
                                    $class->columns('Primary')
                                   );
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

    my @columns = keys %$data;
    $class->normalize(\@columns);

    my $self = $class->_init;
    @{$self}{@columns} = values %$data;

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
    my @columns      = $self->columns;
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

__PACKAGE__->set_sql('DeleteMe', <<"", 'Main');
DELETE 
FROM    %s
WHERE   %s = ?


sub delete {
    my($self) = shift;

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

=pod

=back

=head2 Accessors

Class::DBI inherits from Class::Accessor and thus
provides accessor methods for every column in your subclass.  It
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
  
  $obj = Class->retrieve('Aliens Cut My Hair');
  $obj->autocommit(0);      # Shut off autocommitting for this object.

The commit setting for an object is not stored in the database.

Autocommitting is off by default.

B<NOTE> This has I<nothing> to do with DBI's AutoCommit attribute.

=cut

#'#
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
            
=pod

=item B<commit>

    $obj->commit;

Writes any changes you've made via accessors to disk.  There's nothing
wrong with using commit() when autocommit is on, it'll just silently
do nothing.

=cut

#'#
__PACKAGE__->set_sql('commit', <<"", 'Main');
UPDATE %s
SET    %s
WHERE  %s = ?

sub commit {
    my($self) = shift;

    my $table = $self->table;
    assert( defined $table ) if DEBUG;

    if( my @changed_cols = $self->is_changed ) {
        my($primary_col) = $self->columns('Primary');

        eval {
            my $sth = $self->sql_commit($table,
                                        join( ', ', map { "$_ = ?" } 
                                                    @changed_cols),
                                        $primary_col
                                       );
            $sth->execute((map { $self->{$_} } @changed_cols), 
                          $self->id
                         );
        };
        if($@) {
            $self->DBIwarn( $primary_col, 'commit' );
            return;
        }

        $self->{__Changed}  = {};
    }

    return SUCCESS;
}

=pod

=item B<rollback>

  $obj->rollback;

Removes any changes you've made to this object since the last commit.
Currently this simply reloads the values from the database.  This can
have concurrency issues.

If you're using autocommit this method will throw an exception.

=cut

#'#
sub rollback {
    my($self) = shift;
    my($class) = ref $self;

    # rollback() is useless if autocommit is on.
    if( $self->autocommit ) {
        require Carp;
        Carp::croak('rollback() used while autocommit is on');
    }

    # Shortcut if there are no changes to rollback.
    return SUCCESS unless $self->is_changed;

    # Retrieve myself from the database again.
    my $data;
    eval {
        my $sth = $self->sql_GetMe(join(', ', $self->is_changed),
                                   $self->table,
                                   $self->columns('Primary')
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
        require Carp;
        Carp::carp("rollback failed for ".$self->id." of class $class.");
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

sub DESTROY {
    my($self) = shift;
    
    if( my @changes = $self->is_changed ) {
        require Carp;
        &Carp::carp( $self->id .' in class '. ref($self) .
                     ' destroyed without saving changes to column(s) '.
                     join(', ', map { "'$_'" } @changes) . ".\n"
                   );
    }
}


sub get {
    my($self, @keys) = @_;

    my $col2group = $self->_get_col2group;

    my @null_keys = grep { !_safe_exists($self, $_) } @keys;
    $self->_flesh($self->_cols2groups(@null_keys)) if @null_keys;

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


__PACKAGE__->set_sql('Flesh', <<"SQL");
SELECT  %s
FROM    %s
WHERE   %s = ?
SQL

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
                                $self->columns('Primary')
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
        foreach my $group (@{$col2group->{$col}}) {
            $groups{$group}++;
        }
    }
    
    return grep !/^All$/, keys %groups;
}


sub set {
    my($self, $key) = splice(@_, 0, 2);

    # Only simple scalar values can be stored.
    assert( @_ == 1 and !ref $_[0] ) if DEBUG;

    my $value = shift;

    # Note the change for commit/rollback purposes.
    # We increment instead of setting to 1 because it might be useful
    # to someone to know how many times a value has changed between
    # commits.
    $self->{__Changed}{$key}++;

    $self->SUPER::set($key, $value);

    $self->commit if $self->autocommit;

    return SUCCESS;
}

=pod

=item B<is_changed>

  @changed_keys = $obj->is_changed;

Indicates if the given $obj has uncommitted changes.  Returns a list of
keys which have changed.

=cut

sub is_changed {
    my($self) = shift;
    return keys %{$self->{__Changed}};
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

Table information is inherited by subclasses, but can be overridden.

=cut

__PACKAGE__->mk_classdata('__table');

sub table {
    my($proto) = shift;
    my($class) = ref $proto || $proto;

    no strict 'refs';
    
    if(@_) {
        if( ref $proto ) {
            require Carp;
            Carp::carp('It is prefered to call table() as a class method '.
                       '[Class->table($table)] rather than an object method '.
                       '[$obj->table($table)] when setting the table.');
        }
    }

    $class->__table(@_);
}

=pod

=item B<sequence>

  Class->sequence($sequence_name);
  $sequence_name = Class->sequence;
  $sequence_name = $obj->sequence;

An accessor to get/set the name of a sequence for the primary key.

    Class->columns(Primary => 'id');
    Class->sequence('class_id_seq');

Class::DBI will use the sequence to generate primary keys when objects
are created yet the primary key is not specified.

B<NOTE>: Class::DBI also supports AUTO_INCREMENT and similar semantics.

=cut

__PACKAGE__->mk_classdata('__sequence');

sub sequence {
    my($proto) = shift;
    my($class) = ref $proto || $proto;

    no strict 'refs';
    
    if(@_) {
        if( ref $proto ) {
            require Carp;
            Carp::carp('It is prefered to call sequence() as a class method '.
                       '[Class->sequence($seq)] rather than an object method '.
                       '[$obj->sequence($seq)] when setting the sequence.');
        }
    }
    
    $class->__sequence(@_);
}

=pod

=item B<columns>

  @all_columns  = $obj->columns;
  @columns      = $obj->columns($group);
  Class->columns($group, @columns);

This is an accessor to the names of the database columns of a class.
Its used to construct SQL statements to act on the class.

Columns are grouped together by typical usage, this can allow more
efficient access by loading all columns in a group at once.  For
more information about this, L<"Lazy Population of Columns">. 

There are three 'reserved' groups.  'All', 'Essential' and 'Primary'.

B<'All'> are all columns used by the class.  If not set it will be
created from all the other groups.

B<'Primary'> is the single primary key column for this class.  It
I<must> be set before objects can be used.  (Multiple primary keys
will be supported eventually)

    Class->columns('Primary', 'Title');

B<'Essential'> are the minimal set of columns needed to load and use
the object.  Only the columns in this group will be loaded when an
object is retreive()'d.  Its typically used so save memory on a class
that has alot of columns but most only uses a few of them.  It will
automatically be generated from C<Class->columns('All')> if you don't
set it yourself.

If no arguments are given it will assume you want a list of All columns.

B<NOTE> I haven't decided on this method's behavior in scalar context.

=cut

#'#
__PACKAGE__->mk_classdata('__columns');

sub columns {
    my($proto, $group, @columns) = @_;
    my($class) = ref $proto || $proto;

    # Default to returning 'All' columns.
    $group = 'All' unless defined $group;

    # Get %__Columns from the class's namespace.
    no strict 'refs';
    my $class_columns = $class->__columns || {};

    if(@columns) {
        if( ref $proto ) {
            require Carp;
            Carp::carp('It is prefered to call columns() as a class method '.
                       '[Class->columns($group, @cols)] rather than an '.
                       'object method [$obj->columns($group, @cols)] when '.
                       'setting columns.');
        }

        $class->_mk_column_accessors(@columns);

        $class->normalize(\@columns);

        if( $group eq 'Essential' ) {
            my($prim_col) = $class->columns('Primary');
            unless( grep /^$prim_col$/, @columns ) {
                require Carp;
                Carp::carp('The primary column should be in your essential '.
                           'group.');
            }
        }   

        foreach my $col (@columns) {
            $class->add_fields(PROTECTED, $col) unless 
              $class->is_field($col);
        }

        # Group all these columns together in their group and All.
        # XXX Should this add to the group or overwrite?
        $class_columns->{$group} = { map { ($_=>1) } @columns };
        @{$class_columns->{All}}{@columns} = (1) x @columns 
          unless $group eq 'All';

        # Force columns() to be overriden if necessary.
        $class->__columns($class_columns);

        $class->_flush_col2group;

        return SUCCESS;
    }
    else {
        # Build Essential if not already built.
        if( $group eq 'Essential' and !exists $class_columns->{Essential} ) {
            # Careful to make a copy.
            $class_columns->{Essential} = { %{$class_columns->{All}} };
        }

        unless ( exists $class_columns->{$group} ) {
            require Carp;
            Carp::carp("'$group' is not a column group of '$class'");
            return;
        } else {
            return keys %{$class_columns->{$group}};
        }
    }
}

{
    no strict 'refs';

    sub _mk_column_accessors {
        my($class, @columns) = @_;
        
        my(@col_meths) = @columns;
        $class->normalize(\@columns);
        
        assert(@col_meths == @columns) if DEBUG;

        for my $idx (0..$#columns) {
            my($col)  = $columns[$idx];
            my $accessor = $class->make_accessor($col);
            
            my($meth) = $col_meths[$idx];
            my $alias    = "_${meth}_accessor";
            
            *{$class."\::$meth"} = $accessor
              unless defined &{$class."\::$meth"};
            *{$class."\::$alias"} = $accessor
              unless defined &{$class."\::$alias"};
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

    $class->normalize_one(\$column);

    my $col2group = $class->_get_col2group;

    return exists $col2group->{$column} ? scalar @{$col2group->{$column}}
                                        : NO;
}


__PACKAGE__->mk_classdata('__Col2Group');

sub _get_col2group {
    my($proto) = shift;
    my($class) = ref $proto || $proto;

    no strict 'refs';   
    my $col2group = $class->__Col2Group || {};

    # Build %__Col2Group if necessary.
    unless( keys %$col2group ) {
        while( my($group, $cols) = each %{$class->__columns} ) {
            foreach my $col (keys %$cols) {
                push @{$col2group->{$col}}, $group;
            }
        }
        
        # Allow __Col2Group to override itself if necessary.
        $class->__Col2Group($col2group);
    }

    return $col2group;
}

sub _flush_col2group {
    my($proto) = shift;
    my($class) = ref $proto || $proto;

    my $col2group = $class->__Col2Group;
    %$col2group = ();
}


=pod

=back

=head2 Table relationships, Object relationships

Often you'll want one object to contain other objects in your
database, in the same way one table references another with foreign
keys.  For example, say we decided we wanted to store more information
about directors of our films.  You might set up a table...

    CREATE TABLE Directors (
        Name            VARCHAR(80),
        Birthday        INTEGER,
        IsInsane        BOOLEAN
    )

And put a Class::DBI subclass around it.

    package Film::Directors;
    use base qw(Class::DBI);

    Film::Directors->table('Directors');
    Film::Directors->columns(All    => qw( Name Birthday IsInsane ));
    Film::Directors->columns(Prmary => qw( Name ));
    Film::Directors->set_db(Main => 'dbi:mysql', 'me', 'heywoodjablowme',
                            {AutoCommit => 1});

Now Film can use its Director column as a way of getting at
Film::Directors objects, instead of just the director's name.  Its a
simple matter of adding one line to Film.

    # Director() is now an accessor to Film::Directors objects.
    Film->hasa('Film::Directors', 'Director');

Now the Film->Director() accessor gets and sets Film::Director objects
instead of just their name.

=over 4

=item B<hasa>

    Class->hasa($foreign_class, @foreign_key_columns);

Declares that the given Class has a relationship with the
$foreign_class and is storing $foreign_class's primary key
information in the @foreign_key_columns.

An accessor will be generated with the name of the first element in
@foreign_key_columns.  It gets/sets objects of $foreign_class.  Using
our Film::Director example...

    # Set the director of Bad Taste to the Film::Director object
    # representing Peter Jackson.
    $pj     = Film::Directory->retreive('Peter Jackson');
    $btaste = Film->retreive('Bad Taste');
    $btaste->Director($pj);

hasa() will try to require the foreign class for you.  If the require
fails, it will assume its not a simple require (ie. Foreign::Class
isn't in Foreign/Class.pm) and that you've already taken care of it
and ignore the warning.

It is not necessary to call columns() to set up the
@foreign_key_columns.  hasa() will do this for you if you haven't
already.

XXX I don't know if I like the way this works.  It may change a bit in
the future.  I'm not sure about the way the accessor is named.

NOTE  The two classes do not have to be in the same database!

=cut

#'#
__PACKAGE__->mk_classdata('__hasa_columns');

sub hasa {
    my($class, $foreign_class, @foreign_key_cols) = @_;

    my $foreign_col_accessor = "_".$foreign_key_cols[0]."_accessor";

    eval "require $foreign_class";

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
        
        if ( @_ ) {             # setting
            my($obj) = shift;
            $self->{$obj_key} = $obj;
            
            # XXX Have to fix this for mult-col foreign keys.
            $self->$foreign_col_accessor($obj->id);
        }
        
        unless ( defined $self->{$obj_key} ) {
            # XXX Fix this, too.
            my $obj_id = $self->$foreign_col_accessor();
            $self->{$obj_key} = $foreign_class->retrieve($obj_id) if
              defined $obj_id;
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


=pod

=back

=head2 Lazy Population of Columns

In the tradition of Perl, Class::DBI is lazy about how it loads your
objects.  Often, you find yourself using only a small number of the
available columns and it would be a waste of memory to load all of
them just to get at two, especially if you're dealing with large
numbers of objects simultaneously.

Class::DBI will load a group of columns together.  You access one
column in the group, and it will load them all on the assumption that
if you use one you're probably going to use the rest.  So for example,
say we wanted to add NetProfit and GrossProfit to our Film class.
You're probably going to use them together, so...

    Film->columns('Profit', qw(NetProfit GrossProfit));

Now when you say:

    $net = $film->NetProfit;

Class::DBI will load both NetProfit and GrossProfit from the database.
If you then call GrossProfit() on that same object it will not have to
hit the database.  This can potentially increase performance (YMMV).


If you don't like this behavior, just create a group called 'All' and
stick all your columns into it.  Then Class::DBI will load everything
at once.


=head2 Data Normalization

SQL is largely case insensitive.  Perl is largely not.  This can lead
to problems when reading information out of a database.  Class::DBI
does some data normalization.

=over 4

=item B<normalize>

  $obj->normalize(\@columns);

There is no guarantee how a database will muck with the case of
columns, so to protect against things like DBI->fetchrow_hashref()
returning strangely cased column names (along with table names
appended to the front) we normalize all column names before using them
as data keys.

=cut

sub normalize {
    my($self, $columns) = @_;
    
    assert(ref $columns eq 'ARRAY') if DEBUG;

    foreach my $col (@$columns) {
        $col =~ s/^.*\.//;  # Chop off the possible table & database names.
        # 0A is ASCII 11 vertical tab.
        $col =~ tr/ \t\n\r\f\x0A/______/;  # Translate whitespace to _
        $col = lc $col;
    }
    
    return SUCCESS;
}


# XXX Icky hack.
sub normalize_one {
    my($self, $col) = @_;

    my @cols = ($$col);
    $self->normalize(\@cols);
    $$col = $cols[0];
}


=pod

=item B<normalize_hash>

    $obj->normalize_hash(\%hash);

Given a %hash, it will normalize all its keys using normalize().
This is for convenience.

=cut

sub normalize_hash {
    my($self, $hash) = @_;
    my(@normal_cols, @cols);

    @normal_cols = @cols = keys %$hash;
    $self->normalize(\@normal_cols);
    
    assert(@normal_cols == @cols) if DEBUG;

    @{$hash}{@normal_cols} = delete @{$hash}{@cols};

    return SUCCESS;
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
set_sql() to generate cached statement handles.

Generally, a call to set_sql() looks something like this:

    # Define sql_GetFooBar()
    Class->set_sql('GetFooBar', <<'SQL');
    SELECT %s
    FROM   %s
    WHERE  Foo = ? AND Bar = ?

This generates a method called sql_GetFooBar().  Any arguments given
are used fill in your SQL statement via sprintf().

    my $sth = Class->sql_GetFooBar(join(', ', Class->columns('Essential')),
                                   Class->table);

You must be careful not to hardcode information about your class's
table name or primary key column in your statement and instead use
the table() and columns() methods instead.

If $db_name is omitted it will assume you are using the 'Main'
connection.

=cut

# Override set_sql() so it has a default database connection.
sub set_sql {
    my($class, $name, $sql, $db) = @_;
    $db = 'Main' unless defined $db;

    $class->SUPER::set_sql($name, $sql, $db);
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

__PACKAGE__->set_sql('Search', <<"", 'Main');
SELECT  %s 
FROM    %s
WHERE   %s = ?


sub search {
    my($proto, $key, $value) = @_;
    my($class) = ref $proto || $proto;

    $class->normalize_one(\$key);

    assert($class->is_column($key)) if DEBUG;

    my $sth;
    eval {
        $sth = $class->sql_Search(join(', ', $class->columns('Essential')),
                              $class->table,
                              $key);
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

XXX Should I offer glob-style * and ? instead of % and _?

    # Search for movies directed by guys named Bob.
    @films = Film->search_like('Director', 'Bob %');

=cut

__PACKAGE__->set_sql('SearchLike', <<"", 'Main');
SELECT    %s
FROM      %s
WHERE     %s LIKE ?


sub search_like {
    my($proto, $key, $pattern) = @_;
    my($class) = ref $proto || $proto;

    $class->normalize_one(\$key);

    assert($class->is_column($key)) if DEBUG;

    my $sth;
    eval {
        $sth = $class->sql_SearchLike(join(', ', $class->columns('Essential')),
                                      $class->table,
                                      $key
                                     );
        $sth->execute($pattern);
    };
    if($@) {
        $class->DBIwarn("'$key' -> '$pattern'", 'SearchLike');
        return;
    }

    return map { $class->construct($_) } $sth->fetchall_hash;
}


=pod

=head1 EXAMPLES

Ummm... well, there's the SYNOPSIS.

XXX Need more examples.  They'll come.


=head1 CAVEATS

=head2 Only simple scalar values can be stored

SQL sucks in that lists are really complicated to store and hashes
practically require a whole new table.  Don't even start about
anything more complicated.  If you want to store a list you're going
to have to write the accessors for it yourself (although I plan to
prove ways to handle this soon).  If you want to store a hash you
should probably consider making a new table and a new class.

Someone might be able to convince me to build accessors which
automagically serialize data.

=head2 One table, one class

For every class you define one table.  Classes cannot be spread over
more than one table, this is too much of a headache to deal with.

Eventually I'll ease this restriction for link tables and tables
representing lists of data.

=head2 Single column primary keys only

Having more than one column as your primary key in the SQL table is
currently not supported.  Why?  Its more complicated.  A later version
will support multi-column keys.


=head1 TODO

=head2 Table/object relationships need to be handled.

There's no graceful way to handle relationships between two
tables/objects.  I plan to eventually support these relationships in a
fairly simple manner.

=head2 Lists are poorly supported

There's no graceful way to handle lists of things as object data.
This is also something I plan to implement eventually.

=head2 Using pseudohashes as objects has to be documented

=head2 Cookbook needs to be written

=head2 Object caching needs to be added

=head2 Multi-column primary keys untested.

If you need this feature let me know and I'll get it working.

=head2 More testing with more databases.

=head2 Complex data storage via Storable needed.

=head2 There are concurrency problems

=head2 rollback() has concurrency problems

=head2 Working with transactions needs to be made easier.

$obj->commit should DBI->commit???

Need an easy way to do class-wide commit and rollback.


=head1 BUGS and CAVEATS

=head2 Tested with...

=over 4

=item DBD::mysql - MySQL 3.22 and 3.23

=item DBD::Pg - PostgreSQL 7.0

=item DBD::CSV

=back

=head2 Known not to work with...

=over 4

=item DBD::RAM

=back


=head1 AUTHOR

Michael G Schwern <schwern@pobox.com> with much late-night help from
Uri Gutman, Damian Conway, Mike Lambert and the POOP group.


=head1 SEE ALSO

L<Ima::DBI>, L<Class::Accessor>, L<base>, L<Class::Data::Inheritable>
http://www.pobox.com/~schwern/papers/Class-DBI/,
Perl Object-Oriented Persistence E<lt>poop-group@lists.sourceforge.netE<gt>,
L<Alzabo> and L<Tangram>

=cut
