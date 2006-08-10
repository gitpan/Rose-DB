package Rose::DB::SQLite;

use strict;

use Carp();

use Rose::DB;
use SQL::ReservedWords::SQLite();

our $VERSION = '0.70';

#our $Debug = 0;

#
# Object methods
#

sub build_dsn
{
  my($self_or_class, %args) = @_;

  my %info;

  $info{'dbname'} = $args{'db'} || $args{'database'};

  return
    "dbi:SQLite:" . 
    join(';', map { "$_=$info{$_}" } grep { defined $info{$_} } qw(dbname));
}

sub dbi_driver { 'SQLite' }

sub init_dbh
{
  my($self) = shift;

  my $database = $self->database;

  unless($self->auto_create || -e $database)
  {
    Carp::croak "Refusing to create non-existent SQLite database ",
                "file: '$database'";
  }

  $self->Rose::DB::init_dbh(@_);
}

sub last_insertid_from_sth { shift->dbh->func('last_insert_rowid') }

sub validate_date_keyword
{
  no warnings;
  !ref $_[1] && $_[1] =~ /^\w+\(.*\)$/;
}

sub validate_datetime_keyword
{
  no warnings;
  !ref $_[1] && $_[1] =~ /^\w+\(.*\)$/;
}

sub validate_timestamp_keyword
{
  no warnings;
  !ref $_[1] && $_[1] =~ /^\w+\(.*\)$/;
}

sub format_bitfield 
{
  my($self, $vec, $size) = @_;
  $vec = Bit::Vector->new_Bin($size, $vec->to_Bin)  if($size);
  return q(b') . $vec->to_Bin . q(');
}

sub refine_dbi_column_info
{
  my($self, $col_info) = @_;

  $self->Rose::DB::refine_dbi_column_info($col_info);

  if($col_info->{'TYPE_NAME'} eq 'bit')
  {
    $col_info->{'TYPE_NAME'} = 'bits';
  }

  return;
}

*is_reserved_word = \&SQL::ReservedWords::SQLite::is_reserved;

sub quote_column_name 
{
  my $name = $_[1];
  $name =~ s/"/""/g;
  return qq("$name");
}

sub quote_table_name
{
  my $name = $_[1];
  $name =~ s/"/""/g;
  return qq("$name");
}

#
# Introspection
#

sub list_tables
{
  my($self, %args) = @_;

  my $types = $args{'include_views'} ? q('table', 'view') : q('table');

  my @tables;

  eval
  {
    my $dbh = $self->dbh or die $self->error;

    local $dbh->{'RaiseError'} = 1;

    my $sth = $dbh->prepare("SELECT name FROM sqlite_master WHERE type IN($types)");
    $sth->execute;

    my $name;
    $sth->bind_columns(\$name);

    while($sth->fetch)
    {
      push(@tables, $name);
    }
  };

  if($@)
  {
    Carp::croak "Could not list tables from ", $self->dsn, " - $@";
  }

  return wantarray ? @tables : \@tables;
}

sub _get_primary_key_column_names
{
  my($self, $catalog, $schema, $table) = @_;
  my $pk_columns = ($self->_table_info($table))[1] || [];
  return $pk_columns;
}

sub _table_info
{
  my($self, $table) = @_;

  my $dbh = $self->dbh or Carp::croak $self->error;

  my $table_unquoted = $self->unquote_table_name($table);

  my $sth = $dbh->prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?");
  my $sql;

  $sth->execute($table_unquoted);
  $sth->bind_columns(\$sql);
  $sth->fetch;
  $sth->finish;

  return _info_from_sql($sql);
}

## Yay!  A Giant Wad o' Regexes "parser"!  Yeah, this is lame, but I really
## don't want to load an actual parser, or even a regex lib or helper...

our $Paren_Depth   = 15;
our $Nested_Parens = '\(' . '([^()]|\(' x $Paren_Depth . '[^()]*' . '\))*' x $Paren_Depth . '\)';

