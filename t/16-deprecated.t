#!/usr/bin/perl -w

use strict;
use Test::More tests => 4;

package myClassDBI;

use base 'Class::DBI';

sub wibble {
	my $self = shift;
	$self->croak("Croak dies");
}

package main;

{
	local $SIG{__WARN__} = sub { ok $_[0], $_[0]; };
  eval { myClassDBI->croak("Croak dies") };
  like $@, qr/Croak dies/, $@;

  eval { myClassDBI->wibble };
  like $@, qr/Croak dies/, $@;
}


