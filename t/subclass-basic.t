#!/usr/bin/perl -w

use strict;

use Test::More tests => 36;

BEGIN 
{
  use_ok('Rose::DB');
  use_ok('Rose::DB::Constants');

  require 't/test-lib.pl';

  is(Rose::DB::Constants::IN_TRANSACTION(), -1, 'Rose::DB::Constants::IN_TRANSACTION');
  Rose::DB::Constants->import('IN_TRANSACTION');

  # Default
  My::DB2->register_db(
    domain   => 'default',
    type     => 'default',
    driver   => 'Pg',
    database => 'test',
    host     => 'localhost',
    username => 'postgres',
    password => '',
  );

  # Main
  My::DB2->register_db(
    domain   => 'test',
    type     => 'default',
    driver   => 'Pg',
    database => 'test',
    host     => 'localhost',
    username => 'postgres',
    password => '',
  );

  # Aux
  My::DB2->register_db(
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

my $db = My::DB2->new;

is(My::DB2->default_domain, 'test', 'default_domain() 1');
is(My::DB2->default_type, 'default', 'default_type() 1');

My::DB2->error('foo');

is(My::DB2->error, 'foo', 'error() 2');

$db->error('bar');

is(My::DB2->error, 'bar', 'error() 3');
is($db->error, 'bar', 'error() 4');

eval { $db = My::DB2->new };
ok(!$@, 'Valid type and domain');
  
My::DB2->default_domain('foo');

is(My::DB2->default_domain, 'foo', 'default_domain() 2');

eval { $db = My::DB2->new };
ok($@, 'Invalid domain');

My::DB2->default_domain('test');
My::DB2->default_type('bar');

is(My::DB2->default_type, 'bar', 'default_type() 2');

eval { $db = My::DB2->new };
ok($@, 'Invalid type');

is(Rose::DB->driver_class('Pg'), 'Rose::DB::Pg', 'driver_class() 1');
is(My::DB2->driver_class('xxx'), undef, 'driver_class() 2');

My::DB2->driver_class(Pg => 'MyPgClass');
is(My::DB2->driver_class('Pg'), 'MyPgClass', 'driver_class() 3');

$db = My::DB2->new('aux');

is(ref $db, 'MyPgClass', 'new() single arg');

is($db->error('foo'), 'foo', 'subclass 1');
is($db->error, 'foo', 'subclass 2');

eval { $db->format_date('123') };
ok($@ =~ /^boo!/, 'driver_class() 4');

is(My::DB2->default_connect_option('AutoCommit'), 1, "default_connect_option('AutoCommit')");
is(My::DB2->default_connect_option('RaiseError'), 1, "default_connect_option('RaiseError')");
is(My::DB2->default_connect_option('PrintError'), 1, "default_connect_option('PrintError')");
is(My::DB2->default_connect_option('ChopBlanks'), 1, "default_connect_option('ChopBlanks')");
is(My::DB2->default_connect_option('Warn'), 0, "default_connect_option('Warn')");

my $options = My::DB2->default_connect_options;

is(ref $options, 'HASH', 'default_connect_options() 1');
is(join(',', sort keys %$options), 'AutoCommit,ChopBlanks,PrintError,RaiseError,Warn',
  'default_connect_options() 2');

My::DB2->default_connect_options(a => 1, b => 2);

is(My::DB2->default_connect_option('a'), 1, "default_connect_option('a')");
is(My::DB2->default_connect_option('b'), 2, "default_connect_option('b')");

My::DB2->default_connect_options({ c => 3, d => 4 });

is(My::DB2->default_connect_option('c'), 3, "default_connect_option('c') 1");
is(My::DB2->default_connect_option('d'), 4, "default_connect_option('d') 1");

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