# This doesn't seem to work...
#$Nested_Parens = qr{\( (?: (?> [^()]+ ) | (??{ $Nested_Parens }) )* \)}x;

our $Quoted =   
  qr{(?: ' (?: [^'] | '' )+ '
     | " (?: [^"] | "" )+ "
     | ` (?: [^`] | `` )+ `)}six;

our $Name = qr{(?: $Quoted | \w+ )}six;

our $Type = 
  qr{\w+ (?: \s* \( \s* \d+ \s* (?: , \s* \d+ \s*)? \) )?}six;

our $Conflict_Algorithm = 
  qr{(?: ROLLBACK | ABORT | FAIL | IGNORE | REPLACE )}six;

our $Conflict_Clause =
  qr{(?: ON \s+ CONFLICT \s+ $Conflict_Algorithm )}six;

our $Sort_Order = 
  qr{(?: COLLATE \s+ \S+ \s+)? (?:ASC | DESC)}six;

our $Column_Constraint = 
  qr{(?: NOT \s+ NULL (?: \s+ $Conflict_Clause)?
     | PRIMARY \s+ KEY (?: \s+ $Sort_Order)? (?: \s+ $Conflict_Clause)? (?: \s+ AUTOINCREMENT)? 
     | UNIQUE (?: \s+ $Conflict_Clause)? 
     | CHECK \s* $Nested_Parens (?: \s+ $Conflict_Clause)?
     | REFERENCES \s+ $Name \s* \( \s* $Name \s* \)
     | DEFAULT \s+ (?: $Name | \w+ \s* $Nested_Parens | [^,)]+ )
     | COLLATE \s+ \S+)}six;

our $Table_Constraint =
  qr{(?: (?: PRIMARY \s+ KEY | UNIQUE | CHECK ) \s* $Nested_Parens 
     | FOREIGN \s+ KEY \s+ (?: $Name \s+ )? $Nested_Parens \s+ REFERENCES \s+ $Name \s+ $Nested_Parens )}six;

our $Column_Def =
  qr{($Name) (?:\s+ ($Type))? ( (?: \s+ (?:CONSTRAINT \s+ $Name \s+)? $Column_Constraint )* )}six;

# SQLite allows C comments to be unterminated if they're at the end of the 
# input stream.  Crazy, but true: http://www.sqlite.org/lang_comment.html
our $C_Comment_Cont = qr{/\*.*$}six;
our $C_Comment      = qr{/\*[^*]*\*+(?:[^/*][^*]*\*+)*/}six;
our $SQL_Comment    = qr{--[^\r\n]*(\r?\n)}six;
our $Comment        = qr{($Quoted)|($C_Comment|$SQL_Comment|$C_Comment_Cont)}six;

# These constants are from the DBI documentation.  Is there somewhere 
# I can load these from?
use constant SQL_NO_NULLS => 0;
use constant SQL_NULLABLE => 1;

sub _info_from_sql
{
  my $sql = shift;

  my(@col_info, @pk_columns, @uk_info);

  my($new_sql, $pos);

  # Remove comments
  while($sql =~ /\G((.*?)$Comment)/sgix)
  {
    $pos = pos($sql);

    if(defined $4) # caught comment
    {
      no warnings 'uninitialized';
      $new_sql .= "$2$3";
    }
    else
    {
      $new_sql .= $1;
    }
  }

  $sql = $new_sql . substr($sql, $pos) if(defined $new_sql);

  # Remove the start and end
  $sql =~ s/^\s* CREATE \s+ (?:TEMP(?:ORARY)? \s+)? TABLE \s+ $Name \s*\(\s*//sgix;
  $sql =~ s/\s*\)\s*$//six;

  # Remove leading space from lines
  $sql =~ s/^\s+//mg;

  my $i = 1;

  # Column definitions
  while($sql =~ s/^$Column_Def (?:\s*,\s*|\s*$)//six)
  {
    my $col_name    = $1;
    my $col_type    = $2 || 'scalar';
    my $constraints = $3;

    unless(defined $col_name)
    {
      Carp::croak "Could not extract column name from SQL: $sql";
    }

    my %col_info =
    (
      COLUMN_NAME      => $col_name,
      TYPE_NAME        => $col_type,
      ORDINAL_POSITION => $i++,
    );

    if($col_type =~ /^(\w+) \s* \( \s* (\d+) \s* \)$/x)
    {
      $col_info{'TYPE_NAME'}         = $1;
      $col_info{'COLUMN_SIZE'}       = $2;
      $col_info{'CHAR_OCTET_LENGTH'} = $2;
    }
    elsif($col_type =~ /^\s* (\w+) \s* \( \s* (\d+) \s* , \s* (\d+) \s* \) \s*$/x)
    {
      $col_info{'TYPE_NAME'}      = $1;
      $col_info{'DECIMAL_DIGITS'} = $2;
      $col_info{'COLUMN_SIZE'}    = $3;
    }

    while($constraints =~ s/^\s* (?:CONSTRAINT \s+ $Name \s+)? ($Column_Constraint) \s*//six)
    {
      local $_ = $1;

      if(/^DEFAULT \s+ ( $Name | \w+ \s* $Nested_Parens | [^,)]+ )/six)
      {
        $col_info{'COLUMN_DEF'} = _unquote_name($1);
      }
      elsif(/^PRIMARY (?: \s+ KEY )? \b/six)
      {
        push(@pk_columns, $col_name)
      }
      elsif(/^\s* UNIQUE (?: \s+ KEY)? \b/six)
      {
        push(@uk_info, [ _unquote_name($col_name) ]);
      }
      elsif(/^NOT \s+ NULL \b/six)
      {
        $col_info{'NULLABLE'} = SQL_NO_NULLS;
      }
    }

    $col_info{'NULLABLE'} = SQL_NULLABLE  unless(defined $col_info{'NULLABLE'});

    push(@col_info, \%col_info);
  }

  while($sql =~ s/^($Table_Constraint) (?:\s*,\s*|\s*$)//six)
  {
    my $constraint = $1;

    if($constraint =~ /^\s* PRIMARY \s+ KEY \s* ($Nested_Parens)/six)
    {
      @pk_columns = ();

      my $columns = $1;
      $columns =~ s/^\(\s*//;
      $columns =~ s/\s*\)\s*$//;

      while($columns =~ s/^\s* ($Name) (?:\s*,\s*|\s*$)//six)
      {
        push(@pk_columns, _unquote_name($1));
      }
    }
    elsif($constraint =~ /^\s* UNIQUE \s* ($Nested_Parens)/six)
    {
      my $columns = $1;
      $columns =~ s/^\(\s*//;
      $columns =~ s/\s*\)\s*$//;

      my @uk_columns;

      while($columns =~ s/^\s* ($Name) (?:\s*,\s*|\s*$)//six)
      {
        push(@uk_columns, _unquote_name($1));
      }

      push(@uk_info, \@uk_columns);
    }
  }

  return(\@col_info, \@pk_columns, \@uk_info);
}

sub _unquote_name
{
  my $name = shift;

  if($name =~ s/^(['`"]) ( (?: [^\1]+ | \1\1 )+ ) \1 $/$2/six)
  {
    my $q = $1;
    $name =~ s/$q$q/$q/g;
  }

  return $name;
}

