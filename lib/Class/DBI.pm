package Class::DBI;

require 5.00502;

use strict;

use vars qw($VERSION);
$VERSION = '0.28';

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

=head1 NAME

  Class::DBI - Simple Object Persistence

=head1 SYNOPSIS

  package Film;
  use base qw(Class::DBI);

  # Tell Class::DBI a little about yourself.
  Film->table('Movies');
  Film->columns(All => qw/Title Director Rating NumExplodingSheep/);

  Film->set_db('Main', 'dbi:mysql', 'me', 'noneofyourgoddamnedbusiness',
               {AutoCommit => 1});


  #-- Meanwhile, in a nearby piece of code! --#
  use Film;

  # Create a new film entry for Bad Taste.
  $btaste = Film->create({ Title       => 'Bad Taste',
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
Note that this connection MUST be called 'Main'.

XXX I should probably make this even simpler.  set_db_main() or something.

  Film->set_db('Main', 'dbi:mysql', 'user', 'password', {AutoCommit => 1});

set_db() is inherited from Ima::DBI.  See that module's man page for
details.

=item I<Done.>

All set!  You can now use the constructors (create(), copy() and
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

=item B<create>

    $obj = Class->create(\%data);

This is a constructor to create a new object and store it in the
database.  %data consists of the initial information to place in your
object and the database.  The keys of %data match up with the columns
of your objects and the values are the initial settings of those
fields.

$obj is an instance of Class built out of a hash reference.

  # Create a new film entry for Bad Taste.
  $btaste = Film->create({ Title       => 'Bad Taste',
                           Director    => 'Peter Jackson',
                           Rating      => 'R',
                           NumExplodingSheep   => 1
                         });

If the primary column is not in %data, create() will assume it is to be
generated.  If a sequence() has been specified for this Class, it will
use that.  Otherwise, it will assume the primary key has an
AUTO_INCREMENT constraint on it and attempt to use that.

If the class has declared relationships with foreign classes via
hasa(), it can pass an object to create() for the value of that key.
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

sub _next__in_sequence {
  my $self = shift;
  my $sth = $self->sql_Nextval($self->sequence);
     $sth->execute;
  return ($sth->fetchrow_array)[0];
}

sub _insert_row {
  my $self = shift;
  my $data = shift;
  eval {
    # Enter a new row into the database containing our object's information.
    my $sth = $self->sql_MakeNewObj(
      $self->table,
      join(', ', keys %$data),
      join(', ', ('?') x keys %$data)
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

sub create {
  my $proto = shift;
  my $class = ref $proto || $proto;
  my $table = $class->table or croak "Can't create without a table";
  my $self  = $class->_init;
  my $data  = shift;
  croak 'data to create() must be a hashref' unless ref $data eq 'HASH';
  $self->normalize_hash($data);

  $self->is_column($_) or croak "$_ is not a column" foreach keys %$data;

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

=item B<new>

  $obj = Class->new(\%data);

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

=item B<retrieve>

  $obj = Class->retrieve($id);

Given an ID it will retrieve an object with that ID from the database.

  my $gone = Film->retrieve('Gone With The Wind');

=cut

sub retrieve {
  my $class = shift;
  my $id = shift or return;
  my @rows = $class->_run_search('Search', $class->primary, $id);
  return $rows[0];
}

=item B<construct>

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

=item B<copy>

  $new_obj = $obj->copy;
  $new_obj = $obj->copy($new_id);

This creates a copy of the given $obj both in memory and in the
database.  The only difference is that the $new_obj will have a new
primary identifier.  $new_id will be used if provided, otherwise the
usual sequence or autoincremented primary key will be used.

    my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");

=item B<move>

  my $new_obj = Sub::Class->move($old_obj);
  my $new_obj = Sub::Class->move($old_obj, $new_id);

For transfering objects from one class to another.  Similar to copy(),
an instance of Sub::Class is created using the data in $old_obj
(Sub::Class is a subclass of $old_obj's subclass).  Like copy(),
$new_id is used as the primary key of $new_obj, otherwise the usual
sequence or autoincrement is used.

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

=back

=head2 Accessors

Class::DBI inherits from Class::Accessor and thus
provides accessor methods for every column in your subclass.  It
overrides the get() and set() methods provided by Accessor to
automagically handle database writing.

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

=item B<commit>

    $obj->commit;

Writes any changes you've made via accessors to disk.  There's nothing
wrong with using commit() when autocommit is on, it'll just silently
do nothing.

=cut

__PACKAGE__->set_sql('commit', <<"", 'Main');
UPDATE %s
SET    %s
WHERE  %s = ?

sub commit {
    my($self) = shift;

    my $table = $self->table;
    assert( defined $table ) if DEBUG;

    if( my @changed_cols = $self->is_changed ) {
        my($primary_col) = $self->primary;

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

=item B<rollback>

  $obj->rollback;

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

sub DESTROY {
    my($self) = shift;

    if( my @changes = $self->is_changed ) {
        carp( $self->id .' in class '. ref($self) .
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
        return @{$self}{@keys};
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
    # We increment instead of setting to 1 because it might be useful to
    # someone to know how many times a value has changed between commits.

    $self->{__Changed}{$key}++ if $self->is_column($key);
    $self->SUPER::set($key, $value);
    $self->commit if $self->autocommit;

    return SUCCESS;
}

=item B<is_changed>

  @changed_keys = $obj->is_changed;

Indicates if the given $obj has uncommitted changes.  Returns a list of
keys which have changed.

=cut

sub is_changed { keys %{shift->{__Changed}} }

=back

=head2 Database information

=over 4

=item B<set_db>

  Class->set_db($db_name, $data_source, $user, $password, \%attr);

For details on this method, L<Ima::DBI>.

The special connection named 'Main' must always be set.  Connections
are inherited.

Its often wise to set up a "top level" class for your entire
application to inherit from, rather than directly from Class::DBI.
This gives you a convenient point to place system-wide overrides and
enhancements to Class::DBI's behavior.  It also lets you set the Main
connection in one place rather than scattering the connection info all
over the code.

  package My::Class::DBI;

  use base qw(Class::DBI);
  __PACKAGE__->set_db('Main', 'dbi:foo', 'user', 'password');


  package My::Other::Thing;

  # Instead of inheriting from Class::DBI.  We now have the Main
  # connection all set up.
  use base qw(My::Class::DBI);

Class::DBI helps you along a bit to set up the database connection.
set_db() normally provides its own default attributes on a per
database basis.  For instance, if MySQL is detected, AutoCommit will
be turned on.  Under Oracle, ChopBlanks is turned on.  As more
databases are tested, more defaults will be added.

The defaults can always be overridden by supplying your own %attr.

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

=item B<id>

  $id = $obj->id;

Returns a unique identifier for this object.  Its the equivalent of
$obj->get($self->columns('Primary'));

=cut

sub id {
    my($self) = shift;
    return $self->get($self->primary);
}

=begin _unimplemented

=item B<schema>

  Class->schema(\%schema_def);

This is a convenience method to give a class's schema all in one shot,
without lots of calls to columns().  It takes a single argument which
is a hash ref representing the table schema.  This has two keys:
table and columns.  "table" is straightforward, it works just like
table().

"columns" has a few modes of operation.  Given an array ref, it acts just
like a call to columns('All', ...) except it assumes the first column
is also the primary column.  So:

    Class->schema({
                   table    => 'Movies',
                   columns  => [qw( Title Director Rating
                                    NumExplodingSheep )],
                  });

is the same as:

    Class->table('Movies');
    Class->columns('All', qw(Title Director Rating NumExplodingSheep));
    Class->columns('Primary', 'Title');

If "columns" is given a hash ref it considers it to be like calls to
columns($group, @cols);  So:

    Class->schema({
           table    => 'Line_Feature',
           columns  => {
                        Primary   => ['TLID'],
                        Essential => [qw( TLID FeName Chain ) ],
                        Feature   => [qw( FeDirP FeName FeType )],
                        Zip       => [qw( ZipL Zip4L ZipR Zip4R )],
                       }
    });

is the same as:

    Class->table('Line_Feature');
    Class->columns('Primary', 'TLID');
    Class->columns('Essential', qw( TLID FeName Chain ));
    Class->columns('Feature',   qw( FeDirP FeName FeType ));
    Class->columns('Zip',       qw( ZipL Zip4L ZipR Zip4R ));

=end _unimplemented

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
  my $proto = shift;
  my $class = ref $proto || $proto;
  $class->_invalid_object_method('table()') if @_ and ref $proto;
  $class->__table(@_);
}

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
  my $proto = shift;
  my $class = ref $proto || $proto;
  $class->_invalid_object_method('sequence()') if @_ and ref $proto;
  $class->__sequence(@_);
}

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
object is retrieve()'d.  Its typically used so save memory on a class
that has alot of columns but most only uses a few of them.  It will
automatically be generated from C<Class->columns('All')> if you don't
set it yourself.  The 'Primary' column is always part of your
'Essential' group and Class::DBI will put it there if you don't.

If 'All' is given but not 'Primary' it will assume the first column in
'All' is the primary key.

If no arguments are given it will assume you want a list of All columns.

B<NOTE> I haven't decided on this method's behavior in scalar context.

=cut

sub _invalid_object_method {
  my ($self, $method) = @_;
  carp "$method should be called as a class method not an object method";
}

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
sub essential { (shift->columns('Essential'))[0] }

sub _mk_column_accessors {
  my($class, @col_meths) = @_;
  my(@columns) = $class->_normalized(@col_meths);

  assert(@col_meths == @columns) if DEBUG;

  no strict 'refs';
  for my $i (0..$#columns) {
    my $col      = $columns[$i];
    my $meth     = $col_meths[$i];
    my $alias    = "_${meth}_accessor";
    my $accessor = $class->make_accessor($col);

    *{"$class\::$meth"}  = $accessor unless defined &{"$class\::$meth"};
    *{"$class\::$alias"} = $accessor unless defined &{"$class\::$alias"};
  }
}

=item B<is_column>

    Class->is_column($column);
    $obj->is_column($column);

This will return true if the given $column is a column of the class or
object.

=cut

sub is_column {
  my $proto = shift;
  my $class = ref $proto || $proto;
  my $column = $class->_normalized(shift);
  my $col2group = $class->_get_col2group;
  return exists $col2group->{$column} ? scalar @{$col2group->{$column}} : 0;
}

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

Declares that the given Class has a one-to-one or many-to-one 
relationship with the $foreign_class and is storing $foreign_class's
primary key information in the @foreign_key_columns.

An accessor will be generated with the name of the first element in
@foreign_key_columns.  It gets/sets objects of $foreign_class.  Using
our Film::Director example...

    # Set the director of Bad Taste to the Film::Director object
    # representing Peter Jackson.
    $pj     = Film::Director->retrieve('Peter Jackson');
    $btaste = Film->retrieve('Bad Taste');
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


sub _load_class {
    my($foreign_class) = shift;

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

  Class->hasa_list($foreign_class, \@foreign_keys, $accessor_name);

Declares that the given Class has a one-to-many relationship with the
$foreign_class.  Class's primary key is stored in @foreign_key columns
in the $foreign_class->table.  An accessor will be generated with the
given $accessor_name and it returns a list of objects related to the
Class.

Ok, confusing.  Its like this...

    CREATE TABLE Actors (
        Name            CHAR(40),
        Film            VARCHAR(255)    REFERENCES Movies,

        # Its sad that the average salary won't fit into an integer.
        Salary          BIG INTEGER UNSIGNED
    );

with a subclass around it.

    package Film::Actors;
    use base qw(Class::DBI);

    Film::Actors->table('Actors');
    Film::Actors->columns(All   => qw(Name Film Salary));
    Film::Actors->set_db(...);

Any film is going to have lots of actors.  You'd declare this
relationship like so:

    Film->hasa_list('Film::Actors', ['Film'], 'overpaid_gits');

Declars that a Film has many Film::Actors associated with it.  These
are stored in the Actors table (gotten from Film::Actors->table) with
the column Film containing Film's primary key.  This is accessed via
the method 'overpaid_gits()'.

    my @actors = $film->overpaid_gits;

This basically does a "'SELECT * FROM Actors WHERE Film = '.$film->id"
turning them into objects and returning.

The accessor is currently read-only.

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

=head2 Transactions

Class::DBI is just now becoming dimly aware of transactions as people
are starting to use it with PostgreSQL and Oracle.  Class::DBI
currently works best with DBI's AutoCommit turned on, however I am
working on making it seemless when AutoCommit is off.

When using transactions with Class::DBI you must be careful to
remember two things...

=over 4

=item 1

Your database handles are B<shared> with possibly many other totally
unrelated classes.  This means if you commit one class's handle you
might actually be committing another class's transaction as well.

=item 2

A single class might have many database handles.  Even worse, if
you're working with a subclass it might have handles you're not aware
of!

=back

At the moment, all I can say about #1 is keep the scope of your
transactions small, preferably down to the scope of a single method.
I am working on a system to remove this problem.

For #2 we offer the following...

=over 4

=item B<dbi_commit>

  my $rv = Class->dbi_commit;
  my $rv = Class->dbi_commit(@db_names);

This commits the underlying handles associated with the Class.  If any
of the commits fail, it returns false.  Otherwise true.

If @db_names is not given it will commit all the database handles
associated with this class, otherwise it will only commit those
handles named (like 'Main' for instance).

This is different than commit() so we call it dbi_commit() to
disambiguate.

This is an alias to Ima::DBI->commit().

=cut

sub dbi_commit {
    my($proto, @db_names) = @_;
    $proto->SUPER::commit(@db_names);
}

=item B<dbi_rollback>

  Class->dbi_rollback;
  Class->dbi_rollback(@db_names);

Like dbi_commit() above, this rollsback all the database handles
associated with the Class.

This is an alias to Ima::DBI->rollback().

=cut

sub dbi_rollback {
    my($proto, @db_names) = @_;
    $proto->SUPER::rollback(@db_names);
}

=back

So how might you use this?  At the moment, something like this...

  eval {
      # Change a bunch of things in memory
      $obj->foo('bar');
      $obj->this('that');
      $obj->price(1456);

      # Write them to the database.
      $obj->commit;
  };
  if($@) {
      # Ack!  Something went wrong!  Warn, rollback the transaction
      # and flush out the object in memory as it may be in an odd state.
      $obj->DBIwarn($obj->id, 'update price');
      $obj->dbi_rollback;
      $obj->rollback;
  }
  else {
      # Everything's hoopy, commit the transaction.
      $obj->dbi_commit;
  }

Kinda clunky, but servicable.  As I said, better things are on the way.

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
     croak "$key is not a column" unless $class->is_column($key);
  my $val = shift;
  my $sth = $class->_run_query($SQL, [$key], [$val]) or return;
  return map $class->construct($_), $sth->fetchall_hash;
}

sub _run_query {
  my $class = shift;
  my ($type, $keys, $vals, $columns) = @_;
  $columns ||= [ $class->columns('Essential') ];
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

=head1 EXAMPLES

Ummm... well, there's the SYNOPSIS.

We need more examples.  They'll come.

=head1 CAVEATS

=head2 Class::DBI and mod_perl

Class::DBI was first designed for a system running under FastCGI,
which is basically a slimmer version of mod_perl.  As such, it deals
with both just fine, or any other persistent environment, and takes
advantage of it by caching database and statement handles as well as
some limited object data caching.

In short, there's no problem with using Class::DBI under mod_perl.  In
fact, it'll run better.

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

hasa_list() is a start, but I think the hasa() concept is weak.

=head2 Using pseudohashes as objects has to be documented

=head2 Cookbook needs to be written

=head2 Object caching needs to be added

=head2 Multi-column primary keys

If you need this feature let me know and I'll get it working.

=head2 More testing with more databases.

=head2 Complex data storage via Storable needed.

=head2 There are concurrency problems

=head2 rollback() has concurrency problems

=head2 Transactions yet to be completely implemented

dbi_commit() is a start, but not done.

=head2 Make all internal statements use fully-qualified columns

=head1 BUGS and CAVEATS

Altering the primary key column currently causes Bad Things to happen.

=head2 Tested with...

DBD::mysql - MySQL 3.22 and 3.23

DBD::Pg - PostgreSQL 7.0

DBD::CSV

=head2 Reports it works with...

DBD::Oracle (patches still coming in)

=head2 Known not to work with...

DBD::RAM

=head1 AUTHOR

Michael G Schwern <schwern@pobox.com> with much late-night help from
Uri Gutman, Damian Conway, Mike Lambert and the POOP group.

Now developed and maintained by Tony Bowden <kasei@tmtm.com>

=head1 SEE ALSO

L<Ima::DBI>, L<Class::Accessor>, L<base>, L<Class::Data::Inheritable>
http://www.pobox.com/~schwern/papers/Class-DBI/,
Perl Object-Oriented Persistence E<lt>poop-group@lists.sourceforge.netE<gt>,
L<Alzabo> and L<Tangram>

=cut
