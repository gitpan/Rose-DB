package Rose::DB;

use strict;

use DBI;
use Carp();
use Bit::Vector::Overload;

use Rose::DateTime::Util();

use Rose::Object;
our @ISA = qw(Rose::Object);

our $Error;

our $VERSION = '0.013';

our $Debug = 0;

#
# Object data
#

use Rose::Object::MakeMethods::Generic
(
  'scalar' =>
  [
    qw(database schema host port username password european_dates
       _dbh_refcount _origin_class)
  ],

  'boolean' =>
  [
    '_dbh_is_private',
  ],

  'scalar --get_set_init' =>
  [
    'domain',
    'type',
    'date_handler',
    'server_time_zone'
  ],

  'array' => 
  [
    'post_connect_sql',
    'pre_disconnect_sql',
  ],

  'hash' =>
  [
    connect_options => { interface => 'get_set_init' },
  ]
);

use Rose::Class::MakeMethods::Generic
(
  inheritable_scalar =>
  [
    'default_domain',
    'default_type',
  ]
);

use Rose::Class::MakeMethods::Generic
(
  inheritable_hash =>
  [
    driver_classes      => { interface => 'get_set_all' },
    driver_class        => { interface => 'get_set', hash_key => 'driver_classes' },
    delete_driver_class => { interface => 'delete', hash_key => 'driver_classes' },

    default_connect_options => { interface => 'get_set_all',  },
    default_connect_option  => { interface => 'get_set', hash_key => 'default_connect_options' },
    delete_connect_option   => { interface => 'delete', hash_key => 'default_connect_options' },
  ],
);

__PACKAGE__->default_domain('default');
__PACKAGE__->default_type('default');

__PACKAGE__->driver_classes
(
  mysql    => 'Rose::DB::MySQL',
  Pg       => 'Rose::DB::Pg',
  Informix => 'Rose::DB::Informix',
);

__PACKAGE__->default_connect_options
(
  AutoCommit => 1,
  RaiseError => 1,
  PrintError => 1,
  ChopBlanks => 1,
  Warn       => 0,
);

LOAD_SUBCLASSES:
{
  my %seen;

  my $map = __PACKAGE__->driver_classes;

  foreach my $class (values %$map)
  {
    eval qq(require $class)  unless($seen{$class}++);
    die "Could not load $class - $@"  if($@);
  }
}

#
# Class methods
#

our %Registry;

# Override this method in a sublcass to get a privatre registry.  This
# feature is UNDOCUMENTED and UNSUPPORTED!  Use at your own risk...

sub db_registry_hash { \%Registry }

# Can't do this because drivers are subclasses too...
# {
#   my($class) = shift;
# 
#   unless($Registry{$class})
#   {
#     no strict 'refs';
#     foreach my $subclass (@{$class . '::ISA'})
#     {
#       if(ref $Registry{$subclass} eq 'HASH')
#       {
#         foreach my $domain (keys %{$Registry{$subclass}})
#         {
#           $Registry{$class}{$domain} = {};
# 
#           foreach my $type (keys %{$Registry{$subclass}{$domain} ||= {}})
#           {
#             my %info;
# 
#             # Manually do a two-level copy (avoiding using Clone::Any
#             # and friend for now)
#             while(my($k, $v) = each(%{$Registry{$subclass}}))
#             {
#               if(!ref $v)
#               {
#                 $info{$k} = $v;
#               }
#               elsif(ref $v eq 'ARRAY')
#               {
#                 $info{$k} = [ @$v ];
#               }
#               elsif(ref $v eq 'HASH')
#               {
#                 $info{$k} = { %$v };
#               }
#               else
#               {
#                 Carp::croak "Encountered unexpected reference value in subclass ",
#                             "data source registry: $subclass - $v";
#               }
#             }
#             
#             $Registry{$class}{$domain}{$type} = \%info;
#           }
#         }
#         last;
#       }
#     }
#   }
# 
#   return $Registry{$class} ||= {};
# }

sub register_db
{
  my($class, %args) = @_;

  my $domain = delete $args{'domain'} or Carp::croak "Missing domain";
  my $type   = delete $args{'type'} or Carp::croak "Missing type";
  exists $args{'driver'} or Carp::croak "Missing driver";

  my $registry = $class->db_registry_hash;

  $registry->{$domain}{$type} = \%args;
}

sub unregister_db
{
  my($class, %args) = @_;

  my $domain = $args{'domain'} or Carp::croak "Missing domain";
  my $type   = $args{'type'} or Carp::croak "Missing type";

  my $registry = $class->db_registry_hash;

  $registry->{$domain}{$type} = \%args;

  delete $registry->{$domain}{$type};
}

sub modify_db
{
  my($class, %args) = @_;

  my $domain = delete $args{'domain'} or Carp::croak "Missing domain";
  my $type   = delete $args{'type'} or Carp::croak "Missing type";

  my $registry = $class->db_registry_hash;

  Carp::croak "No db defined for domain '$domain' and type '$type'"
    unless(exists $registry->{$domain} && exists $registry->{$domain}{$type});

  @{$registry->{$domain}{$type}}{keys %args} = values %args;
}

sub unregister_domain
{
  my($class, $domain) = @_;
  my $registry = $class->db_registry_hash;
  delete $registry->{$domain};
}

#
# Object methods
#

sub new
{
  my($class) = shift;

  @_ = (type => $_[0])  if(@_ == 1);

  my %args = @_;

  my $domain = 
    exists $args{'domain'} ? $args{'domain'} : $class->default_domain;

  my $type = 
    exists $args{'type'} ? $args{'type'} : $class->default_type;

  my $db_info;

  my $registry = $class->db_registry_hash;

  if(exists $registry->{$domain} && exists $registry->{$domain}{$type})
  {
    $db_info = $registry->{$domain}{$type}
  }
  else
  {
    Carp::croak "No database information found for domain '$domain' and type '$type'";
  }

  my $driver = $db_info->{'driver'}; 

  Carp::croak "No driver found for domain '$domain' and type '$type'"
    unless(defined $driver);

  my $driver_class = $class->driver_class($driver) or Carp::croak
    "No driver class found for driver '$driver'";

  my $self = bless {}, $driver_class;

  $self->{'_origin_class'} = $class;

  $self->init(@_);

  return $self;
}

sub init
{
  my($self) = shift;
  $self->SUPER::init(@_);
  $self->init_db_info;
}

sub init_domain { shift->_origin_class->default_domain }
sub init_type   { shift->_origin_class->default_type }
sub init_date_handler { Rose::DateTime::Format::Stub->new }
sub init_server_time_zone { 'floating' }

