Puppet::Type.type(:mongodb_user).provide(:mongodb) do

  desc "Manage users for a MongoDB database."

  defaultfor :kernel => 'Linux'

  commands :mongo => 'mongo'

  confine :true =>
    begin
      require 'json'
      true
    rescue LoadError
      false
    end

  mk_resource_methods # creates getters & setters on top of @property_hash

  def block_until_mongodb(tries = 10)
    begin
      mongo('--quiet', '--eval', 'db.getMongo()') # and not mongo_command('db.getMongo()') else retries too much
    rescue
      debug('MongoDB server not ready, retrying')
      sleep 2
      retry unless (tries -= 1) <= 0
    end
  end

  def create
    # TODO switch according to MongoDB version :
    #Puppet.warning(@resource.parent.parent.instance_variables.map{|var| puts [var, @resource.parent.parent.instance_variable_get(var)].join(":")})
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--eval', "db.system.users.insert({user:\"#{@resource[:name]}\", pwd:\"#{@resource[:password_hash]}\", roles: #{@resource[:roles].inspect}})")
    # since MongoDB 2.6, users are stored in admin db and credentials and roles are more complex :
    roleMaps = []
    @resource[:roles].each { |role| roleMaps << {"role"=>role,"db"=>@resource[:database]} }
    ##require 'json'
    if @resource[:password]
      # required in 2.6 for auth'd relpset & to create first user
      mongo_command("db.getSiblingDB(\"#{@resource[:database]}\").createUser({user:\"#{@resource[:name]}\", pwd:\"#{@resource[:password]}\", roles:#{roleMaps.to_json}})")
    else
      # allows not knowing plain text password but doesn't work in 2.6 to create first user nor in replset
      mongo_command("db.system.users.insert({\"_id\":\"#{@resource[:database]}.#{@resource[:name]}\", user:\"#{@resource[:name]}\", credentials:{\"MONGODB-CR\":\"#{@resource[:password_hash]}\"}, db:\"#{@resource[:database]}\", roles:#{roleMaps.to_json}})")
    end
  end

  def destroy
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.removeUser(\"#{@resource[:name]}\")")
    # since MongoDB 2.6, users are stored in admin db and removeUser is deprecated :
    mongo_command("db.getSiblingDB(\"#{@resource[:database]}\").dropUser(\"#{@resource[:name]}\")")
  end

  def exists?
    block_until_mongodb(@resource[:tries])
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.find({user:\"#{@resource[:name]}\"}).count()").strip.eql?('1')
    # since MongoDB 2.6, users are stored in admin db :
    output = mongo_command("db.system.users.find({_id:\"#{@resource[:database]}.#{@resource[:name]}\"}).count()")
    Puppet.warning("exists: '" + output + "'");
    output.is_a?(String) and output.strip.eql?('1') # not a string but {} if no user yet in 2.6 replset
  end

  def password_hash
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.findOne({user:\"#{@resource[:name]}\"})[\"pwd\"]").strip
    # since MongoDB 2.6, users are stored in admin db :
    mongo_command("db.system.users.findOne({_id:\"#{@resource[:database]}.#{@resource[:name]}\"})[\"credentials\"][\"MONGODB-CR\"]").strip.delete('\"')
  end

  def password_hash=(value)
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.update({user:\"#{@resource[:name]}\"}, { $set: {pwd:\"#{value}\"}})")
    # since MongoDB 2.6, users are stored in admin db, and the above lines don't work in 2.6 in replset :
    if @resource[:password]
      mongo_command("db.getSiblingDB(\"#{@resource[:database]}\").updateUser(\"#{@resource[:name]}\", { pwd: \"#{@resource[:password]}\" })")
    elsif @resource[:password_hash]
      mongo_command("db.system.users.update({_id:\"#{@resource[:database]}.#{@resource[:name]}\"}, { $set: {credentials:{\"MONGODB-CR\":\"#{value}\"}}})")
    else
      raise Puppet::Error, "Missing password (or if not on MongoDB 2.6 password_hash) property"
    end
  end

  def roles
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.findOne({user:\"#{@resource[:name]}\"})[\"roles\"]").strip.split(",").sort
    # since MongoDB 2.6, users are stored in admin db : TODO rather on roles.db, filter out false matches, map to array, or even ::db.roles to map
    rolesString = mongo_command("db.system.users.findOne({_id:\"#{@resource[:database]}.#{@resource[:name]}\"})[\"roles\"]")
    # Dirty hack to remove JavaScript objects
    rolesString.gsub!(/ISODate\((.+?)\)/, '\1 ')
    rolesString.gsub!(/Timestamp\((.+?)\)/, '[\1]')

    #Hack to avoid non-json empty sets
    ##output = "{}" if output == "null\n" or output == "0\n" # this last one being when no user yet in 2.6 (meaning no system.users collection in admin db yet)

    roleHashes = JSON.parse(rolesString)
    roles = []
    roleHashes.each { |roleHash| roles << roleHash['role'] }
    Puppet.warning("gotten roles: " + roles.sort.inspect)
    roles.sort
  end

  def roles=(value)
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.update({user:\"#{@resource[:name]}\"}, { $set: {roles: #{@resource[:roles].inspect}}})")
    # since MongoDB 2.6, users are stored in admin db and credentials and roles are more complex :
    roleMaps = []
    @resource[:roles].each { |role| roleMaps << {"role"=>role,"db"=>@resource[:database]} }
    ##require 'json'
    if @resource[:password]
      # required in 2.6 for auth'd relpset & to create first user
      mongo_command("db.getSiblingDB(\"#{@resource[:database]}\").updateUser(\"#{@resource[:name]}\", {roles:#{roleMaps.to_json}})") # avoid setting optional password, too much here
    else
      # allows not knowing plain text password but doesn't work in 2.6 in replset
      mongo_command("db.system.users.update({_id:\"#{@resource[:database]}.#{@resource[:name]}\"}, { $set: {roles: #{roleMaps.to_json}}})")
    end
  end


  def mongo_command(command, host=nil, retries=0)
    Puppet.warning("mongodb0 c+r+f+h: " + command + " " + @resource.inspect)
    # always "admin" database (otherwise can't connect, and pretty logical for user admin anyway)
    self.class.mongo_command('admin', @resource[:admin_user], @resource[:admin_password], command, host, retries)
  end

  # NB. self here means static
  def self.mongo_command(db, admin_user, admin_password, command, host=nil, retries=0)
    # Allow waiting for mongod to become ready
    # Wait for 2 seconds initially and double the delay at each retry
    wait = 2
    begin
      args = Array.new
      args << db
      args << '--quiet'
      args << ['-u',admin_user, '-p', admin_password] if admin_user
      args << ['--host',host] if host
      args << ['--eval',"printjson(#{command})"]
      Puppet.warning("mongo: " + args.flatten.inspect)
      output = mongo(args.flatten)
      Puppet.warning("output: " + output.inspect)
    rescue Puppet::ExecutionFailure => e
      if e =~ /Error: couldn't connect to server/ and wait <= 2**max_wait
        info("Waiting #{wait} seconds for mongod to become available")
        sleep wait
        wait *= 2
        retry
      else
        raise
      end
    end

    # Dirty hack to remove JavaScript objects
    ##output.gsub!(/ISODate\((.+?)\)/, '\1 ')
    ##output.gsub!(/Timestamp\((.+?)\)/, '[\1]')

    #Hack to avoid non-json empty sets
    ##output = "{}" if output == "null\n" or output == "0\n" # this last one being when no user yet in 2.6 (meaning no system.users collection in admin db yet)

    ##JSON.parse(output)
    output
  end
  
end
