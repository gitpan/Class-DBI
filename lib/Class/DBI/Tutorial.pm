package Class::DBI::Tutorial;

use strict;

=head1 NAME

  Class::DBI - Simple Database Abstraction

=head1 SYNOPSIS

  package Film;
  use base 'Class::DBI';

  __PACKAGE__->set_db('Main', 'dbi:mysql', 'username', 'password');

  __PACKAGE__->table('Movies');
  __PACKAGE__->columns(All => qw/Title Director Rating NumExplodingSheep/);

  #-- Meanwhile, in a nearby piece of code! --#

  use Film;

  # Create a new film entry for Bad Taste.
  my $btaste = Film->create({ Title       => 'Bad Taste',
                              Director    => 'Peter Jackson',
                              Rating      => 'R',
                              NumExplodingSheep   => 1
                           });

  # Shocking new footage found reveals bizarre Scarlet/sheep scene!
  my $gone = Film->retrieve('Gone With The Wind');
     $gone->NumExplodingSheep(5);
     $gone->Rating('NC-17');
     $gone->commit;

  # Make a copy of 'Bladerunner' and create an entry of the director's
  # cut from it.
  my $blrunner    = Film->retrieve('Bladerunner');
  my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");

  # Ishtar doesn't deserve an entry anymore.
  Film->retrieve('Ishtar')->delete;

  # Find all films which have a rating of PG.
  @films = Film->search('Rating', 'PG');

  # Find all films which were directed by Bob
  @films = Film->search_like('Director', 'Bob %');

=head1 DESCRIPTION

Although the difficulties in serialising objects to a relational database
are well documented, we often find outselves using such a database to
store the data that will make up the objects in our system.

Thus we end up writing many classes, each mapping to a table in our
database, and each containing accessor and mutator methods for each of
the columns. We then write simple constructors, search methods and the
like for each these classes.

Class::DBI is here to make this task trivial.

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

Using our Film example, you might declare a table something like this:

  CREATE TABLE Movies (
         Title      VARCHAR(255)    PRIMARY KEY,
         Director   VARCHAR(80),
         Rating     CHAR(5),    /* to fit at least 'NC-17' */
         NumExplodingSheep      INTEGER
  )

=item I<Inherit from Class::DBI.>

It is prefered that you use base.pm to do this rather than appending
directly to @ISA, as your class may have to inherit some protected data
fields from Class::DBI.

  package Film;
  use base 'Class::DBI';

=item I<Declare a database connection>

Class::DBI needs to know how to access the database.  It does this
through a DBI connection which you set up.  Set up is by calling the
set_db() method and declaring a database connection named 'Main'.
(Note that this connection MUST be called 'Main').

  Film->set_db('Main', 'dbi:mysql', 'user', 'password');

[See L<Ima::DBI> for more details on set_db()]

=item I<Declare the name of your table>

Inform Class::DBI what table you are using for this class:

  Film->table('Movies');

=item I<Declare your columns.>

This is done using the columns() method. In the simplest form, you tell
it the name of all your columns (primary key first):

  Film->columns(All => qw/Title Director Rating NumExplodingSheep/);

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

Its often wise to set up a "top level" class for your entire application
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

=head2 columns

  __PACKAGE__->columns('Primary'   => 'Title');
  __PACKAGE__->columns('Essential' => 'Title', 'Director');

  my @all_columns  = $obj->columns;
  my @columns      = $obj->columns($group);

You should group together your columns by typical usage, as fetching
one value from a group also pre-fetches all the others in that
group for you, for more efficient access. For more information about this,
L<"Lazy Population">.

There are three 'reserved' groups.  'All', 'Essential' and 'Primary'.

B<'All'> are all columns used by the class.  If not set it will be
created from all the other groups.

B<'Primary'> is the single primary key column for this class.  It I<must>
be set before objects can be used.  (Multiple primary keys will be
supported eventually) If 'All' is given but not 'Primary' it will assume
the first column in 'All' is the primary key.

