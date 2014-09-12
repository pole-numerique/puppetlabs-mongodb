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
#Puppet.warning(@resource.parent.parent.instance_variables.map{|var| puts [var, @resource.parent.parent.instance_variable_get(var)].join(":")})
    # before MongoDB 2.6 :
    #mongo(@resource[:database], '--eval', "db.system.users.insert({user:\"#{@resource[:name]}\", pwd:\"#{@resource[:password_hash]}\", roles: #{@resource[:roles].inspect}})")
    # since MongoDB 2.6, users are stored in admin db and credentials and roles are more complex
    roleMaps = []
    @resource[:roles].each { |role| roleMaps << {"role"=>role,"db"=>@resource[:database]} }
    require 'json'
    mongo("admin", '--eval', "db.system.users.insert({\"_id\":\"#{@resource[:database]}.#{@resource[:name]}\", user:\"#{@resource[:name]}\", credentials:{\"MONGODB-CR\":\"#{@resource[:password_hash]}\"}, db:\"#{@resource[:database]}\", roles:#{roleMaps.to_json}})")
  end

  def destroy
    mongo(@resource[:database], '--quiet', '--eval', "db.removeUser(\"#{@resource[:name]}\")")
  end

  def exists?
    block_until_mongodb(@resource[:tries])
    mongo(@resource[:database], '--quiet', '--eval', "db.system.users.find({user:\"#{@resource[:name]}\"}).count()").strip.eql?('1')
  end

  def password_hash
    mongo(@resource[:database], '--quiet', '--eval', "db.system.users.findOne({user:\"#{@resource[:name]}\"})[\"pwd\"]").strip
  end

  def password_hash=(value)
    mongo(@resource[:database], '--quiet', '--eval', "db.system.users.update({user:\"#{@resource[:name]}\"}, { $set: {pwd:\"#{value}\"}})")
  end

  def roles
    mongo(@resource[:database], '--quiet', '--eval', "db.system.users.findOne({user:\"#{@resource[:name]}\"})[\"roles\"]").strip.split(",").sort
  end

  def roles=(value)
    mongo(@resource[:database], '--quiet', '--eval', "db.system.users.update({user:\"#{@resource[:name]}\"}, { $set: {roles: #{@resource[:roles].inspect}}})")
  end

end
