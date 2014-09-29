Puppet::Type.type(:mongodb_database).provide(:mongodb) do

  desc "Manages MongoDB database."

  defaultfor :kernel => 'Linux'

  commands :mongo => 'mongo'

  mk_resource_methods # creates getters & setters on top of @property_hash

  def block_until_mongodb(tries = 10)
    begin
      mongo('--quiet', '--eval', 'db.getMongo()') # and not mongo_command('db.getMongo()') else retries too much
    rescue => e
      debug('MongoDB server not ready, retrying')
      sleep 2
      if (tries -= 1) > 0
        retry
      else
        raise e
      end
    end
  end

  def create
    # merely creating a new collection in the new database to create it :
    mongo_command("db.getSiblingDB(\"#{@resource[:name]}\").dummyData.insert({\"created_by_puppet\": 1})")
    # NB. in MongoDB, there are no specific database (or collection) creation functions
    # an alternative would be to use "use db", but only by writing to shell (and not executing some js) :
    #self.class.mongo_command_stub("admin", @resource[:admin_user],@resource[:admin_password],["--shell"])
    #$stdout.write "use #{@resource[:name]}"
    #$stdout.write "db.dummyData.insert({\"created_by_puppet\": 1})"
    #$stdout.write "exit"
  end

  def destroy
    # connecting to admin db implies using getSiblingDB()
    mongo_command("db.getSiblingDB(\"#{@resource[:name]}\").dropDatabase()")
  end

  def exists?
    block_until_mongodb(@resource[:tries])
    mongo_command('db.getMongo().getDBNames()').chomp.split(",").include?(@resource[:name])
  end
  
  def mongo_command(command, host=nil, retries=0)
    Puppet.warning("mongodb0 c+r: " + command + " " + @resource.inspect)
    # always "admin" database (otherwise can't connect) ; implies using getSiblingDB() next
    self.class.mongo_command('admin',@resource[:admin_user],@resource[:admin_password],command,host,retries)
  end

  # NB. self here means static
  def self.mongo_command(db, admin_user, admin_password, command, host=nil, retries=0)
    mongo_command_stub(db, admin_user, admin_password, ['--eval',"printjson(#{command})"], host, retries)
  end
  def self.mongo_command_stub(db, admin_user, admin_password, cmdArgs, host=nil, retries=0)
    # Allow waiting for mongod to become ready
    # Wait for 2 seconds initially and double the delay at each retry
    wait = 2
    begin
      args = Array.new
      args << db # else "auth failed" if admin user
      args << '--quiet'
      args << ['-u',admin_user, '-p', admin_password] if admin_user
      args << ['--host',host] if host
      args << cmdArgs
      Puppet.warning("mongo: " + args.flatten.inspect)
      output = mongo(args.flatten)
      #Puppet.warning("output: " + output.inspect)
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
