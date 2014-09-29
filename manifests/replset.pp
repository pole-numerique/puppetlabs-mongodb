# Wrapper class useful for hiera based deployments

class mongodb::replset(
  $sets = undef,
  $admin_user     = $::mongodb::server::admin_user,
  $admin_password = $::mongodb::server::admin_password,
) {

  if $sets {
    create_resources(mongodb_replset, $sets)
  }
}
