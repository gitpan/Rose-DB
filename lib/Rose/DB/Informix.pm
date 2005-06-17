package Rose::DB::Informix;

use strict;

use Rose::DateTime::Util();

use Rose::DB;
our @ISA = qw(Rose::DB);

our $VERSION = '0.012';

our $Debug = 0;

use Rose::Class::MakeMethods::Generic
(
  inheritable_scalar => 'max_array_characters',
);

__PACKAGE__->max_array_characters(255);

#
# Object methods
#

sub build_dsn
{
  my($self_or_class, %args) = @_;
  return "dbi:$args{'driver'}:" . ($args{'db'} || $args{'database'});
}

sub insertid_param { 'unsupported' }
sub null_date      { '0000-00-00'  }
sub null_datetime  { '0000-00-00 00:00:00' }
sub null_timestamp { '0000-00-00 00:00:00.00000' }
sub min_timestamp  { '0001-01-01 00:00:00.00000' }
sub max_timestamp  { '9999-12-31 23:59:59.99999' }

sub last_insertid_from_sth { $_[1]->{'ix_sqlerrd'}[1] }

sub generate_primary_key_values { return; }

sub generate_primary_key_placeholders
{
  (@_ == 1 || (@_ > 1 && $_[1] == 1)) ? 0 : ((undef) x $_[1]) 
}

# Boolean formatting and parsing

sub format_boolean { $_[1] ? 't' : 'f' }

sub parse_boolean
{
  my($self, $value) = @_;
  return $value  if($self->validate_boolean_keyword($_[1]) || $_[1] =~ /^\w+\(.*\)$/);
  return 1  if($value =~ /^[t1]$/i);
  return 0  if($value =~ /^[f0]$/i);

  $self->error("Invalid boolean value: '$value'");
  return undef;
}

# Date formatting

sub format_date
{  
  return $_[1]  if($_[0]->validate_date_keyword($_[1]));
  return Rose::DateTime::Util::format_date($_[1], '%m/%d/%Y');
}

sub format_datetime
{
  return $_[1]  if($_[0]->validate_datetime_keyword($_[1]));
  return Rose::DateTime::Util::format_date($_[1], '%Y-%m-%d %H:%M:%S');
}

sub format_datetime_year_to_second
{
  return $_[1]  if($_[0]->validate_datetime_keyword($_[1]));
  return Rose::DateTime::Util::format_date($_[1], '%Y-%m-%d %H:%M:%S');
}

sub format_datetime_year_to_minute
{
  return $_[1]  if($_[0]->validate_datetime_keyword($_[1]));
  return Rose::DateTime::Util::format_date($_[1], '%Y-%m-%d %H:%M');
}

sub format_time
{  
  return $_[1]  if($_[0]->validate_time_keyword($_[1]));
  return Rose::DateTime::Util::format_date($_[1], '%H:%M:%S');
}

sub format_timestamp
{  
  return $_[1]  if($_[0]->validate_timestamp_keyword($_[1]));
  return Rose::DateTime::Util::format_date($_[1], '%Y-%m-%d %H:%M:%S.%5N');
}

# Date parsing

sub parse_date
{
  return $_[1]  if($_[0]->validate_date_keyword($_[1]));

  my $dt = Rose::DateTime::Util::parse_date($_[1]);

  if($@)
  {
    $_[0]->error("Could not parse date '$_[1]' - $@");
    return undef;
  }

  return $dt;
}

sub parse_datetime
{
  return $_[1]  if($_[0]->validate_datetime_keyword($_[1]));

  my $dt = Rose::DateTime::Util::parse_date($_[1]);

  if($@)
  {
    $_[0]->error("Could not parse datetime '$_[1]' - $@");
    return undef;
  }

  return $dt;
}

sub parse_datetime_year_to_second
{
  return $_[1]  if($_[0]->validate_datetime_keyword($_[1]));

  my $dt = Rose::DateTime::Util::parse_date($_[1]);

  if($@)
  {
    $_[0]->error("Could not parse datetime year to second '$_[1]' - $@");
    return undef;
  }

  $dt->truncate(to => 'second')  if(ref $dt);
  return $dt;
}

