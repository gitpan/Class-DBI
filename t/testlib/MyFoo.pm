package MyFoo;

require './t/testlib/MyBase.pm';
@ISA = 'MyBase';
use strict;
use Date::Simple;

__PACKAGE__->set_table();
__PACKAGE__->columns(All => qw/id name val tdate/);
__PACKAGE__->add_trigger(
  select => \&_date_to_object,
);

sub _column_placeholder {
  my ($self, $column) = @_;
  return $column eq "tdate" ? "IF(1, CURDATE(), ?)" : "?";
}

sub _date_to_object {
  my $self = shift;
  $self->{tdate} = Date::Simple->new($self->{tdate})
    unless not exists $self->{tdate} or
      (ref $self->{tdate} and $self->{tdate}->isa("Date::Simple"));
}


sub create_sql {
  return qq{
    id mediumint not null auto_increment primary key,
    name varchar(50) not null default '',
    val  char(1) default 'A',
    tdate date not null
  };
}

1;

