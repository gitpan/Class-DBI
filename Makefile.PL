# $Id: Makefile.PL,v 1.9 2000/09/10 05:07:25 schwern Exp $
#
# A template for Makefile.PL used by Arena Networks.
# - Set the $PACKAGE variable to the name of your module.
# - Set $LAST_API_CHANGE to reflect the last version you changed the API 
#   of your module.
# - Fill in your dependencies in PREREQ_PM
# Alternatively, you can say the hell with this and use h2xs.

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

$PACKAGE = 'Class::DBI';
($PACKAGE_FILE) = $PACKAGE =~ /::([^:]+)/;
$LAST_API_CHANGE = 0.85;

require 5.00502;

eval "require $PACKAGE";

unless ($@) { # Make sure we did find the module.
    print <<"CHANGE_WARN" if ${$PACKAGE.'::VERSION'} < $LAST_API_CHANGE;

NOTE: There have been API changes between this version and any older than
version $LAST_API_CHANGE!  Please check carefully if you are upgrading
from a version older than $LAST_API_CHANGE.

Significant changes:

  0.85 - Class::DBI no longer supports pseudo-hash based objects
       - hasa_list is now deprecated in favour of has_many
       - has_many auto-creates a reciprocal hasa relationship

  0.32 - delete() now removes any foreign elements, to avoid orphans

CHANGE_WARN
}

WriteMakefile(
  NAME                => $PACKAGE,
  VERSION_FROM        => 'lib/Class/DBI.pm',
  PREREQ_PM           => {
    Carp::Assert             => '0.06',
    Class::Accessor          => '0.10',
    Class::Data::Inheritable => '0.02',
    DBD::CSV                 => '0.1022',
    Ima::DBI                 => '0.26',
    protected                => '0.01',
    Test::More               => '0.11',
    File::Temp               => '0.12',
    Class::Trigger           => '0.03',
  },
  dist              => { 
    COMPRESS   => 'gzip -9',
    SUFFIX     => '.gz',
    DIST_DEFAULT   => 'all tardist',
  },
);