sub parse_datetime_year_to_minute
{
  return $_[1]  if($_[0]->validate_datetime_keyword($_[1]));

  my $dt = Rose::DateTime::Util::parse_date($_[1]);


  if($@)
  {
    $_[0]->error("Could not parse datetime year to minute '$_[1]' - $@");
    return undef;
  }

  $dt->truncate(to => 'minute')  if(ref $dt);
  return $dt;
}

sub parse_timestamp
{
  return $_[1]  if($_[0]->validate_timestamp_keyword($_[1]));

  my $dt = Rose::DateTime::Util::parse_date($_[1]);

  if($@)
  {
    $_[0]->error("Could not parse timestamp '$_[1]' - $@");
    return undef;
  }

  return $dt;
}

sub validate_date_keyword
{
  no warnings;
  $_[1] =~ /^(?:current|\w+\(.*\))$/i;
}

sub validate_time_keyword
{
  no warnings;
  $_[1] =~ /^(?:current|\w+\(.*\))$/i;
}

sub validate_timestamp_keyword
{
  no warnings;
  $_[1] =~ /^(?:current(?: +year +to +(?:fraction(?:\([1-5]\))?|second|minute|hour|day|month))?|\w+\(.*\))$/i;
}

sub validate_datetime_keyword
{
  no warnings;
  $_[1] =~ /^(?:current(?: +year +to +(?:second|minute|hour|day|month))?|\w+\(.*\))$/i;
}

sub validate_datetime_year_to_second_keyword
{
  no warnings;
  $_[1] =~ /^(?:current(?: +year +to +(?:second|minute|hour|day|month))?|\w+\(.*\))$/i;
}

sub validate_datetime_year_to_minute_keyword
{
  no warnings;
  $_[1] =~ /^(?:current(?: +year +to +(?:minute|hour|day|month))?|\w+\(.*\))$/i;
}

sub parse_set
{
  my($self) = shift;

  return $_[0]  if(ref $_[0]);
  return [ @_ ] if(@_ > 1);

  my $val = $_[0];

  return undef  unless(defined $val);

  $val =~ s/^SET\{(.*)\}$/$1/;

  my @set;

  while($val =~ s/(?:'((?:[^'\\]+|\\.)*)'|([^',]+))(?:,|$)//)
  {
    push(@set, (defined $1) ? $1 : $2);
  }

  return \@set;
}

sub format_set
{
  my($self) = shift;

  my @set = (ref $_[0]) ? @{$_[0]} : @_;

  return undef  unless(@set && defined $set[0]);

  return 'SET{' . join(',', map 
  {
    if(!defined $_)
    {
      Carp::croak 'Undefined value found in array or list passed to ',
                  __PACKAGE__, '::format_set()';
    }
    elsif(/^[-+]?\d+(?:\.\d*)?$/)
    {
      $_
    }
    else
    {
      s/\\/\\\\/g; 
      s/'/\\'/g;
      qq('$_') 
    }
  } @set) . '}';
}

sub parse_array
{
  my($self) = shift;

  return $_[0]  if(ref $_[0]);
  return [ @_ ] if(@_ > 1);

  my $val = $_[0];

  return undef  unless(defined $val);

  $val =~ s/^\{(.*)\}$/$1/;

  my @array;

  while($val =~ s/(?:"((?:[^"\\]+|\\.)*)"|([^",]+))(?:,|$)//)
  {
    push(@array, (defined $1) ? $1 : $2);
  }

  return \@array;
}

sub format_array
{
  my($self) = shift;

  my @array = (ref $_[0]) ? @{$_[0]} : @_;

  return undef  unless(@array && defined $array[0]);

  my $str = '{' . join(',', map 
  {
    if(!defined $_)
    {
      Carp::croak 'Undefined value found in array or list passed to ',
                  __PACKAGE__, '::format_array()';
    }
    elsif(/^[-+]?\d+(?:\.\d*)?$/)
    {
      $_
    }
    else
    {
      s/\\/\\\\/g; 
      s/"/\\"/g;
      qq("$_") 
    }
  } @array) . '}';

  if(length($str) > $self->max_array_characters)
  {
    Carp::croak "Array string is longer than ", ref($self), 
                "->max_array_characters (", $self->max_array_characters,
                ") characters long: $str";
  }

  return $str;
}

sub next_value_in_sequence
{
  my($self, $seq) = @_;

  my $dbh = $self->dbh or return undef;

  my $id;

  eval
  {
    my $sth = $dbh->prepare(qq(SELECT nextval('$seq')));
    $sth->execute;
    $id = ${$sth->fetchrow_arrayref}[0];
  };

  if($@)
  {
    $self->error("Could not get the next value in the sequence '$seq' - $@");
    return undef;
  }

  return $id;
}