sub init_db_info
{
  my($self) = shift;

  my $class = ref $self;

  my $domain = $self->domain;
  my $type   = $self->type;

  my $db_info;

  my $registry = $class->db_registry_hash;

  if(exists $registry->{$domain} && exists $registry->{$domain}{$type})
  {
    $db_info = $registry->{$domain}{$type}
  }
  else
  {
    Carp::croak "No database information found for domain '$domain' and type '$type'";
  }

  unless($self->{'connect_options_for'}{$domain} && 
         $self->{'connect_options_for'}{$domain}{$type})
  {
    $self->{'connect_options'} = undef;

    if(my $custom_options = $db_info->{'connect_options'})
    {
      my $options = $self->connect_options;
      @$options{keys %$custom_options} = values %$custom_options;
    }

    $self->{'connect_options_for'} = { $domain => { $type => 1 } };
  }

  $self->driver($db_info->{'driver'});

  my $dsn = $db_info->{'dsn'} ||= $self->build_dsn(domain => $domain, 
                                                   type   => $type,
                                                   %$db_info);

  while(my($field, $value) = each(%$db_info))
  {
    next  if($field eq 'connect_options');
    $self->$field($value);
  }

  return 1;
}

sub init_connect_options
{
  my($class) = ref $_[0];
  $class->default_connect_options;
}

sub connect_option
{
  my($self, $param) = (shift, shift);

  my $options = $self->connect_options;

  return $options->{$param} = shift  if(@_);
  return $options->{$param};
}

sub dsn
{
  my($self) = shift;

  return $self->{'dsn'}  unless(@_);

  $self->{'dsn'} = shift;

  $self->database(undef);
  $self->host(undef);
  $self->port(undef);

  if(DBI->can('parse_dsn'))
  {
    if(my($scheme, $driver, $attr_string, $attr_hash, $driver_dsn) =
         DBI->parse_dsn($self->{'dsn'}))
    {
      $self->driver($driver)  if($driver);

      if($attr_string)
      {
        $self->_parsed_dsn($attr_hash, $driver_dsn);
      }
    }
    else { $self->error("Couldn't parse DSN '$self->{'dsn'}'") }
  }

  return $self->{'dsn'};
}

sub _parsed_dsn { }

sub dbh
{
  my($self) = shift;

  return $self->{'dbh'} || $self->init_dbh  unless(@_);

  unless(defined($_[0]))
  {
    return $self->{'dbh'} = undef;
  }

  $self->driver($_[0]->{'Driver'}{'Name'});

  return $self->{'dbh'} = $_[0];
}

sub driver
{
  if(@_ > 1)
  {
    if(defined $_[1] && defined $_[0]->{'driver'} && $_[0]->{'driver'} ne $_[1])
    {
      Carp::croak "Attempt to change driver from '$_[0]->{'driver'}' to ",
                  "'$_[1]' detected.  The driver cannot be changed after ",
                  "object creation.";
    }

    return $_[0]->{'driver'} = $_[1];
  }

  return $_[0]->{'driver'};
}

sub retain_dbh
{
  my($self) = shift;
  my $dbh = $self->dbh or return undef;
  #$Debug && warn "$self->{'_dbh_refcount'} -> ", ($self->{'_dbh_refcount'} + 1), " $dbh\n";
  $self->{'_dbh_refcount'}++;
  $self->{'_dbh_is_private'} = 0;
  return $dbh;
}

sub release_dbh
{
  my($self) = shift;

  my $dbh = $self->{'dbh'} or return 0;

  #$Debug && warn "$self->{'_dbh_refcount'} -> ", ($self->{'_dbh_refcount'} - 1), " $dbh\n";
  $self->{'_dbh_refcount'}--;

  unless($self->{'_dbh_refcount'})
  {
    $self->{'_dbh_is_private'} = 1;

    if(my $sqls = $self->pre_disconnect_sql)
    {
      eval
      {
        foreach my $sql (@$sqls)
        {
          $dbh->do($sql) or die "$sql - " . $dbh->errstr;
          return undef;
        }
      };

      if($@)
      {
        $self->error("Could not do pre-disconnect SQL: $@");
        return undef;
      }
    }

    #$Debug && warn "DISCONNECT $dbh ", join(':', (caller(3))[0,2]), "\n";
    return $dbh->disconnect;
  }
  #else { $Debug && warn "DISCONNECT NOOP $dbh ", join(':', (caller(2))[0,2]), "\n"; }

  return 1;
}

sub init_dbh
{
  my($self) = shift;

  $self->init_db_info;

  my $options = $self->connect_options;

  $Debug && warn "DBI->connect('", $self->dsn, "', '", $self->username, "', ...)\n";

  $self->error(undef);

  my $dbh = DBI->connect($self->dsn, $self->username, $self->password, $options);

  unless($dbh)
  {
    $self->error("Could not connect to database: $DBI::errstr");
    return 0;
  }

  $self->{'_dbh_refcount'}++;
  #$Debug && warn "CONNECT $dbh ", join(':', (caller(3))[0,2]), "\n";
  $self->{'_dbh_is_private'} = 1;

  #$self->_update_driver;

  if(my $sqls = $self->post_connect_sql)
  {
    eval
    {
      foreach my $sql (@$sqls)
      {
        $dbh->do($sql) or die "$sql - " . $dbh->errstr;
      }
    };

    if($@)
    {
      $self->error("Could not do post-connect SQL: $@");
      $dbh->disconnect;
      return undef;
    }
  }

  return $self->{'dbh'} = $dbh;
}

use constant MAX_SANE_TIMESTAMP => 30000000000000; # YYYYY MM DD HH MM SS

sub compare_timestamps
{
  my($self, $t1, $t2) = @_;

  foreach my $t ($t1, $t2)
  {
    if($t eq $self->min_timestamp)
    {
      $t = -1;
    }
    elsif($t eq $self->max_timestamp)
    {
      $t = MAX_SANE_TIMESTAMP;
    }
    else
    {
      $t = $self->parse_timestamp($t);

      # Last attempt to get a DateTime object
      unless(ref $t)
      {
        my $d = Rose::DateTime::Util::parse_date($t);
        $t = $d  if(defined $d);
      }

      if(ref $t)
      {
        $t = Rose::DateTime::Util::format_date($t, '%Y%m%d.%N');
      }
    }
  }

  return -1  if($t1 < 0 && $t2 < 0);
  return 1   if($t1 == MAX_SANE_TIMESTAMP && $t2 == MAX_SANE_TIMESTAMP);

  return $t1 <=> $t2;
}

sub print_error { shift->_dbh_and_connect_option('PrintError', @_) }
sub raise_error { shift->_dbh_and_connect_option('RaiseError', @_) }
sub autocommit  { shift->_dbh_and_connect_option('AutoCommit', @_) }

sub _dbh_and_connect_option
{
  my($self, $param) = (shift, shift);

  if(@_)
  {
    my $val = ($_[0]) ? 1 : 0;
    $self->connect_option($param => $val);

    $self->{'dbh'}{$param} = $val  if($self->{'dbh'});
  }

  return $self->{'dbh'} ? $self->{'dbh'}{$param} : 
         $self->connect_option($param);
}

sub connect
{
  my($self) = shift;

  $self->dbh or return 0;
  return 1;
}

