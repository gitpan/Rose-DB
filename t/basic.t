#!/usr/bin/perl -w

use strict;

use Test::More tests => 40;

BEGIN 
{
  use_ok('Rose::DB');
  use_ok('Rose::DB::Constants');

  require 't/test-lib.pl';

  is(Rose::DB::Constants::IN_TRANSACTION(), -1, 'Rose::DB::Constants::IN_TRANSACTION');
  Rose::DB::Constants->import('IN_TRANSACTION');

  # Default
  Rose::DB->register_db(
    domain   => 'default',
    type     => 'default',
    driver   => 'Pg',
    database => 'test',
    host     => 'localhost',
    username => 'postgres',
    password => '',
  );

  # Main
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'default',
    driver   => 'Pg',
    database => 'test',
    host     => 'localhost',
    username => 'postgres',
    password => '',
  );

  # Aux
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'aux',
    driver   => 'Pg',
    database => 'test',
    host     => 'localhost',
    username => 'postgres',
    password => '',
  );

  package MyPgClass;
  @MyPgClass::ISA = qw(Rose::DB::Pg);
  sub format_date { die "boo!" }
}

is(IN_TRANSACTION, -1, 'IN_TRANSACTION');

my $db = Rose::DB->new;

is(Rose::DB->default_domain, 'test', 'default_domain() 1');
is(Rose::DB->default_type, 'default', 'default_type() 1');

Rose::DB->error('foo');

is(Rose::DB->error, 'foo', 'error() 2');

$db->error('bar');

is(Rose::DB->error, 'bar', 'error() 3');
is($db->error, 'bar', 'error() 4');

eval { $db = Rose::DB->new };
ok(!$@, 'Valid type and domain');
  
Rose::DB->default_domain('foo');

is(Rose::DB->default_domain, 'foo', 'default_domain() 2');

eval { $db = Rose::DB->new };
ok($@, 'Invalid domain');

Rose::DB->default_domain('test');
Rose::DB->default_type('bar');

is(Rose::DB->default_type, 'bar', 'default_type() 2');

eval { $db = Rose::DB->new };
ok($@, 'Invalid type');

is(Rose::DB->driver_class('Pg'), 'Rose::DB::Pg', 'driver_class() 1');
is(Rose::DB->driver_class('xxx'), undef, 'driver_class() 2');

Rose::DB->driver_class(Pg => 'MyPgClass');
is(Rose::DB->driver_class('Pg'), 'MyPgClass', 'driver_class() 3');

$db = Rose::DB->new('aux');

is(ref $db, 'MyPgClass', 'new() single arg');

is($db->error('foo'), 'foo', 'subclass 1');
is($db->error, 'foo', 'subclass 2');

eval { $db->format_date('123') };
ok($@ =~ /^boo!/, 'driver_class() 4');

is(Rose::DB->default_connect_option('AutoCommit'), 1, "default_connect_option('AutoCommit')");
is(Rose::DB->default_connect_option('RaiseError'), 1, "default_connect_option('RaiseError')");
is(Rose::DB->default_connect_option('PrintError'), 1, "default_connect_option('PrintError')");
is(Rose::DB->default_connect_option('ChopBlanks'), 1, "default_connect_option('ChopBlanks')");
is(Rose::DB->default_connect_option('Warn'), 0, "default_connect_option('Warn')");

my $options = Rose::DB->default_connect_options;

is(ref $options, 'HASH', 'default_connect_options() 1');
is(join(',', sort keys %$options), 'AutoCommit,ChopBlanks,PrintError,RaiseError,Warn',
  'default_connect_options() 2');

Rose::DB->default_connect_options(a => 1, b => 2);

is(Rose::DB->default_connect_option('a'), 1, "default_connect_option('a')");
is(Rose::DB->default_connect_option('b'), 2, "default_connect_option('b')");

Rose::DB->default_connect_options({ c => 3, d => 4 });

is(Rose::DB->default_connect_option('c'), 3, "default_connect_option('c') 1");
is(Rose::DB->default_connect_option('d'), 4, "default_connect_option('d') 1");

my $keys = join(',', sort keys %{$db->default_connect_options});

$db->default_connect_options(zzz => 'bar');

my $keys2 = join(',', sort keys %{$db->default_connect_options});

is($keys2, "$keys,zzz", 'default_connect_options() 1');

$db->default_connect_options({ zzz => 'bar' });

$keys2 = join(',', sort keys %{$db->default_connect_options});

is($keys2, 'zzz', 'default_connect_options() 2');

$keys = join(',', sort keys %{$db->connect_options});

$db->connect_options(zzzz => 'bar');

$keys2 = join(',', sort keys %{$db->connect_options});

is($keys2, "$keys,zzzz", 'connect_option() 1');

$db->connect_options({ zzzz => 'bar' });

$keys2 = join(',', sort keys %{$db->connect_options});

is($keys2, 'zzzz', 'connect_option() 2');

$db->dsn('dbi:Pg:dbname=dbfoo;host=hfoo;port=pfoo');

ok(!defined($db->database) || $db->database eq 'dbfoo', 'dsn() 1');
ok(!defined($db->host) || $db->host eq 'hfoo', 'dsn() 2');
ok(!defined($db->port) || $db->port eq 'port', 'dsn() 3');

eval { $db->dsn('dbi:mysql:dbname=dbfoo;host=hfoo;port=pfoo') };

ok($@, 'dsn() driver change');