1;

__END__

=head1 NAME

Rose::DB::Informix - Informix driver class for Rose::DB.

=head1 SYNOPSIS

  use Rose::DB;

  Rose::DB->register_db(
    domain   => 'development',
    type     => 'main',
    driver   => 'Informix',
    database => 'dev_db',
    host     => 'localhost',
    username => 'devuser',
    password => 'mysecret',
    server_time_zone => 'UTC',
  );


  Rose::DB->default_domain('development');
  Rose::DB->default_type('main');
  ...

  # Set max length of varchar columns used to emulate an array data type
  Rose::DB::Informix->max_array_characters(128);

  $db = Rose::DB->new; # $db is really a Rose::DB::Informix object

  $dt  = $db->parse_datetime_year_to_minute(...);
  $val = $db->format_datetime_year_to_minute($dt);

  $dt  = $db->parse_datetime_year_to_second(...);
  $val = $db->format_datetime_year_to_second($dt);
  ...

=head1 DESCRIPTION

This is the subclass that L<Rose::DB> blesses an object into when the C<driver> is "Informix".  This mapping of drivers to class names is configurable.  See the documentation for L<Rose::DB>'s C<new()> and C<driver_class()> methods for more information.

Using this class directly is not recommended.  Instead, use L<Rose::DB> and let it bless objects into the appropriate class for you, according to its C<driver_class()> mappings.

This class inherits from L<Rose::DB>.  B<Only the methods that are new or have  different behaviors are documented here.>  See the L<Rose::DB> documentation for information on the inherited methods.

=head1 CLASS METHODS

=over 4

=item B<max_array_characters [INT]>

Get or set the maximum length of varchar columns used to emulate an array data type.  The default value is 255.

Informix does not have a native "ARRAY" data type, but it can be emulated using a "VARCHAR" column and a specially formatted string.  The formatting and parsing of this string is handled by the C<format_array()> and C<parse_array()> object methods.  The maximum length limit is honored by the C<format_array()> object method.

Informix does have a native "SET" data type, serviced by the C<parse_set()> and C<format_set()> object methods.  This is a better choice than the emulated array data type if you don't care about the order of the stored values.

=back

=head1 OBJECT METHODS

=head2 Value Parsing and Formatting

=over 4

=item B<format_array ARRAYREF | LIST>

Given a reference to an array or a list of values, return a specially formatted string.  Undef is returned if ARRAYREF points to an empty array or if LIST is not passed.  The array or list must not contain undefined values.

If the resulting string is longer than C<max_array_characters()>, a fatal error will occur.

=item B<format_date DATETIME>

Converts the C<DateTime> object DATETIME into the appropriate format for the "DATE" data type.

=item B<format_datetime DATETIME>

Converts the C<DateTime> object DATETIME into the appropriate format for the "DATETIME YEAR TO SECOND" data type.

=item B<format_datetime_year_to_minute DATETIME>

Converts the C<DateTime> object DATETIME into the appropriate format for the "DATETIME YEAR TO MINUTE" data type.

=item B<format_datetime_year_to_second DATETIME>

Converts the C<DateTime> object DATETIME into the appropriate format for the "DATETIME YEAR TO SECOND" data type.

=item B<format_set ARRAYREF | LIST>

Given a reference to an array or a list of values, return a string formatted according to the rules of Informix's "SET" data type.  Undef is returned if ARRAYREF points to an empty array or if LIST is not passed.  If th array or list  contains undefined values, a fatal error will occur.

=item B<format_timestamp DATETIME>

Converts the C<DateTime> object DATETIME into the appropriate format for the "DATETIME YEAR TO FRACTION(5)" data type.

=item B<parse_array STRING | LIST | ARRAYREF>

Parse STRING and return a reference to an array.  STRING should be formatted according to the Informix array data type emulation format returned by C<format_array()>.  Undef is returned if STRING is undefined.

If a LIST of more than one item is passed, a reference to an array containing the values in LIST is returned.

If a an ARRAYREF is passed, it is returned as-is.

=item B<parse_boolean STRING>

