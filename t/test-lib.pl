#!/usr/bin/perl

use strict;

use Rose::DB;

BEGIN 
{  
  Rose::DB->default_domain('test');

  #
  # Postgres
  #

  # Main
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'pg',
    driver   => 'Pg',
    database => 'test',
    host     => 'localhost',
    username => 'postgres',
    password => '',
    post_connect_sql =>
    [
      'SET default_transaction_isolation TO "read committed"',
    ],
  );

  # Private schema
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'pg_with_schema',
    schema   => 'rose_db_object_private',
    driver   => 'Pg',
    database => 'test',
    host     => 'localhost',
    username => 'postgres',
    password => '',
    post_connect_sql =>
    [
      'SET default_transaction_isolation TO "read committed"',
    ],
  );

  # Admin
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'pg_admin',
    driver   => 'Pg',
    database => 'test',
    host     => 'localhost',
    username => 'postgres',
    password => '',
    post_connect_sql =>
    [
      'SET default_transaction_isolation TO "read committed"',
    ],
  );

  #
  # MySQL
  #

  # Main
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'mysql',
    driver   => 'mysql',
    database => 'test',
    host     => 'localhost',
    username => 'root',
    password => ''
  );

  # Admin
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'mysql_admin',
    driver   => 'mysql',
    database => 'test',
    host     => 'localhost',
    username => 'root',
    password => ''
  );

  #
  # Informix
  #

  # Main
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'informix',
    driver   => 'Informix',
    database => 'test@test',
    connect_options => { AutoCommit => 1 },
    post_connect_sql =>
    [
      'SET LOCK MODE TO WAIT 30',
      'SET ISOLATION TO DIRTY READ',
    ],
  );

  # Admin
  Rose::DB->register_db(
    domain   => 'test',
    type     => 'informix_admin',
    driver   => 'Informix',
    database => 'test@test',
    connect_options => { AutoCommit => 1 },
    post_connect_sql =>
    [
      'SET LOCK MODE TO WAIT 30',
      'SET ISOLATION TO DIRTY READ',
    ],
  );

  # Just test that the catalog attribute works.  No supported DBs use it.
  Rose::DB->register_db(
    domain   => 'catalog_test',
    type     => 'catalog_test',
    driver   => 'Pg',
    database => 'test',
    catalog  => 'somecatalog',
    schema   => 'someschema',
    host     => 'localhost',
    username => 'postgres',
    password => '',
  );

  my @types = qw(pg pg_with_schema pg_admin mysql mysql_admin informix informix_admin);

  unless($Rose::DB::Object::Test::NoDefaults)
  {
    foreach my $db_type (qw(PG MYSQL INFORMIX))
    {
      if(my $dsn = $ENV{"RDBO_${db_type}_DSN"})
      {
        foreach my $type (grep { /^$db_type(?:_|$)/i } @types)
        {
          Rose::DB->modify_db(domain => 'test', type => $type, dsn => $dsn);
        }
      }
      
      if(my $user = $ENV{"RDBO_${db_type}_USER"})
      {
        foreach my $type (grep { /^$db_type(?:_|$)/i } @types)
        {
          Rose::DB->modify_db(domain => 'test', type => $type, username => $user);
        }
      }

      if(my $user = $ENV{"RDBO_${db_type}_PASS"})
      {
        foreach my $type (grep { /^$db_type(?:_|$)/i } @types)
        {
          Rose::DB->modify_db(domain => 'test', type => $type, password => $user);
        }
      }
    }
  }
}

# Subclass testing
package My::DB;
@My::DB::ISA = qw(Rose::DB);

package My::DB2;
@My::DB2::ISA = qw(My::DB);

My::DB2->driver_class(Pg => 'My::DB2::Pg');
My::DB2->driver_class(mysql => 'My::DB2::MySQL');
My::DB2->driver_class(Informix => 'My::DB2::Informix');

package My::DB2::Pg;
@My::DB2::Pg::ISA = qw(Rose::DB::Pg);

sub subclass_special_pg { 'PG' }

package My::DB2::MySQL;
@My::DB2::MySQL::ISA = qw(Rose::DB::MySQL);

sub subclass_special_mysql { 'MYSQL' }

package My::DB2::Informix;
@My::DB2::Informix::ISA = qw(Rose::DB::Informix);

sub subclass_special_informix { 'INFORMIX' }

package My::DB3;
@My::DB3::ISA = qw(My::DB2);

our %Registry;

sub db_registry_hash { \%Registry }

1;
