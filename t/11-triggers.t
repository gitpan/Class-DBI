use strict;
use Test::More tests => 8;

require './t/testlib/Film.pm';
Film->CONSTRUCT;

sub create_trigger  { ::ok(1, "Created " . shift->Title) }
sub create_trigger2 { ::ok(1, "Running create trigger 2");    }
sub delete_trigger  { ::ok(1, "Deleting " . shift->Title) }
sub pre_up_trigger  { ::ok(1, "Running pre-update trigger");  }
sub pst_up_trigger  { ::ok(1, "Running post-update trigger"); }

Film->add_trigger(
  create => \&create_trigger,
  create => \&create_trigger2,
  delete => \&delete_trigger,
  before_update => \&pre_up_trigger,
  after_update => \&pst_up_trigger,
);

ok (my $ver = Film->create({
   Title              => 'La Double Vie De Veronique',
   Director           => 'Kryzstof Kieslowski',
   Rating             => '15',
   NumExplodingSheep  => 0,
}), "Create Veronique");

ok $ver->Rating('12') && $ver->commit, "Change the rating";
ok $ver->delete, "Delete";

