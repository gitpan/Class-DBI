package Class::DBI::Iterator;

use strict;
use base 'Class::DBI';
use overload 
 '0+' => 'count',
 fallback => 1;

sub new {
  my ($me, $them, @data) = @_;
  bless {
    _class => $them,
    _data  => \@data,
    _place => 0,
  }, $me;
}

sub class { shift->{_class}    }
sub data  { @{shift->{_data}}  }
sub count { scalar shift->data }

sub next {
  my $self  = shift;
  my @data  = $self->data;
  my $use   = $data[$self->{_place}++] or return;
  return $self->class->construct($use);
}

sub first { 
  my $self = shift;
  $self->{_place} = 0;
  return $self->next;
}

1;