B<'Essential'> are the minimal set of columns needed to load and use
the object.  Only the columns in this group will be loaded when an object
is retrieve()'d.  It's typically used to save memory on a class that has
a lot of columns but where we mostly only use a few of them.  It will
automatically be generated from B<'All'> if you don't set it yourself.
The 'Primary' column is always part of your 'Essential' group and
Class::DBI will put it there if you don't.

B<NOTE> I haven't decided on this method's behavior in scalar context.

=head2 has_column

    Class->has_column($column);
    $obj->has_column($column);

This will return true if the given $column is a column of the class or
object.

=head1 CONSTRUCTORS and DESTRUCTORS

The following are methods provided for convenience to create, retrieve
and delete stored objects.  Its not entirely one-size fits all and you
might find it necessary to override them.

=head2 create

    my $obj = Class->create(\%data);

This is a constructor to create a new object and store it in the database.

%data consists of the initial information to place in your object and
the database.  The keys of %data match up with the columns of your
objects and the values are the initial settings of those fields.

  # Create a new film entry for Bad Taste.
  $btaste = Film->create({ Title       => 'Bad Taste',
                           Director    => 'Peter Jackson',
                           Rating      => 'R',
                           NumExplodingSheep   => 1
                         });

If the primary column is not in %data, create() will assume it is
to be generated.  If a sequence() has been specified for this Class,
it will use that.  Otherwise, it will assume the primary key has an
AUTO_INCREMENT constraint on it and attempt to use that.

If the class has declared relationships with foreign classes via
hasa(), it can pass an object to create() for the value of that key.
Class::DBI will Do The Right Thing.

=head2 retrieve

  $obj = Class->retrieve($id);

Given an ID it will retrieve an object with that ID from the database.

  my $gone = Film->retrieve('Gone With The Wind');

=head2 retrieve_all

  @objs = Class->retrieve_all;

Retrieves objects for all rows in the database. (This is probably a 
bad idea if your table is big).  

  my @all_films = Film->retrieve_all;

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

=head2 delete

  $obj->delete;

Deletes this object from the database and from memory. If you have set
up any relationships using hasa_list, delete the foreign elements also.
$obj is no longer usable after this call.

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

Writes any changes you've made via accessors to disk.  There's nothing
wrong with using commit() when autocommit is on, it'll just silently
do nothing.

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

Returns a unique identifier for this object.  Its the equivalent of
$obj->get($self->columns('Primary'));

=head1 TABLE RELATIONSHIPS

Often you'll want one object to contain other objects in your database, in
the same way one table references another with foreign keys.  For example,
say we decided we wanted to store more information about directors of
our films.  You might set up a table...

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
Film::Directors objects, instead of just the director's name.  It's a
simple matter of adding one line to Film:

    # Director() is now an accessor to Film::Directors objects.
    Film->hasa('Film::Directors', 'Director');

Now the Film->Director() accessor gets and sets Film::Director objects
instead of just their name.

=head2 hasa

    __PACKAGE__->hasa($foreign_class, @foreign_key_columns);

Declares that the given Class has a one-to-one or many-to-one relationship
with the $foreign_class and is storing $foreign_class's primary key
information in the @foreign_key_columns.

An accessor will be generated with the name of the first element
in @foreign_key_columns.  It gets/sets objects of $foreign_class.
Using our Film::Director example...

    # Set the director of Bad Taste to the Film::Director object
    # representing Peter Jackson.
    $pj     = Film::Director->retrieve('Peter Jackson');
    $btaste = Film->retrieve('Bad Taste');
    $btaste->Director($pj);

hasa() will try to require the foreign class for you.  If the require
fails, it will assume its not a simple require (ie. Foreign::Class isn't
in Foreign/Class.pm) and that you've already taken care of it and ignore
the warning.

It is not necessary to call columns() to set up the @foreign_key_columns.
hasa() will do this for you if you haven't already.

NOTE  The two classes do not have to be in the same database!

XXX I don't know if I like the way this works.  It may change a bit in
the future.  I'm not sure about the way the accessor is named.

=head2 hasa_list

  __PACKAGE__->hasa_list($foreign_class, \@foreign_keys, $accessor_name);