sub disconnect
{
  my($self) = shift;

  $self->release_dbh or return undef;

  $self->{'dbh'} = undef;
}

sub begin_work
{
  my($self) = shift;

  my $dbh = $self->dbh or return undef;

  if($dbh->{'AutoCommit'})
  {
    my $ret;

    #$Debug && warn "BEGIN TRX\n";

    eval
    {
      local $dbh->{'RaiseError'} = 1;
      $ret = $dbh->begin_work
    };

    if($@)
    {
      $self->error('begin_work() - ' . $dbh->errstr);
      return undef;
    }

    unless($ret)
    {
      $self->error('begin_work() failed - ' . $dbh->errstr);
      return undef;
    }

    return 1;
  }

  return -1;
}

sub commit
{
  my($self) = shift;

  return 0  unless(defined $self->{'dbh'} && $self->{'dbh'}{'Active'});

  my $dbh = $self->dbh or return undef;

  unless($dbh->{'AutoCommit'})
  {
    my $ret;

    #$Debug && warn "COMMIT TRX\n";    

    eval
    {
      local $dbh->{'RaiseError'} = 1;
      $ret = $dbh->commit;
    };

    if($@)
    {
      $self->error('commit() - ' . $dbh->errstr);
      return undef;
    }

    unless($ret)
    {
      $self->error('Could not commit transaction: ' . 
                   ($dbh->errstr || $DBI::errstr || 
                    'Possibly a referential integrity violation.  ' .
                    'Check the database error log for more information.'));
      return undef;
    }

    return 1;
  }

  return -1;
}

sub rollback
{
  my($self) = shift;

  return 0  unless(defined $self->{'dbh'} && $self->{'dbh'}{'Active'});

  my $dbh = $self->dbh or return undef;

  my $ret;

  #$Debug && warn "ROLLBACK TRX\n";

  eval
  {
    local $dbh->{'RaiseError'} = 1;
    $ret = $dbh->rollback;
  };

  if($@)
  {
    $self->error('rollback() - ' . $dbh->errstr);
    return undef;
  }

  unless($ret)
  {
    $self->error('rollback() failed - ' . $dbh->errstr);
    return undef;
  }

  # DBI does this for me...
  #$dbh->{'AutoCommit'} = 1;

  return 1;
}

sub do_transaction
{
  my($self, $code) = (shift, shift);

  my $dbh = $self->dbh or return undef;  

  eval
  {
    local $dbh->{'RaiseError'} = 1;
    $self->begin_work or die $self->error;
    $code->(@_);
    $self->commit or die $self->error;
  };

  if($@)
  {
    my $error = "do_transaction() failed - $@";

    if($self->rollback)
    {
      $self->error($error);
    }
    else
    {
      $self->error("$error.  rollback() also failed - " . $self->error)
    }

    return undef;
  }

  return 1;
}

#
# These methods could/should be overriden in driver-specific subclasses
#

sub insertid_param { undef }
sub null_date      { '0000-00-00'  }
sub null_datetime  { '0000-00-00 00:00:00' }
sub null_timestamp { '00000000000000' }
sub min_timestamp  { '00000000000000' }
sub max_timestamp  { '00000000000000' }

sub last_insertid_from_sth { $_[1]->{$_[0]->insertid_param} }
sub generate_primary_key_values       { (undef) x ($_[1] || 1) }
sub generate_primary_key_placeholders { (undef) x ($_[1] || 1) }

# Boolean formatting and parsing

sub format_boolean { $_[1] ? 1 : 0 }

sub parse_boolean
{
  my($self, $value) = @_;
  return $value  if($self->validate_boolean_keyword($_[1]) || $_[1] =~ /^\w+\(.*\)$/);
  return 1  if($value =~ /^(?:t(?:rue)?|y(?:es)?|1)$/);
  return 0  if($value =~ /^(?:f(?:alse)?|no?|0)$/);

  $self->error("Invalid boolean value: '$value'");
  return undef;
}

# Date formatting

sub format_date
{  
  return $_[1]  if($_[0]->validate_date_keyword($_[1]) || $_[1] =~ /^\w+\(.*\)$/);
  return $_[0]->date_handler->format_date($_[1]);
}

sub format_datetime
{
  return $_[1]  if($_[0]->validate_datetime_keyword($_[1]) || $_[1] =~ /^\w+\(.*\)$/);
  return $_[0]->date_handler->format_datetime($_[1]);
}

sub format_time
{  
  return $_[1]  if($_[0]->validate_time_keyword($_[1])) || $_[1] =~ /^\w+\(.*\)$/;
  return $_[0]->date_handler->format_time($_[1]);
}

sub format_timestamp
{  
  return $_[1]  if($_[0]->validate_timestamp_keyword($_[1]) || $_[1] =~ /^\w+\(.*\)$/);
  return $_[0]->date_handler->format_timestamp($_[1]);
}

# Date parsing

sub parse_date
{  
  return $_[1]  if($_[0]->validate_date_keyword($_[1]));

  my $dt;
  eval { $dt = $_[0]->date_handler->parse_date($_[1]) };

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

  my $dt;
  eval { $dt = $_[0]->date_handler->parse_datetime($_[1]) };

  if($@)
  {
    $_[0]->error("Could not parse datetime '$_[1]' - $@");
    return undef;
  }

  return $dt;
}

sub parse_time
{  
  return $_[1]  if($_[0]->validate_time_keyword($_[1]));

  my $dt;
  eval { $dt = $_[0]->date_handler->parse_time($_[1]) };

  if($@)
  {
    $_[0]->error("Could not parse time '$_[1]' - $@");
    return undef;
  }

  return $dt;
}

sub parse_timestamp
{  
  return $_[1]  if($_[0]->validate_timestamp_keyword($_[1]));

  my $dt;
  eval { $dt = $_[0]->date_handler->parse_timestamp($_[1]) };

  if($@)
  {
    $_[0]->error("Could not parse timestamp '$_[1]' - $@");
    return undef;
  }

  return $dt;
}

