use strict;
use Test::More tests => 8;

require './t/testlib/Film.pm';
Film->CONSTRUCT;

sub create_hook  { ::ok(1, "Created " . shift->Title) }
sub create_hook2 { ::ok(1, "Running create hook 2");    }
sub delete_hook  { ::ok(1, "Deleting " . shift->Title) }
sub pre_up_hook  { ::ok(1, "Running pre-update hook");  }
sub pst_up_hook  { ::ok(1, "Running post-update hook"); }

Film->add_hook(
  create => \&create_hook,
  create => \&create_hook2,
  delete => \&delete_hook,
  before_update => \&pre_up_hook,
  after_update => \&pst_up_hook,
);

ok (my $ver = Film->create({
   Title              => 'La Double Vie De Veronique',
   Director           => 'Kryzstof Kieslowski',
   Rating             => '15',
   NumExplodingSheep  => 0,
}), "Create Veronique");

ok $ver->Rating('12') && $ver->commit, "Change the rating";
ok $ver->delete, "Delete";