Parse STRING and return a boolean value of 1 or 0.  STRING should be formatted according to Informix's native "boolean" data type.  Acceptable values are 't', 'T', or '1' for true, and 'f', 'F', or '0' for false.

If STRING is a valid boolean keyword (according to C<validate_boolean_keyword()>) or if it looks like a function call (matches /^\w+\(.*\)$/) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "boolean" value.

=item B<parse_datetime STRING>

Parse STRING and return a C<DateTime> object.  STRING should be formatted according to the Informix "DATETIME YEAR TO SECOND" data type.

If STRING is a valid "datetime year to second" keyword (according to C<validate_datetime_year_to_second_keyword()>) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "DATETIME YEAR TO SECOND" value.

=item B<parse_datetime_year_to_minute STRING>

Parse STRING and return a C<DateTime> object.  STRING should be formatted according to the Informix "DATETIME YEAR TO MINUTE" data type.

If STRING is a valid "datetime year to minute" keyword (according to C<validate_datetime_year_to_minute_keyword()>) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "DATETIME YEAR TO MINUTE" value.

=item B<parse_datetime_year_to_second STRING>

Parse STRING and return a C<DateTime> object.  STRING should be formatted according to the Informix "DATETIME YEAR TO SECOND" data type.

If STRING is a valid "datetime year to second" keyword (according to C<validate_datetime_year_to_second_keyword()>) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "DATETIME YEAR TO SECOND" value.

=item B<parse_set STRING | LIST | ARRAYREF>

Parse STRING and return a reference to an array.  STRING should be formatted according to Informix's "SET" data type.  Undef is returned if STRING is undefined.

If a LIST of more than one item is passed, a reference to an array containing the values in LIST is returned.

If a an ARRAYREF is passed, it is returned as-is.

=item B<parse_timestamp STRING>

Parse STRING and return a C<DateTime> object.  STRING should be formatted according to the Informix "DATETIME YEAR TO FRACTION(5)" data type.

If STRING is a valid timestamp keyword (according to C<validate_timestamp_keyword()>) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "DATETIME YEAR TO FRACTION(5)" value.

=item B<validate_date_keyword STRING>

Returns true if STRING is a valid keyword for the Informix "date", false otherwise.   Valid date keywords are:

    current

The keywords are not case sensitive.  Any string that looks like a function call (matches /^\w+\(.*\)$/) is also considered a valid date keyword.

=item B<validate_datetime_keyword STRING>

Returns true if STRING is a valid keyword for the Informix "datetime year to second" data type, false otherwise.  Valid datetime keywords are:

    current
    current year to second
    current year to minute
    current year to hour
    current year to day
    current year to month

The keywords are not case sensitive.  Any string that looks like a function call (matches /^\w+\(.*\)$/) is also considered a valid datetime keyword.

=item B<validate_datetime_year_to_minute_keyword STRING>

Returns true if STRING is a valid keyword for the Informix "datetime year to minute" data type, false otherwise.  Valid "datetime year to minute" keywords are:

    current
    current year to minute
    current year to hour
    current year to day
    current year to month

The keywords are not case sensitive.  Any string that looks like a function call (matches /^\w+\(.*\)$/) is also considered a valid "datetime year to minute" keyword.

=item B<validate_datetime_year_to_second_keyword STRING>

Returns true if STRING is a valid keyword for the Informix "datetime year to second" data type, false otherwise.  Valid datetime keywords are:

    current
    current year to second
    current year to minute
    current year to hour
    current year to day
    current year to month

The keywords are not case sensitive.  Any string that looks like a function call (matches /^\w+\(.*\)$/) is also considered a valid "datetime year to second" keyword.

=item B<validate_timestamp_keyword STRING>

Returns true if STRING is a valid keyword for the Informix "timestamp" data type, false otherwise.  Valid timestamp keywords are:

    current
    current year to fraction
    current year to fraction(1)
    current year to fraction(2)
    current year to fraction(3)
    current year to fraction(4)
    current year to fraction(5)
    current year to second
    current year to minute
    current year to hour
    current year to day
    current year to month

The keywords are not case sensitive.  Any string that looks like a function call (matches /^\w+\(.*\)$/) is also considered a valid timestamp keyword.

=back

=head1 AUTHOR

John C. Siracusa (siracusa@mindspring.com)

=head1 COPYRIGHT

Copyright (c) 2005 by John C. Siracusa.  All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the same terms
as Perl itself.
