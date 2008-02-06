#!/usr/bin/perl -w

use strict;

use Rose::DateTime::Util qw(parse_date);

BEGIN
{
  require Test::More;
  eval { require DBD::Oracle };

  if($@)
  {
    Test::More->import(skip_all => 'Missing DBD::Oracle');
  }
  else
  {
    Test::More->import(tests => 55);
  }
}

BEGIN
{
  require 't/test-lib.pl';
  use_ok('Rose::DB');
}

My::DB2->default_domain('test');
My::DB2->default_type('oracle');

# Note: $db here is of type Rose::DB::Oracle.

my $db = My::DB2->new();

ok(ref $db && $db->isa('Rose::DB'), 'new()');

is($db->parse_boolean('t'), 1, 'parse_boolean (t)');
is($db->parse_boolean('true'), 1, 'parse_boolean (true)');
is($db->parse_boolean('y'), 1, 'parse_boolean (y)');
is($db->parse_boolean('yes'), 1, 'parse_boolean (yes)');
is($db->parse_boolean('1'), 1, 'parse_boolean (1)');
is($db->parse_boolean('TRUE'), 'TRUE', 'parse_boolean (TRUE)');

is($db->parse_boolean('f'), 0, 'parse_boolean (f)');
is($db->parse_boolean('false'), 0, 'parse_boolean (false)');
is($db->parse_boolean('n'), 0, 'parse_boolean (n)');
is($db->parse_boolean('no'), 0, 'parse_boolean (no)');
is($db->parse_boolean('0'), 0, 'parse_boolean (0)');
is($db->parse_boolean('FALSE'), 'FALSE', 'parse_boolean (FALSE)');

is($db->parse_boolean('Foo(Bar)'), 'Foo(Bar)', 'parse_boolean (Foo(Bar))');

foreach my $val (qw(t 1 true True T y Y yes Yes))
{
  is($db->format_boolean($db->parse_boolean($val)), 't', "format_boolean ($val)");
}

foreach my $val (qw(f 0 false False F n N no No))
{
  is($db->format_boolean($db->parse_boolean($val)), 'f', "format_boolean ($val)");
}

my $dbh;
eval { $dbh = $db->dbh };

SKIP:
{
  skip("Could not connect to db - $@", 9)  if($@);

  ok($dbh, 'dbh() 1');

  ok($db->has_dbh, 'has_dbh() 1');

  my $db2 = My::DB2->new();

  $db2->dbh($dbh);

  foreach my $field (qw(dsn driver database host port username password))
  {
    is($db2->$field(), $db->$field(), "$field()");
  }

  $db->disconnect;
  $db2->disconnect;
}

$db = My::DB2->new();

ok(ref $db && $db->isa('Rose::DB'), "new()");

$db->init_db_info;

My::DB2->register_db
(
  domain => 'stub',
  type   => 'default',
  driver => 'oracle',
);

$db = My::DB2->new
(
  domain => 'stub',
  type   => 'default',
  dsn    => "dbi:Oracle:mydb",
);
  
is($db->database, 'mydb', 'parse_dsn() 1');

SKIP:
{
  $db = My::DB2->new;

  eval { $db->connect };
  skip("Could not connect to db 'test', 'oracle' - $@", 11)  if($@);
  $dbh = $db->dbh;

  is($db->domain, 'test', "domain()");
  is($db->type, 'oracle', "type()");

  is($db->print_error, $dbh->{'PrintError'}, 'print_error() 2');
  is($db->print_error, $db->connect_option('PrintError'), 'print_error() 3');

  is($db->null_date, '0000-00-00', "null_date()");
  is($db->null_datetime, '0000-00-00 00:00:00', "null_datetime()");

  #is($db->autocommit + 0, $dbh->{'AutoCommit'} + 0, 'autocommit() 1');

  $db->autocommit(1);

  is($db->autocommit + 0, 1, 'autocommit() 2');
  is($dbh->{'AutoCommit'} + 0, 1, 'autocommit() 3');

  $db->autocommit(0);

  is($db->autocommit + 0, 0, 'autocommit() 4');
  is($dbh->{'AutoCommit'} + 0, 0, 'autocommit() 5');

  is($db->auto_sequence_name(table => 'foo', column => 'bar'), 'foo_bar_seq', 'auto_sequence_name()');

  my $dbh_copy = $db->retain_dbh;

  $db->disconnect;
}

sub lookup_ip
{
  my($name) = shift || return 0;

  my $address = (gethostbyname($name))[4] or return 0;

  my @octets = unpack("CCCC", $address);

  return 0  unless($name && @octets);
  return join('.', @octets), "\n";
}