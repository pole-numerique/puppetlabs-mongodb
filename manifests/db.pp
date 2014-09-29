# == Class: mongodb::db
#
# Class for creating mongodb databases and users.
#
# == Parameters
#
#  name (namevar) - database name.
#  user - Database username.
#  password_hash - Hashed password, not mandatory in MongoDB 2.6. Hex encoded md5 hash of "$username:mongo:$password".
#  password - Plain text user password. Required in MongoDB 2.6, otherwise this is UNSAFE, use 'password_hash' unstead.
#  roles (default: ['dbAdmin']) - array with user roles.
#  tries (default: 10) - The maximum amount of two second tries to wait MongoDB startup.
#  admin_user - user with sufficient admin rights, mandatory in auth mode
#  admin_password - mandatory in auth mode
#
define mongodb::db (
  $user,
  $password_hash = false,
  $password      = false,
  $roles         = ['dbAdmin'],
  $tries         = 10,
  $admin_user     = $::mongodb::server::admin_user,
  $admin_password = $::mongodb::server::admin_password,
) {

  mongodb_database { $name:
    ensure   => present,
    admin_user     => $admin_user,
    admin_password => $admin_password,
    tries    => $tries,
    require  => Class['mongodb::server'],
  }

  if $password_hash {
    $hash = $password_hash
  } elsif $password {
    $hash = mongodb_password($user, $password)
  } else {
    fail("Parameter 'password_hash' or 'password' should be provided to mongodb::db.")
  }

  mongodb_user { $user:
    ensure        => present,
    admin_user     => $admin_user,
    admin_password => $admin_password,
    password => $password,
    password_hash => $hash,
    database      => $name,
    roles         => $roles,
    require       => Mongodb_database[$name],
  }

}
