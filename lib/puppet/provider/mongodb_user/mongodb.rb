Puppet::Type.type(:mongodb_user).provide(:mongodb) do

  desc "Manage users for a MongoDB database."

  defaultfor :kernel => 'Linux'

  commands :mongo => 'mongo'

  def block_until_mongodb(tries = 10)
    begin
      mongo('--quiet', '--eval', 'db.getMongo()')
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
    require 'json'
    mongo("admin", '--eval', "db.system.users.insert({\"_id\":\"#{@resource[:database]}.#{@resource[:name]}\", user:\"#{@resource[:name]}\", credentials:{\"MONGODB-CR\":\"#{@resource[:password_hash]}\"}, db:\"#{@resource[:database]}\", roles:#{roleMaps.to_json}})")
  end

  def destroy
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.removeUser(\"#{@resource[:name]}\")")
    # since MongoDB 2.6, users are stored in admin db and removeUser is deprecated :
    mongo("admin", '--quiet', '--eval', "db.dropUser(\"#{@resource[:name]}\")")
  end

  def exists?
    block_until_mongodb(@resource[:tries])
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.find({user:\"#{@resource[:name]}\"}).count()").strip.eql?('1')
    # TODO since MongoDB 2.6, users are stored in admin db : TODO $elemMatch on user & roles.db
    mongo("admin", '--quiet', '--eval', "db.system.users.find({user:\"#{@resource[:name]}\"}).count()").strip.eql?('1')
  end

  def password_hash
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.findOne({user:\"#{@resource[:name]}\"})[\"pwd\"]").strip
    # since MongoDB 2.6, users are stored in admin db :
    mongo("admin", '--quiet', '--eval', "db.system.users.findOne({user:\"#{@resource[:name]}\"})[\"credentials\"][\"MONGODB-CR\"]").strip
  end

  def password_hash=(value)
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.update({user:\"#{@resource[:name]}\"}, { $set: {pwd:\"#{value}\"}})")
    # since MongoDB 2.6, users are stored in admin db :
    mongo("admin", '--quiet', '--eval', "db.system.users.update({user:\"#{@resource[:name]}\"}, { $set: {credentials:{\"MONGODB-CR\":\"#{value}\"}}})")
  end

  def roles
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.findOne({user:\"#{@resource[:name]}\"})[\"roles\"]").strip.split(",").sort
    # TODO since MongoDB 2.6, users are stored in admin db : TODO rather on roles.db, filter out false matches, map to array, or even ::db.roles to map
    mongo("admin", '--quiet', '--eval', "db.system.users.findOne({user:\"#{@resource[:name]}\"})[\"roles\"]").strip.split(",").sort
  end

  def roles=(value)
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--quiet', '--eval', "db.system.users.update({user:\"#{@resource[:name]}\"}, { $set: {roles: #{@resource[:roles].inspect}}})")
    # since MongoDB 2.6, users are stored in admin db and credentials and roles are more complex :
    roleMaps = []
    @resource[:roles].each { |role| roleMaps << {"role"=>role,"db"=>@resource[:database]} }
    require 'json'
    # TODO or on \"_id\":\"#{@resource[:database]}.#{@resource[:name]}\" instead of user:\"#{@resource[:name]}\"} ?
    mongo("admin", '--quiet', '--eval', "db.system.users.update({user:\"#{@resource[:name]}\"}, { $set: {roles: #{roleMaps.to_json}}})")
  end

end