1;

__END__

=head1 NAME

Rose::DB::SQLite - SQLite driver class for Rose::DB.

=head1 SYNOPSIS

  use Rose::DB;

  Rose::DB->register_db(
    domain   => 'development',
    type     => 'main',
    driver   => 'sqlite',
    database => '/path/to/some/file.db',
  );


  Rose::DB->default_domain('development');
  Rose::DB->default_type('main');
  ...

  # Set max length of varchar columns used to emulate the array data type
  Rose::DB::SQLite->max_array_characters(128);

  $db = Rose::DB->new; # $db is really a Rose::DB::SQLite-derived object
  ...

=head1 DESCRIPTION

L<Rose::DB> blesses objects into a class derived from L<Rose::DB::SQLite> when the L<driver|Rose::DB/driver> is "sqlite".  This mapping of driver names to class names is configurable.  See the documentation for L<Rose::DB>'s L<new()|Rose::DB/new> and L<driver_class()|Rose::DB/driver_class> methods for more information.

This class cannot be used directly.  You must use L<Rose::DB> and let its L<new()|Rose::DB/new> method return an object blessed into the appropriate class for you, according to its L<driver_class()|Rose::DB/driver_class> mappings.

This class supports SQLite version 3 only.  See the SQLite web site for more information on the major versions of SQLite:

