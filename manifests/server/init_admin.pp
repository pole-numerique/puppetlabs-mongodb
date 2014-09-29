# PRIVATE CLASS: do not call directly
class mongodb::server::init_admin {
  
  $admin_user        = $mongodb::server::admin_user
  $admin_password    = $mongodb::server::admin_password

  $ensure          = $mongodb::server::ensure
  $user            = $mongodb::server::user

  $dbpath          = $mongodb::server::dbpath
  $pidfilepath     = $mongodb::server::pidfilepath
  $logpath         = $mongodb::server::logpath
  #$port            = $mongodb::server::port
  $journal         = $mongodb::server::journal
  $nojournal       = $mongodb::server::nojournal
  $smallfiles      = $mongodb::server::smallfiles
  $auth            = $mongodb::server::auth
  $noath           = $mongodb::server::noauth
  #$master          = $mongodb::server::master
  #$slave           = $mongodb::server::slave
  $replset         = $mongodb::server::replset
  #$bind_ip         = $mongodb::server::bind_ip

  if (($ensure == 'present' or $ensure == true) and $auth) {
    #$mongodb_not_inited_generate_res = generate('/bin/sh', '-c', "res=`/usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" 2>/dev/null` ; echo -n $res && exit 0")
    #$mongodb_inited_generate_res = generate('/bin/sh', '-c', "/usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" >/dev/null && echo -n success || echo -n failed")
    $mongodb_not_inited_generate_res = generate('/bin/sh', '-c', "res=eval /usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" 2>/dev/null ; echo -n $res && exit 0")
    # NB. if no grep, generate fails because internal command fails ; not backticks because also exec the result of the command
    $mongodb_not_inited = 'failed' in $mongodb_not_inited_generate_res
  
  if ($mongodb_not_inited) {
    # NB. within /bin/sh else "Generators can only contain alphanumerics, file separators, and dashes"
    # see https://projects.puppetlabs.com/issues/5481
    # in and not '... | grep "failed"' == '' else Failed to execute generator... Execution... returned 1
    notify { "MongoDB not yet inited (replset & auth admin) ! $mongodb_not_inited_generate_res": }
  
    file { '/etc/mongod_prestart.conf' :
      content => template('mongodb/mongodb_prestart.conf.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
    }
  
  # 33. init security :
  exec { "Init admin user" :
    # * db.createUser() must be called first to rightly init mongo 2.6 users
    # (so that db.system.version.find() => { "_id" : "authSchema", "currentVersion" : 3 } and not 1
    # which mere db.system.users.insert(...) as puppetlabs-mongodb does fails to do
    # (but allows not to have plain text passwords in puppet conf))
    # * this can't be done in a new keyFile-auth'd replset so it requires to happen BEFOREHANDS WITHOUT SUCH CONF
    # (so it couldn't be done merely with a mongodb_user)
    # see http://docs.mongodb.org/manual/tutorial/deploy-replica-set-with-auth/ 
    # NB. beware of rights ! of files (pid, log, nohup log), and sudo as user required else error "[initandlisten] exception in initAndListen: 10309 Unable to create/open lock file: /var/lib/mongodb/mongod.lock errno:13 Permission denied Is a mongod instance already running?, terminating"
    command => "/bin/true ; kill `cat /tmp/mongod_prestart.pid` ; rm -f /var/lib/mongodb/mongod.lock ; \
        sudo -u $user nohup sh -c \"/usr/bin/mongod --pidfilepath /tmp/mongod_prestart.pid -f /etc/mongod_prestart.conf\" &> /var/log/mongodb/mongodb_prestart_nohup.log & \
        /usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" 2>/dev/null && kill `cat /tmp/mongod_prestart.pid` && exit 0 ;
        /usr/bin/mongo admin --quiet --eval \"db.createUser({ user: \\\"${admin_user}\\\", pwd: \\\"${admin_password}\\\", \
        roles: [ { role: \\\"userAdminAnyDatabase\\\", db: \\\"admin\\\" }, { role: \\\"dbAdminAnyDatabase\\\", db: \\\"admin\\\" }, \
        { role: \\\"readWriteAnyDatabase\\\", db: \\\"admin\\\" }, { role: \\\"clusterAdmin\\\", db: \\\"admin\\\" }, \
        { role: \\\"root\\\", db: \\\"admin\\\" } ] })\" \
        && kill `cat /tmp/mongod_prestart.pid` && rm -f /var/lib/mongodb/mongod.lock  && exit 0 ; exit 1",
        # kill pid rather than /etc/init.d/mongod stop if consecutive "apply"s and better than ps -ef | grep \"mongod\" | awk '{print \$2}' | xargs kill which is hard to follow on
        ## /tmp/mongod_prestart.pid
        ##sudo -u $user nohup /usr/bin/mongod --smallfiles --auth --replSet $replset --dbpath /var/lib/mongodb --logpath=/var/log/mongodb/mongodb_prestart.log &> /var/log/mongodb/mongodb_prestart_nohup.log & \
    tries => 10,
    try_sleep => 1,
    logoutput => true,
    #timeout => 300,
    require => File['/etc/mongod_prestart.conf'],
  }
  
  } else {
    notify { "MongoDB already inited (replset & auth admin) ! $mongodb_not_inited_generate_res": }
  }
  
  }
}