Declares that the given Class has a one-to-many relationship with the
$foreign_class.  Class's primary key is stored in @foreign_key columns in
the $foreign_class->table.  An accessor will be generated with the given
$accessor_name and it returns a list of objects related to the Class.

Ok, confusing.  Its like this...

    CREATE TABLE Actors (
        Name            CHAR(40),
        Film            VARCHAR(255)    REFERENCES Movies,
        # Its sad that the average salary won't fit into an integer.
        Salary          BIG INTEGER UNSIGNED
    );

with a subclass around it:

    package Film::Actors;
    use base qw(Class::DBI);

    Film::Actors->table('Actors');
    Film::Actors->columns(All   => qw(Name Film Salary));
    Film::Actors->set_db(...);

Any film is going to have lots of actors.  You'd declare this relationship
like so:

    Film->hasa_list('Film::Actors', ['Film'], 'actors');

Declars that a Film has many Film::Actors associated with it.  These are
stored in the Actors table (gotten from Film::Actors->table) with the
column Film containing Film's primary key.  This is accessed via the
method 'actors()'.

    my @actors = $film->actors;

This basically does a "'SELECT * FROM Actors WHERE Film = '.$film->id"
turning them into objects and returning.

The accessor is currently read-only.

=head2 Many To Many Relationships

This means that it is now possible to define many to many relationships
using a combination of 'hasa' and 'hasa' list.

Let's say we set up a table for producers (with name and height), and
then another one for mapping each producer to each Film (with 'producer'
and 'film' columns cross-referencing to the respective names).

Thus we would create:

  package Producer;
  Producer->table('producer');
  Producer->columns(All => qw/Name Height/);

  package FilmProducer;
  FilmProducer->table('producer_to_film_xref');
  FilmProducer->columns(All => qw/Film Producer/);
  FilmProducer->hasa('Producer', 'producer');

and add the link to Film:

  Film->hasa_list('FilmProducer', ['producer'], 'producers');

Now calling $film->producers will retrieve a list of FilmProducer objects
which in turn have a Producer object living in their 'producer()' method,
enabling you to call:

  foreach my $xref ($film->producers) {
    printf "Produced by %s\n", $xref->producer->name;
  }