L<http://www.sqlite.org/>

Only the methods that are new or have different behaviors than those in L<Rose::DB> are documented here.  See the L<Rose::DB> documentation for the full list of methods.

=head1 DATA TYPES

SQLite doesn't care what value you pass for a given column, regardless of that column's nominal data type.  L<Rose::DB> does care, however.  The following data type formats are enforced by L<Rose::DB::SQLite>'s L<parse_*|Rose::DB/"Value Parsing and Formatting"> and L<format_*|Rose::DB/"Value Parsing and Formatting"> functions.

    Type        Format
    ---------   ------------------------------
    DATE        YYYY-MM-DD
    DATETIME    YYYY-MM-DD HH:MM::SS
    TIMESTAMP   YYYY-MM-DD HH:MM::SS.NNNNNNNNN

=head1 CLASS METHODS

=over 4

=item B<max_array_characters [INT]>

Get or set the maximum length of varchar columns used to emulate the array data type.  The default value is 255.

SQLite does not have a native "ARRAY" data type, but it can be emulated using a "VARCHAR" column and a specially formatted string.  The formatting and parsing of this string is handled by the C<format_array()> and C<parse_array()> object methods.  The maximum length limit is honored by the C<format_array()> object method.

=back

=head1 OBJECT METHODS

=over 4

=item B<auto_create [BOOL]>

Get or set a boolean value indicating whether or not a new SQLite L<database|Rose::DB/database> should be created if it does not already exist.  Defaults to true.

If false, and if the specified L<database|Rose::DB/database> does not exist, then a fatal error will occur when an attempt is made to L<connect|Rose::DB/connect> to the database.

=back

=head2 Value Parsing and Formatting

=over 4

=item B<format_array ARRAYREF | LIST>

Given a reference to an array or a list of values, return a specially formatted string.  Undef is returned if ARRAYREF points to an empty array or if LIST is not passed.  The array or list must not contain undefined values.

If the resulting string is longer than C<max_array_characters()>, a fatal error will occur.

=item B<parse_array STRING | LIST | ARRAYREF>

Parse STRING and return a reference to an array.  STRING should be formatted according to the SQLite array data type emulation format returned by C<format_array()>.  Undef is returned if STRING is undefined.

If a LIST of more than one item is passed, a reference to an array containing the values in LIST is returned.

If a an ARRAYREF is passed, it is returned as-is.

=item B<validate_date_keyword STRING>

Returns true if STRING is a valid keyword for the "date" data type.  Any strings that looks like a function call (matches /^\w+\(.*\)$/) is considered a valid date keyword.

=item B<validate_datetime_keyword STRING>

Returns true if STRING is a valid keyword for the "datetime" data type, false otherwise.   Any strings that looks like a function call (matches /^\w+\(.*\)$/) is considered a valid datetime keyword.

=item B<validate_timestamp_keyword STRING>

Returns true if STRING is a valid keyword for the "timestamp" data type, false otherwise.  Any strings that looks like a function call (matches /^\w+\(.*\)$/) is considered a valid timestamp keyword.

=back

=head1 AUTHOR

John C. Siracusa (siracusa@mindspring.com)

=head1 COPYRIGHT

Copyright (c) 2006 by John C. Siracusa.  All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the same terms
as Perl itself.
