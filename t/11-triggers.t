use strict;
use Test::More tests => 8;

require './t/testlib/Film.pm';
Film->CONSTRUCT;

sub create_trigger2 { ::ok(1, "Running create trigger 2");    }
sub delete_trigger  { ::ok(1, "Deleting " . shift->Title) }
sub pre_up_trigger  { ::ok(1, "Running pre-update trigger");  }
sub pst_up_trigger  { ::ok(1, "Running post-update trigger"); }

sub default_rating  { $_[0]->Rating(15); }

Film->add_trigger(
  before_create => \&default_rating,
  create => \&create_trigger2,
  delete => \&delete_trigger,
  before_update => \&pre_up_trigger,
  after_update => \&pst_up_trigger,
);

ok (my $ver = Film->create({
   title              => 'La Double Vie De Veronique',
   director           => 'Kryzstof Kieslowski',
   # rating           => '15',
   numexplodingsheep  => 0,
}), "Create Veronique");

is $ver->Rating, 15, "Default rating";
ok $ver->Rating('12') && $ver->commit, "Change the rating";
ok $ver->delete, "Delete";