[At some stage I'd like to make this even easier]

=head1 DEFINING SQL STATEMENTS

Class::DBI inherits from Ima::DBI and prefers to use its style of dealing
with statemtents, via set_sql(). (Now is a good time to skim L<Ima::DBI>.)

In order to write new methods which are inheritable by your subclasses
you must be careful not to hardcode any information about your class's
table name or primary key, and instead use the table() and columns()
methods instead.

Generally, a call to set_sql() looks something like this:

    __PACKAGE__->set_sql('OpeningDate', <<'');
    SELECT %s
    FROM   %s
    WHERE  opening_date >= ?
    AND    opening_date <= ?

This generates a method called sql_OpeningDate(), which you can then
use in an appropriate method:

    sub opening_this_week {
      my $class = shift;
      my $sth;
      eval {
        $sth = $class->sql_GetFooBar(
                      join(', ', Class->columns('Essential')),
                      Class->table
        );
        $sth->execute($last_friday, $this_thursday);
      }
      if (@$) {
        $class->DBIwarn("Can't get films opening this week");
        return;
      }
      return map $class->construct($_), $sth->fetchall_hash;
    }

XXX This process will be made simpler in a later version.

=head1 LAZY POPULATION

In the tradition of Perl, Class::DBI is lazy about how it loads your
objects.  Often, you find yourself using only a small number of the
available columns and it would be a waste of memory to load all of them
just to get at two, especially if you're dealing with large numbers of
objects simultaneously.

Class::DBI will load a group of columns together.  You access one
column in the group, and it will load them all on the assumption that
if you use one you're probably going to use the rest.  So for example,
say we wanted to add NetProfit and GrossProfit to our Film class.
You're probably going to use them together, so...

    Film->columns('Profit', qw/NetProfit GrossProfit/);

Now when you say:

    $net = $film->NetProfit;

Class::DBI will load both NetProfit and GrossProfit from the database.
If you then call GrossProfit() on that same object it will not have to
hit the database.  This can potentially increase performance (YMMV).

If you don't like this behavior, just create a group called 'All' and
stick all your columns into it.  Then Class::DBI will load everything
at once.

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

Class::DBI is just now becoming dimly aware of transactions as people
are starting to use it with PostgreSQL and Oracle.  Class::DBI currently
works best with DBI's AutoCommit turned on, however I am working on
making it seemless when AutoCommit is off.

When using transactions with Class::DBI you must be careful to remember
two things...

=over 4

=item 1

Your database handles are B<shared> with possibly many other totally
unrelated classes.  This means if you commit one class's handle you
might actually be committing another class's transaction as well.

=item 2

A single class might have many database handles.  Even worse, if you're
working with a subclass it might have handles you're not aware of!

=back

At the moment, all I can say about #1 is keep the scope of your
transactions small, preferably down to the scope of a single method.
I am working on a system to remove this problem.

For #2 we offer the following...

=head2 dbi_commit

  my $rv = Class->dbi_commit;
  my $rv = Class->dbi_commit(@db_names);

This commits the underlying handles associated with the Class.  If any
of the commits fail, it returns false.  Otherwise true.

If @db_names is not given it will commit all the database handles
associated with this class, otherwise it will only commit those handles
named (like 'Main' for instance).

This is different than commit() so we call it dbi_commit() to
disambiguate.

This is an alias to Ima::DBI->commit().

=head2 dbi_rollback

  Class->dbi_rollback;
  Class->dbi_rollback(@db_names);

Like dbi_commit() above, this rollsback all the database handles
associated with the Class.

This is an alias to Ima::DBI->rollback().

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

=head1 SEARCHING

We provide a few simple search methods, more to show the potential of
the class than to be serious search methods.

=head2 search

  @objs = Class->search($key, $value);
  @objs = $obj->search($key, $value);

This is a simple search through the stored objects for all objects
whose $key has the given $value.

    @films = Film->search('Rating', 'PG');

=head2 search_like

  @objs = Class->search_like($key, $like_pattern);
  @objs = $obj->search_like($key, $like_pattern);

A simple search for objects whose $key matches the $like_pattern
given.  $like_pattern is a pattern given in SQL LIKE predicate syntax.
'%' means "any one or more characters", '_' means "any single
character".

XXX Perhaps offer * and ? instead of % and _

    # Search for movies directed by guys named Bob.
    @films = Film->search_like('Director', 'Bob %');

=head1 CAVEATS

=head2 Class::DBI and mod_perl

Class::DBI was first designed for a system running under FastCGI, which
is basically a slimmer version of mod_perl.  As such, it deals with both
just fine, or any other persistent environment, and takes advantage of
it by caching database and statement handles as well as some limited
object data caching.

In short, there's no problem with using Class::DBI under mod_perl.
In fact, it'll run better.

=head2 Only simple scalar values can be stored

SQL sucks in that lists are really complicated to store and hashes
practically require a whole new table.  Don't even start about anything
more complicated.  If you want to store a list you're going to have
to write the accessors for it yourself (although I plan to prove ways
to handle this soon).  If you want to store a hash you should probably
consider making a new table and a new class.

Someone might be able to convince me to build accessors which
automagically serialize data.

=head2 One table, one class

For every class you define one table.  Classes cannot be spread over
more than one table, this is too much of a headache to deal with.

Eventually I'll ease this restriction for link tables and tables
representing lists of data.

=head2 Single column primary keys only

Composite primary keys are not yet supported. This will come soon.

=head1 TODO

=head2 Table relationships need to be handled better.

There's no graceful way to handle relationships between two
tables/objects.  I plan to eventually support these relationships in a
fairly simple manner.

=head2 Lists are poorly supported

hasa_list() is a start, but I think the hasa() concept is weak.

=head2 Using pseudohashes as objects has to be documented

=head2 Cookbook needs to be written

=head2 Object caching needs to be added

=head2 More testing with more databases.

=head2 Complex data storage via Storable needed.

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

1;
