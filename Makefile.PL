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
$LAST_API_CHANGE = 0.05;

require 5.00502;

eval "require $PACKAGE";

unless ($@) { # Make sure we did find the module.
    print <<"CHANGE_WARN" if ${$PACKAGE.'::VERSION'} < $LAST_API_CHANGE;

NOTE: There have been API changes between this version and any older
than version $LAST_API_CHANGE!  Please read the Changes file if you
are upgrading from a version older than $LAST_API_CHANGE.

CHANGE_WARN
}

WriteMakefile(
    NAME                => $PACKAGE,
    VERSION_FROM        => 'lib/Class/DBI.pm',
    PREREQ_PM           => {
                            Carp::Assert        => 0.06,
                            Class::Accessor     => '0.10',
                            Class::Data::Inheritable => 0.02,
                            Class::Fields       => '0.09',
                            Class::Fields::Fuxor=> '0.06',
                            Ima::DBI            => '0.24',
                            base                => 1.94,
                            protected           => 0.01,
                           },
    'dist'              => { COMPRESS   => 'gzip -9',
                             SUFFIX     => '.gz',
                             DIST_DEFAULT   => 'all tardist',
                           },
);