sub parse_bitfield
{
  my($self, $val, $size) = @_;

  if(ref $val)
  {
    if($size && $val->Size != $size)
    {
      return Bit::Vector->new_Bin($size, $val->to_Bin);
    }

    return $val;
  }

  if($val =~ /^[10]+$/)
  {
    return Bit::Vector->new_Bin($size || length $val, $val);
  }
  elsif($val =~ /^\d*[2-9]\d*$/)
  {
    return Bit::Vector->new_Dec($size || (length($val) * 4), $val);
  }
  elsif($val =~ s/^0x// || $val =~ s/^X'(.*)'$/$1/ || $val =~ /^[0-9a-f]+$/i)
  {
    return Bit::Vector->new_Hex($size || (length($val) * 4), $val);
  }
  elsif($val =~ s/^B'([10]+)'$/$1/i)
  {
    return Bit::Vector->new_Bin($size || length $val, $val);
  }
  else
  {
    return undef;
    #return Bit::Vector->new_Bin($size || length($val), $val);
  }
}

sub format_bitfield 
{
  my($self, $vec, $size) = @_;

  $vec = Bit::Vector->new_Bin($size, $vec->to_Bin)  if($size);
  return $vec->to_Bin;
}

sub build_dsn { 'override in subclass' }

sub validate_boolean_keyword
{
  no warnings;
  $_[1] =~ /^(?:TRUE|FALSE)$/;
}

sub validate_date_keyword      { 0 }
sub validate_datetime_keyword  { 0 }
sub validate_time_keyword      { 0 }
sub validate_timestamp_keyword { 0 }

sub next_value_in_sequence
{
  my($self, $seq) = @_;
  $self->error("Don't know how to select next value in sequence '$seq' " .
               "for database driver " . $self->driver);
  return undef;
}

sub auto_sequence_name { return undef }

#
# This is both a class and an object method
#

sub error
{
  my($self_or_class) = shift;

  if(ref $self_or_class) # Object method
  {
    if(@_)
    {
      return $self_or_class->{'error'} = $Error = shift;
    }
    return $self_or_class->{'error'};  
  }

  # Class method
  return $Error = shift  if(@_);
  return $Error;
}

sub DESTROY
{
  $_[0]->disconnect;
}

BEGIN
{
  package Rose::DateTime::Format::Stub;

  use Rose::Object::MakeMethods::Generic
  (
    scalar  => 'server_tz',
    boolean => 'european',
  );

  sub format_date      { shift; Rose::DateTime::Util::format_date($_[0], '%Y-%m-%d') }
  sub format_datetime  { shift; Rose::DateTime::Util::format_date($_[0], '%Y-%m-%d %T') }
  sub format_timestamp { shift; Rose::DateTime::Util::format_date($_[0], '%Y%m%d%H%M%S') }

  sub parse_date       { shift; Rose::DateTime::Util::parse_date($_[0]) }
  sub parse_datetime   { shift; Rose::DateTime::Util::parse_date($_[0]) }
  sub parse_timestamp  { shift; Rose::DateTime::Util::parse_date($_[0]) }
}

1;

__END__

=head1 NAME

Rose::DB - A DBI wrapper and abstraction layer.

=head1 SYNOPSIS

  use Rose::DB;

  Rose::DB->register_db(
    domain   => 'development',
    type     => 'main',
    driver   => 'Pg',
    database => 'dev_db',
    host     => 'localhost',
    username => 'devuser',
    password => 'mysecret',
    server_time_zone => 'UTC',
  );

  Rose::DB->register_db(
    domain   => 'production',
    type     => 'main',
    driver   => 'Pg',
    database => 'big_db',
    host     => 'dbserver.acme.com',
    username => 'dbadmin',
    password => 'prodsecret',
    server_time_zone => 'UTC',
  );

  Rose::DB->default_domain('development');
  Rose::DB->default_type('main');
  ...

  $db = Rose::DB->new;

  my $dbh = $db->dbh or die $db->error;

  $db->begin_work or die $db->error;
  $dbh->do(...)   or die $db->error;
  $db->commit     or die $db->error;

  $db->do_transaction(sub
  {
    $dbh->do(...);
    $sth = $dbh->prepare(...);
    $sth->execute(...);
    while($sth->fetch) { ... }
    $dbh->do(...);
  }) 
  or die $db->error;

  $dt  = $db->parse_timestamp('2001-03-05 12:34:56.123');
  $val = $db->format_timestamp($dt);

  $dt  = $db->parse_datetime('2001-03-05 12:34:56');
  $val = $db->format_datetime($dt);

  $dt  = $db->parse_date('2001-03-05');
  $val = $db->format_date($dt);

  $bit = $db->parse_bitfield('0x0AF', 32);
  $val = $db->format_bitfield($bit);

  ...

=head1 DESCRIPTION

C<Rose::DB> is a wrapper and abstraction layer for C<DBI>-related functionality.  A C<Rose::DB> object "has a" C<DBI> object; it is not a subclass of C<DBI>.

=head1 DATABASE SUPPORT

C<Rose::DB> currently supports the following C<DBI> database drivers:

    DBD::Pg       (PostgreSQL)
    DBD::mysql    (MySQL)
    DBD::Informix (Informix)

Support for more drivers may be added in the future.  Patches are welcome (provided they also patch the test suite, of course).

All database-specific behavior is contained and documented in the subclasses of C<Rose::DB>.  C<Rose::DB>'s constructor method (C<new()>) returns  a database-specific subclass of C<Rose::DB>, chosen based on the C<driver> value of the selected L<data source|"Data Source Abstraction">.  The default mapping of databases to C<Rose::DB> subclasses is:

    DBD::Pg       -> Rose::DB::Pg      
    DBD::mysql    -> Rose::DB::MySQL   
    DBD::Informix -> Rose::DB::Informix

This mapping can be changed using the C<driver_class()> class method.

The C<Rose::DB> object method documentation found here defines the purpose of each method, as well as the default behavior of the method if it is not overridden by a subclass.  You must read the subclass documentation to learn about behaviors that are specific to each type of database.

Subclasses may also add methods that do not exist in the parent class, of course.  This is yet another reason to read the documentation for the subclass that corresponds to your data source's database software.

=head1 FEATURES

The basic features of C<Rose::DB> are as follows.

=head2 Data Source Abstraction

Instead of dealing with "databases" that exist on "hosts" or are located via some vendor-specific addressing scheme, C<Rose::DB> deals with "logical" data sources.  Each logical data source is currently backed by a single "physical" database (basically a single C<DBI> connection).

Multiplexing, fail-over, and other more complex relationships between logical data sources and physical databases are not part of C<Rose::DB>.  Some basic types of fail-over may be added to C<Rose::DB> in the future, but right now the mapping is strictly one-to-one.  (I'm also currently inclined to encourage multiplexing functionality to exist in a layer above C<Rose::DB>, rather than within it or in a subclass of it.)

The driver type of the data source determines the functionality of all methods that do vendor-specific things (e.g., L<column value parsing and formatting|"Vendor-Specific Column Value Parsing and Formatting">).

C<Rose::DB> identifies data sources using a two-level namespace made of a "domain" and a "type".  Both are arbitrary strings.  If left unspecified, the default domain and default type (accessible via C<Rose::DB>'s C<default_domain()> and C<default_type()> class methods) are assumed.

There are many ways to use the two-level namespace, but the most common is to use the domain to represent the current environment (e.g., "development", "staging", "production") and then use the type to identify the logical data source within that environment (e.g., "report", "main", "archive")

A typical deployment scenario will set the default domain using the C<default_domain()> class method as part of the configure/install process.  Within application code, C<Rose::DB> objects can be constructed by specifying type alone:

    $main_db    = Rose::DB->new(type => 'main');
    $archive_db = Rose::DB->new(type => 'archive');

If there is only one database type, then all C<Rose::DB> objects can be instantiated with a bare constructor call like this:

    $db = Rose::DB->new;

Again, remember that this is just one of many possible uses of domain and type.  Arbitrarily complex scenarios can be created by nesting namespaces within one or both parameters (much like how Perl uses "::" to create a multi-level namespace from single strings).

The important point is the abstraction of data sources so they can be identified and referred to using a vocabulary that is entirely independent of the actual DSN (data source names) used by C<DBI> behind the scenes.

=head2 Database Handle Life-Cycle Management

When a C<Rose::DB> object is destroyed while it contains an active C<DBI> database handle, the handle is explicitly disconnected before destruction.  C<Rose::DB> supports a simple retain/release reference-counting system which allows a database handle to out-live its parent C<Rose::DB> object.

In the simplest case, C<Rose::DB> could be used for its data source abstractions features alone. For example, transiently creating a C<Rose::DB> and then retaining its C<DBI> database handle before it is destroyed:

    $main_dbh = Rose::DB->new(type => 'main')->retain_dbh 
                  or die Rose::DB->error;

    $aux_dbh  = Rose::DB->new(type => 'aux')->retain_dbh  
                  or die Rose::DB->error;

If the database handle was simply extracted via the C<dbh()> method instead of retained with C<retain_dbh()>, it would be disconnected by the time the statement completed.

    # WRONG: $dbh will be disconnected immediately after the assignment!
    $dbh = Rose::DB->new(type => 'main')->dbh or die Rose::DB->error;

=head2 Vendor-Specific Column Value Parsing and Formatting

Certain semantically identical column types are handled differently in different databases.  Date and time columns are good examples.  Although many databases  store month, day, year, hours, minutes, and seconds using a "datetime" column type, there will likely be significant differences in how each of those databases expects to receive such values, and how they're returned.

C<Rose::DB> is responsible for converting the wide range of vendor-specific column values for a particular column type into a single form that is convenient for use within Perl code.  C<Rose::DB> also handles the opposite task, taking input from the Perl side and converting it into the appropriate format for a specific database.  Not all column types that exist in the supported databases are handled by C<Rose::DB>, but support will expand in the future.

Many column types are specific to a single database and do not exist elsewhere.  When it is reasonable to do so, vendor-specific column types may be "emulated" by C<Rose::DB> for the benefit of other databases.  For example, an ARRAY value may be stored as a specially formatted string in a VARCHAR field in a database that does not have a native ARRAY column type.

C<Rose::DB> does B<NOT> attempt to present a unified column type system, however.  If a column type does not exist in a particular kind of database, there should be no expectation that C<Rose::DB> will be able to parse and format that value type on behalf of that database.

=head2 High-Level Transaction Support

Transactions may be started, committed, and rolled back in a variety of ways using the C<DBI> database handle directly.  C<Rose::DB> provides wrappers to do the same things, but with different error handling and return values.  There's also a method (C<do_transaction()>) that will execute arbitrary code within a single transaction, automatically handling rollback on failure and commit on success.

=head1 SUBCLASSING

Subclassing is encouraged and generally works as expected.  There is, however, the question of how class data is shared with subclasses.  Here's how it works for the various pieces of class data.

=over

=item B<default_domain>, B<default_type>

If called with no arguments, and if the attribute was never set for this
class, then a left-most, breadth-first search of the parent classes is
initiated.  The value returned is taken from first parent class 
encountered that has ever had this attribute set.

(These attributes use the C<inheritable_scalar> method type as defined in C<Rose::Class::MakeMethods::Generic>.)

=item B<driver_class>, B<default_connect_options>

These hashes of attributes are inherited by subclasses using a one-time, shallow copy from a superclass.  Any subclass that accesses or manipulates the hash in any way will immediately get its own private copy of the hash I<as it exists in the superclass at the time of the access or manipulation>.  

The superclass from which the hash is copied is the closest ("least super") class that has ever accessed or manipulated this hash.  The copy is a "shallow" copy, duplicating only the keys and values.  Reference values are not recursively copied.

Setting to hash to undef (using the 'reset' interface) will cause it to be re-copied from a superclass the next time it is accessed.

(These attributes use the C<inheritable_hash> method type as defined in C<Rose::Class::MakeMethods::Generic>.)

=item B<modify_db>, B<register_db>, B<unregister_db>, B<unregister_domain>

All subclasses share the same data source "registry" with C<Rose::DB>.  There is an undocumented method for creating a private data source registry for a subclass of C<Rose::DB> (search DB.pm for C<sub db_registry_hash>), but it is subject to change without notice and should not be relied upon.  If there is enough demand for a supported method, I will add one.

=back

=head1 CLASS METHODS

=over 4

=item B<default_connect_options [HASHREF | PAIRS]>

Get or set the default C<DBI> connect options hash.  If a reference to a hash is passed, it replaces the default connect options hash.  If a series of name/value pairs are passed, they are added to the default connect options hash.

The default set of default connect options is:

    AutoCommit => 1,
    RaiseError => 1,
    PrintError => 1,
    ChopBlanks => 1,
    Warn       => 0,

See the C<connect_options()> object method for more information on how the default connect options are used.

=item B<default_domain [DOMAIN]>

Get or set the default data source domain.  See the L<"Data Source Abstraction"> section for more information on data source domains.

=item B<default_type [TYPE]>

Get or set the default data source type.  See the L<"Data Source Abstraction"> section for more information on data source types.

=item B<driver_class DRIVER [, CLASS]>

Get or set the subclass used for DRIVER.

    $class = Rose::DB->driver_class('Pg');      # get
    Rose::DB->driver_class('Pg' => 'MyDB::Pg'); # set

See the documentation for the C<new()> method for more information on how the driver influences the class of objects returned by the constructor.

=item B<modify_db PARAMS>

Modify a new data source, setting the attributes specified in PARAMS, where
PARAMS are name/value pairs.  Any C<Rose::DB> object method that sets a L<data source configuration value|"Data Source Configuration"> is a valid parameter name.

    # Set new username for data source identified by domain and type
    Rose::DB->modify_db(domain   => 'test', 
                        type     => 'main',
                        username => 'tester');

PARAMS B<must> include values for both the C<type> and C<domain> parameters since these two attributes are used to identify the data source.  If either one is missing, a fatal error will occur.

If there is no data source defined for the specified C<type> and C<domain>, a fatal error will occur.

=item B<register_db PARAMS>

Registers a new data source with the attributes specified in PARAMS, where
PARAMS are name/value pairs.  Any C<Rose::DB> object method that sets a L<data source configuration value|"Data Source Configuration"> is a valid parameter name.

PARAMS B<must> include values for the C<type>, C<domain>, and C<driver> parameters.

The C<type> and C<domain> are used to identify the data source.  If either one is missing, a fatal error will occur.  See the L<"Data Source Abstraction"> section for more information on data source types and domains.

The C<driver> is used to determine which class objects will be blessed into by the C<Rose::DB> constructor, C<new()>.  If it is missing, a fatal error will occur.

In most deployment scenarios, C<register_db()> is called early in the compilation process to ensure that the registered data sources are available when the "real" code runs.

Database registration is often consolidated to a single module which is then C<use>ed at the start of the code.  For example, imagine a mod_perl web server environment:

    # File: MyCorp/DataSources.pm
    package MyCorp::DataSources;

    Rose::DB->register_db(
      domain   => 'development',
      type     => 'main',
      driver   => 'Pg',
      database => 'dev_db',
      host     => 'localhost',
      username => 'devuser',
      password => 'mysecret',
    );

    Rose::DB->register_db(
      domain   => 'production',
      type     => 'main',
      driver   => 'Pg',
      database => 'big_db',
      host     => 'dbserver.acme.com',
      username => 'dbadmin',
      password => 'prodsecret',
    );
    ...

    # File: /usr/local/apache/conf/startup.pl

    use MyCorp::DataSources; # register all data sources
    ...

Data source registration can happen at any time, of course, but it is most useful when all application code can simply assume that all the data sources are already registered.  Doing the registration as early as possible (e.g., in a C<startup.pl> file that is loaded from an apache/mod_perl web server's C<httpd.conf> file) is the best way to create such an environment.

=item B<unregister_db PARAMS>

Unregisters the data source having the C<type> and C<domain> specified in  PARAMS, where PARAMS are name/value pairs.  Returns true if the data source was unregistered successfully, false if it did not exist in the first place.  Example:

    Rose::DB->unregister_db(type => 'main', domain => 'test');

PARAMS B<must> include values for both the C<type> and C<domain> parameters since these two attributes are used to identify the data source.  If either one is missing, a fatal error will occur.

Unregistering a data source removes all knowledge of it.  This may be harmful to any existing C<Rose::DB> objects that are associated with that data source.

=item B<unregister_domain DOMAIN>

Unregisters an entire domain.  Returns true if the domain was unregistered successfully, false if it did not exist in the first place.  Example:

    Rose::DB->unregister_domain('test');

Unregistering a domain removes all knowledge of all of the data sources that existed under it.  This may be harmful to any existing C<Rose::DB> objects that are associated with any of those data sources.

=back

=head1 CONSTRUCTOR

=over 4

=item B<new PARAMS>

Constructs a new object based on PARAMS, where PARAMS are
name/value pairs.  Any object method is a valid parameter name.  Example:

    $db = Rose::DB->new(type => 'main', domain => 'qa');

If a single argument is passed to C<new()>, it is used as the C<type> value:

    $db = Rose::DB->new(type => 'aux'); 
    $db = Rose::DB->new('aux'); # same thing

Each C<Rose::DB> object is associated with a particular data source, defined by the C<type> and C<domain> values.  If these are not part of PARAMS, then the default values are used.  If you do not want to use the default values for the C<type> and C<domain> attributes, you should specify them in the constructor PARAMS.

The default C<type> and C<domain> can be set using the C<default_type()> and C<default_domain()> class methods.  See the L<"Data Source Abstraction"> section for more information on data sources.

The object returned by C<new()> will be a database-specific subclass of C<Rose::DB>, chosen based on the C<driver> value of the selected data source.  If there is no registered data source for the specified C<type> and C<domain>, or if a fatal error will occur.

The default driver-to-class mapping is as follows:

    Pg       -> Rose::DB::Pg
    mysql    -> Rose::DB::MySQL
    Informix -> Rose::DB::Informix

You can change this mapping with the C<driver_class()> class method.

=back

=head1 OBJECT METHODS

=over 4

=item B<begin_work>

Attempt to start a transaction by calling the C<begin_work()> method on the C<DBI> database handle.

If necessary, the database handle will be constructed and connected to the current data source.  If this fails, undef is returned.  If there is no registered data source for the current C<type> and C<domain>, a fatal error will occur.

If the "AutoCommit" database handle attribute is false, the handle is assumed to already be in a transaction and C<Rose::DB::Constants::IN_TRANSACTION> (-1) is returned.  If the call to C<DBI>'s C<begin_work()> method succeeds, 1 is returned.  If it fails, undef is returned.

=item B<commit>

Attempt to commit the current transaction by calling the C<commit()> method on the C<DBI> database handle.  If the C<DBI> database handle does not exist or is not connected, 0 is returned.

If the "AutoCommit" database handle attribute is true, the handle is assumed to not be in a transaction and C<Rose::DB::Constants::IN_TRANSACTION> (-1) is returned.  If the call to C<DBI>'s C<commit()> method succeeds, 1 is returned.  If it fails, undef is returned.

=item B<connect>

Constructs and connects the C<DBI> database handle for the current data source.  If there is no registered data source for the current C<type> and C<domain>, a fatal error will occur.

If any C<post_connect_sql> statement failed to execute, the database handle is disconnected and then discarded.

Returns true if the database handle was connected successfully and all C<post_connect_sql> statements (if any) were run successfully, false otherwise.  

=item B<connect_option NAME [, VALUE]>

Get or set a single connection option.  Example:

    $val = $db->connect_option('RaiseError'); # get
    $db->connect_option(AutoCommit => 1);     # set

Connection options are name/value pairs that are passed in a hash reference as the fourth argument to the call to C<DBI-E<gt>connect()>.  See the C<DBI> documentation for descriptions of the various options.

=item B<dbh>

Returns the C<DBI> database handle connected to the current data source.  If the database handle does not exist or is not already connected, this method will do everything necessary to do so.

Returns undef if the database handle could not be constructed and connected.  If there is no registered data source for the current C<type> and C<domain>, a fatal error will occur.

=item B<disconnect>

Decrements the reference count for the database handle and disconnects it if the reference count is zero.  Regardless of the reference count, it sets the C<dbh> attribute to undef.

Returns true if all C<pre_disconnect_sql> statements (if any) were run successfully and the database handle was disconnected successfully (or if it was simply set to undef), false otherwise.

The database handle will not be disconnected if any C<pre_disconnect_sql> statement fails to execute, and the C<pre_disconnect_sql> is not run unless the handle is going to be disconnected.

=item B<do_transaction CODE [, ARGS]>

Execute arbitrary code within a single transaction, rolling back if any of the code fails, committing if it succeeds.  CODE should be a code reference.  It will be called with any arguments passed to C<do_transaction()> after the code reference.  Example:

    # Transfer $100 from account id 5 to account id 9
    $db->do_transaction(sub
    {
      my($amt, $id1, $id2) = @_;

      my $dbh = $db->dbh or die $db->error;

      # Transfer $amt from account id $id1 to account id $id2
      $dbh->do("UPDATE acct SET bal = bal - $amt WHERE id = $id1");
      $dbh->do("UPDATE acct SET bal = bal + $amt WHERE id = $id2");
    },
    100, 5, 9) or warn "Transfer failed: ", $db->error;

=item B<error [MSG]>

Get or set the error message associated with the last failure.  If a method fails, check this attribute to get the reason for the failure in the form of a text message.

=item B<init_db_info>

Initialize data source configuration information based on the current values of the C<type> and C<domain> attributes.  If there is no registered data source for the current C<type> and C<domain>, a fatal error will occur.  C<init_db_info()> is called as part of the C<new()> and C<connect()> methods.

=item B<insertid_param>

Returns the name of the C<DBI> statement handle attribute that contains the auto-generated unique key created during the last insert operation.  Returns undef if the current data source does not support this attribute.

=item B<last_insertid_from_sth STH>

Given a C<DBI> statement handle, returns the value of the auto-generated unique key created during the last insert operation.  This value may be undefined if this feature is not supported by the current data source.

=item B<release_dbh>

Decrements the reference count for the C<DBI> database handle, if it exists.  Returns 0 if the database handle does not exist.

If the reference count drops to zero, the database handle is disconnected.  Keep in mind that the C<Rose::DB> object itself will increment the reference count when the database handle is connected, and decrement it when C<disconnect()> is called.

Returns true if the reference count is not 0 or if all C<pre_disconnect_sql> statements (if any) were run successfully and the database handle was disconnected successfully, false otherwise.

The database handle will not be disconnected if any C<pre_disconnect_sql> statement fails to execute, and the C<pre_disconnect_sql> is not run unless the handle is going to be disconnected.

See the L<"Database Handle Life-Cycle Management"> section for more information on the retain/release system.

=item B<retain_dbh>

Returns the connected C<DBI> database handle after incrementing the reference count.  If the database handle does not exist or is not already connected, this method will do everything necessary to do so.

Returns undef if the database handle could not be constructed and connected.  If there is no registered data source for the current C<type> and C<domain>, a fatal error will occur.

See the L<"Database Handle Life-Cycle Management"> section for more information on the retain/release system.

=item B<rollback>

Roll back the current transaction by calling the C<rollback()> method on the C<DBI> database handle.  If the C<DBI> database handle does not exist or is not connected, 0 is returned.

If the call to C<DBI>'s C<rollback()> method succeeds, 1 is returned.  If it fails, undef is returned.

=back

=head2 Data Source Configuration

Not all databases will use all of these values.  Values that are not supported are simply ignored.

=over 4

=item B<autocommit [VALUE]>

Get or set the value of the "AutoCommit" connect option and C<DBI> handle attribute.  If a VALUE is passed, it will be set in both the connect options hash and the current database handle, if any.  Returns the value of the "AutoCommit" attribute of the database handle if it exists, or the connect option otherwise.

This method should not be mixed with the C<connect_options> method in calls to C<register_db()> or C<modify_db()> since C<connect_options> will overwrite I<all> the connect options with its argument, and neither C<register_db()> nor C<modify_db()> guarantee the order that its parameters will be evaluated.

=item B<connect_options [HASHREF | PAIRS]>

Get or set the options passed in a hash reference as the fourth argument to the call to C<DBI-E<gt>connect()>.  See the C<DBI> documentation for descriptions of the various options.

If a reference to a hash is passed, it replaces the connect options hash.  If a series of name/value pairs are passed, they are added to the connect options hash.

Returns a reference to the hash of options in scalar context, or a list of name/value pairs in list context.

When C<init_db_info()> is called for the first time on an object (either in isolation or as part of the C<connect()> process), the connect options are merged with the C<default_connect_options()>.  The defaults are overridden in the case of a conflict.  Example:

    Rose::DB->register_db(
      domain   => 'development',
      type     => 'main',
      driver   => 'Pg',
      database => 'dev_db',
      host     => 'localhost',
      username => 'devuser',
      password => 'mysecret',
      connect_options =>
      {
        RaiseError => 0, 
        AutoCommit => 0,
      }
    );

    # Rose::DB->default_connect_options are:
    #
    # AutoCommit => 1,
    # ChopBlanks => 1,
    # PrintError => 1,
    # RaiseError => 1,
    # Warn       => 0,

    # The object's connect options are merged with default options 
    # since new() will trigger the first call to init_db_info()
    # for this object
    $db = Rose::DB->new(domain => 'development', type => 'main');

    # $db->connect_options are:
    #
    # AutoCommit => 0,
    # ChopBlanks => 1,
    # PrintError => 1,
    # RaiseError => 0,
    # Warn       => 0,

    $db->connect_options(TraceLevel => 2); # Add an option

    # $db->connect_options are now:
    #
    # AutoCommit => 0,
    # ChopBlanks => 1,
    # PrintError => 1,
    # RaiseError => 0,
    # TraceLevel => 2,
    # Warn       => 0,

    # The object's connect options are NOT re-merged with the default 
    # connect options since this will trigger the second call to 
    # init_db_info(), not the first
    $db->connect or die $db->error; 

    # $db->connect_options are still:
    #
    # AutoCommit => 0,
    # ChopBlanks => 1,
    # PrintError => 1,
    # RaiseError => 0,
    # TraceLevel => 2,
    # Warn       => 0,

=item B<database [NAME]>

Get or set the database name used in the construction of the DSN used in the C<DBI> C<connect()> call.

=item B<domain [DOMAIN]>

Get or set the data source domain.  See the L<"Data Source Abstraction"> section for more information on data source domains.

=item B<driver [DRIVER]>

Get or set the driver name.  The driver name can only be set during object construction (i.e., as an argument to C<new()>) since it determines the object class (according to the mapping set by the C<driver_class()> class method).  After the object is constructed, setting the driver to anything other than the same value it already has will cause a fatal error.

Even in the call to C<new()>, setting the driver name explicitly is not recommended.  Instead, specify the driver when calling C<register_db()> for each data source and allow the C<driver> to be set automatically based on the C<domain> and C<type>.

The driver names for the L<currently supported database types|"DATABASE SUPPORT"> are:

    Pg
    mysql
    Informix

The driver names are case-sensitive.

=item B<dsn [DSN]>

Get or set the C<DBI> DSN (Data Source Name) passed to the call to C<DBI>'s C<connect()> method.

When this value is set, C<database>, C<host>, and C<port> are set to undef.  If using C<DBI> version 1.43 or later, an attempt is made to parse the new DSN using C<DBI>'s C<parse_dsn()> method.  Any parts successfully extracted are assigned to the corresponding C<Rose::DB> attributes (e.g., host, port, database).

If the DSN is never set explicitly, it is initialized with the DSN constructed from the component values when C<init_db_info()> or C<connect()> is called.

=item B<host [NAME]>

Get or set the database server host name used in the construction of the DSN which is passed in the C<DBI> C<connect()> call.

=item B<password [PASS]>

Get or set the password that will be passed to the C<DBI> C<connect()> call.

=item B<port [NUM]>

Get or set the database server port number used in the construction of the DSN which is passed in the C<DBI> C<connect()> call.

=item B<pre_disconnect_sql [STATEMENTS]>

Get or set the SQL statements that will be run immediately before disconnecting from the database.  STATEMENTS should be a list or reference to an array of SQL statements.  Returns a reference to the array of SQL statements in scalar context, or a list of SQL statements in list context.

The SQL statements are run in the order that they are supplied in STATEMENTS.  If any C<pre_disconnect_sql> statement fails when executed, the subsequent statements are ignored.

=item B<post_connect_sql [STATEMENTS]>

Get or set the SQL statements that will be run immediately after connecting to the database.  STATEMENTS should be a list or reference to an array of SQL statements.  Returns a reference to the array of SQL statements in scalar context, or a list of SQL statements in list context.

The SQL statements are run in the order that they are supplied in STATEMENTS.  If any C<post_connect_sql> statement fails when executed, the subsequent statements are ignored.

=item B<print_error [VALUE]>

Get or set the value of the "PrintError" connect option and C<DBI> handle attribute.  If a VALUE is passed, it will be set in both the connect options hash and the current database handle, if any.  Returns the value of the "PrintError" attribute of the database handle if it exists, or the connect option otherwise.

This method should not be mixed with the C<connect_options> method in calls to C<register_db()> or C<modify_db()> since C<connect_options> will overwrite I<all> the connect options with its argument, and neither C<register_db()> nor C<modify_db()> guarantee the order that its parameters will be evaluated.

=item B<raise_error [VALUE]>

Get or set the value of the "RaiseError" connect option and C<DBI> handle attribute.  If a VALUE is passed, it will be set in both the connect options hash and the current database handle, if any.  Returns the value of the "RaiseError" attribute of the database handle if it exists, or the connect option otherwise.

This method should not be mixed with the C<connect_options> method in calls to C<register_db()> or C<modify_db()> since C<connect_options> will overwrite I<all> the connect options with its argument, and neither C<register_db()> nor C<modify_db()> guarantee the order that its parameters will be evaluated.

=item B<server_time_zone [TZ]>

Get or set the time zone used by the database server software.  TZ should be a time zone name that is understood by C<DateTime::TimeZone>.  The default value is "floating".

See the C<DateTime::TimeZone> documentation for acceptable values of TZ.

=item B<type [TYPE]>

Get or set the  data source type.  See the L<"Data Source Abstraction"> section for more information on data source types.

=item B<username [NAME]>

Get or set the username that will be passed to the C<DBI> C<connect()> call.

=back

=head2 Value Parsing and Formatting

=over 4

=item B<format_bitfield BITS [, SIZE]>

Converts the C<Bit::Vector> object BITS into the appropriate format for the "bitfield" data type of the current data source.  If a SIZE argument is provided, the bit field will be padded with the appropriate number of zeros until it is SIZE bits long.  If the data source does not have a native "bit" or "bitfield" data type, a character data type may be used to store the string of 1s and 0s returned by the default implementation.

=item B<format_boolean VALUE>

Converts VALUE into the appropriate format for the "boolean" data type of the current data source.  VALUE is simply evaluated in Perl's scalar context to determine if it's true or false.

=item B<format_date DATETIME>

Converts the C<DateTime> object DATETIME into the appropriate format for the "date" (month, day, year) data type of the current data source.

=item B<format_datetime DATETIME>

Converts the C<DateTime> object DATETIME into the appropriate format for the "datetime" (month, day, year, hour, minute, second) data type of the current data source.

=item B<format_timestamp DATETIME>

Converts the C<DateTime> object DATETIME into the appropriate format for the timestamp (month, day, year, hour, minute, second, fractional seconds) data type of the current data source.  Fractional seconds are optional, and the useful precision may vary depending on the data source.

=item B<parse_bitfield BITS [, SIZE]>

Parse BITS and return a corresponding C<Bit::Vector> object.  If SIZE is not passed, then it defaults to the number of bits in the parsed bit string.

If BITS is a string of "1"s and "0"s or matches /^B'[10]+'$/, then the "1"s and "0"s are parsed as a binary string.

If BITS is a string of numbers, at least one of which is in the range 2-9, it is assumed to be a decimal (base 10) number and is converted to a bitfield as such.

If BITS matches any of these regular expressions:

    /^0x/
    /^X'.*'$/
    /^[0-9a-f]+$/

it is assumed to be a hexadecimal number and is converted to a bitfield as such.

Otherwise, undef is returned.

=item B<parse_boolean STRING>

Parse STRING and return a boolean value of 1 or 0.  STRING should be formatted according to the data source's native "boolean" data type.  The default implementation accepts 't', 'true', 'y', 'yes', and '1' values for true, and 'f', 'false', 'n', 'no', and '0' values for false.

If STRING is a valid boolean keyword (according to C<validate_boolean_keyword()>) or if it looks like a function call (matches /^\w+\(.*\)$/) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "boolean" value.

=item B<parse_date STRING>

Parse STRING and return a C<DateTime> object.  STRING should be formatted according to the data source's native "date" (month, day, year) data type.

If STRING is a valid date keyword (according to C<validate_date_keyword()>) or if it looks like a function call (matches /^\w+\(.*\)$/) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "date" value.

=item B<parse_datetime STRING>

Parse STRING and return a C<DateTime> object.  STRING should be formatted according to the data source's native "datetime" (month, day, year, hour, minute, second) data type.

If STRING is a valid datetime keyword (according to C<validate_datetime_keyword()>) or if it looks like a function call (matches /^\w+\(.*\)$/) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "datetime" value.

=item B<parse_timestamp STRING>

Parse STRING and return a C<DateTime> object.  STRING should be formatted according to the data source's native "timestamp" (month, day, year, hour, minute, second, fractional seconds) data type.  Fractional seconds are optional, and the acceptable precision may vary depending on the data source.  

If STRING is a valid timestamp keyword (according to C<validate_timestamp_keyword()>) or if it looks like a function call (matches /^\w+\(.*\)$/) it is returned unmodified.  Returns undef if STRING could not be parsed as a valid "timestamp" value.

=item B<validate_boolean_keyword STRING>

Returns true if STRING is a valid keyword for the "boolean" data type of the current data source, false otherwise.  The default implementation accepts the values "TRUE" and "FALSE".

=item B<validate_date_keyword STRING>

Returns true if STRING is a valid keyword for the "date" (month, day, year) data type of the current data source, false otherwise.  The default implementation always returns false.

=item B<validate_datetime_keyword STRING>

Returns true if STRING is a valid keyword for the "datetime" (month, day, year, hour, minute, second) data type of the current data source, false otherwise.  The default implementation always returns false.

=item B<validate_timestamp_keyword STRING>

Returns true if STRING is a valid keyword for the "timestamp" (month, day, year, hour, minute, second, fractional seconds) data type of the current data source, false otherwise.  The default implementation always returns false.

=back

=head1 AUTHOR

John C. Siracusa (siracusa@mindspring.com)

=head1 COPYRIGHT

Copyright (c) 2005 by John C. Siracusa.  All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the same terms
as Perl itself.
