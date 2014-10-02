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
  $is_primary       = $mongodb::server::is_primary # compute it by = $replset_members[0] == $mongodb_host, used only to know whether to create admin user in prestart
  #$bind_ip         = $mongodb::server::bind_ip

  if (($ensure == 'present' or $ensure == true) and $auth and (!$replset or $is_primary)) {
    #$mongodb_not_inited_generate_res = generate('/bin/sh', '-c', "res=`/usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" 2>/dev/null` ; echo -n \$res && exit 0")
    #$mongodb_inited_generate_res = generate('/bin/sh', '-c', "/usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" >/dev/null && echo -n success || echo -n failed")
    ##$mongodb_not_inited_generate_res = generate('/bin/sh', '-c', "res=eval /usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" 2>/dev/null ; echo -n \$res && exit 0")
    # NB. if no grep, generate fails because internal command fails ; not backticks because also exec the result of the command
    ##$mongodb_not_inited = 'failed' in $mongodb_not_inited_generate_res
  
  ##if ($mongodb_not_inited) {
    # NB. within /bin/sh else "Generators can only contain alphanumerics, file separators, and dashes"
    # see https://projects.puppetlabs.com/issues/5481
    # in and not '... | grep "failed"' == '' else Failed to execute generator... Execution... returned 1
    ##notify { "MongoDB not yet inited (replset & auth admin) ! $mongodb_not_inited_generate_res": }
  
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
    command => "/bin/true ; if [ -f \"/etc/init.d/mongod\" ]; then /etc/init.d/mongod stop ; rm -f /var/lib/mongodb/mongod.lock ; fi ; \
        echo starting up after checking if needed ; \
        /usr/bin/mongo admin --quiet --eval \"db.getMongo()\" 2>/dev/null | grep \"couldn't connect\" && sudo -u $user nohup sh -c \"/usr/bin/mongod --pidfilepath /tmp/mongod_prestart.pid -f /etc/mongod_prestart.conf\" &> /var/log/mongodb/mongodb_prestart_nohup.log & \
        echo waiting to be up ; \
        sleep 5 ;
        res=\"ailed\" ; while [ \"$res\" != \"\" ] ; do echo sleep ; sleep 1 ; res=$(/usr/bin/mongo admin --quiet --eval \"db.getMongo()\" 2>/dev/null | grep \"ailed\") ; echo $res ; done ;
        echo creating user ; \
        res=eval /usr/bin/mongo admin --quiet --eval \"db.createUser({ user: \\\"${admin_user}\\\", pwd: \\\"${admin_password}\\\", \
        roles: [ { role: \\\"userAdminAnyDatabase\\\", db: \\\"admin\\\" }, { role: \\\"dbAdminAnyDatabase\\\", db: \\\"admin\\\" }, \
        { role: \\\"readWriteAnyDatabase\\\", db: \\\"admin\\\" }, { role: \\\"clusterAdmin\\\", db: \\\"admin\\\" }, \
        { role: \\\"root\\\", db: \\\"admin\\\" } ] })\" ; \
        echo res \"$res\" ; \
        /usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" || exit 1 ; \
        echo admin user created ; kill `cat /tmp/mongod_prestart.pid` ; rm -f /var/lib/mongodb/mongod.lock /tmp/mongod_prestart.pid ; echo success ; exit 0",
        # grep for auth failed and Failed to connect
        # kill `cat /tmp/mongod_prestart.pid` rather than /etc/init.d/mongod stop if consecutive "apply"s and better than ps -ef | grep \"mongod\" | awk '{print \$2}' | xargs kill which is hard to follow on
        ## /tmp/mongod_prestart.pid
        ##sudo -u $user nohup /usr/bin/mongod --smallfiles --auth --replSet $replset --dbpath /var/lib/mongodb --logpath=/var/log/mongodb/mongodb_prestart.log &> /var/log/mongodb/mongodb_prestart_nohup.log & \
        #/usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" 2>/dev/null | grep -v ailed && echo actually inited && kill `cat /tmp/mongod_prestart.pid` && echo killed mongodb && exit 0 ;
        #echo res \"$res\" ; \
        ##already_exists=\"\" ; echo \"$res\" | grep \"already exists\" && already_exists=\"already exists\" ; \
        #if [ \"$already_exists\" != \"\" ] ; then echo already exists ; kill `cat /tmp/mongod_prestart.pid` ; ps -ef | grep \"mongod\" | awk '{print \$2}' | xargs kill ; rm -f /var/lib/mongodb/mongod.lock /tmp/mongod_prestart.pid ; echo success ; exit 0 ; fi ; \ 
        #successful=\"\" ; echo \"$res\" | grep Successfully && successful=\"Successfully\" ; \
        #if [ \"$successful\" != \"\" ] ; then echo admin user created ; kill `cat /tmp/mongod_prestart.pid` ; ps -ef | grep \"mongod\" | awk '{print \$2}' | xargs kill ; rm -f /var/lib/mongodb/mongod.lock /tmp/mongod_prestart.pid ; echo success ; exit 0 ; fi ; \
        #echo failure && exit 1",
        #echo admin user created ; echo bb `ps -ef | grep \"mongod\" | grep -v \"sudo\" | grep -v \"sh\" | grep \"pidfilepath\" | grep -v \"grep\"` ; ps -ef | grep \"mongod\" | grep -v \"sudo\" | grep -v \"sh\" | grep \"pidfilepath\" | grep -v \"grep\" | awk '{print \$2}' ; rm -f /var/lib/mongodb/mongod.lock /tmp/mongod_prestart.pid ; echo success ; exit 0",
    ######tries => 10,
    ######try_sleep => 1,
    unless => "/usr/bin/mongo -p $admin_password -u $admin_user admin --quiet --eval \"db.getMongo()\" > /tmp/mongo_test ; cat /tmp/mongo_test | grep failed && exit 1 || exit 0", # rather than generate() which is executed on server side !
    logoutput => true,
    #timeout => 300,
    require => File['/etc/mongod_prestart.conf'],
  }
  
  ##} else {
  ##  notify { "MongoDB already inited (replset & auth admin) ! $mongodb_not_inited_generate_res": }
  ##}
  
  }
}
