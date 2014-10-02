#
# Author: François Charlier <francois.charlier@enovance.com>
#

Puppet::Type.type(:mongodb_replset).provide(:mongo) do

  desc "Manage hosts members for a replicaset."

  commands :mongo => 'mongo'

  confine :true =>
    begin
      require 'json'
      true
    rescue LoadError
      false
    end

  mk_resource_methods

  def initialize(resource={})
    super(resource)
    Puppet.warning("initialize")
    @property_flush = {}
  end

  def members=(hosts)
    Puppet.warning("members=(hosts)")
    @property_flush[:members] = hosts
  end

  def self.instances
    Puppet.warning("self.instances...")
    # can't without credentials, rather in prefetch
    # as at http://www.masterzen.fr/2011/11/02/puppet-extension-point-part-2/
    #instance = get_replset_properties
    #if instance
      # There can only be one replset per node
    #  [new(instance)]
    #else
    #  []
    #end
  end

  def self.prefetch(resources)
    Puppet.warning("self.prefetch resources... " + resources.inspect)
    if resources.length > 1
      raise Puppet::Error, "There can be at most one replset per node but there are: " + resources.inspect
    end
    resources.each do |name, resource|
      #Puppet.warning(resource.provider.inspect)
      # there can be only one replset per node :
      #if not resource.provider or resource.provider.name = name # KO
        instanceProps = get_replset_properties(resource)
        resource.provider = new(instanceProps)
      #end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.warning("create")
    @property_flush[:ensure] = :present
    @property_flush[:members] = resource.should(:members)
    #@property_flush[:user_admin] = resource.should(:user_admin)
    #@property_flush[:user_password] = resource.should(:user_password)
  end

  def destroy
    @property_flush[:ensure] = :absent
  end

  def flush
    Puppet.warning("flush0:")
    ##Puppet.warning(@property_hash.inspect)
    set_members
    Puppet.warning("flush1:")
    @property_hash = self.class.get_replset_properties(resource)
    Puppet.warning("flush2: " + @property_hash.inspect)
  end

  private

  def db_ismaster(host)
    mongo_command("db.isMaster()", host)
  end

  def rs_initiate(conf, master)
    Puppet.warning("rs_initiate: c+m " + conf.inspect + " " + master)
    return mongo_command("rs.initiate(#{conf})", master)
  end

  def rs_status(host)
    mongo_command("rs.status()", host)
  end

  def rs_add(host, master)
    mongo_command("rs.add(\"#{host}\")", master)
  end

  def rs_remove(host, master)
    mongo_command("rs.remove(\"#{host}\")", master)
  end

  def master_host(hosts)
    hosts.each do |host|
      status = db_ismaster(host)
      Puppet.warning("db_ismaster " + host + " " + status.inspect)
      if status.has_key?('primary')
        return status['primary']
      end
    end
    false
  end

  def self.get_replset_properties(resource) # needs resource for conf ex. admin_user ! # and not self else can't use conf ex. admin_user !
    output = mongo_command('admin','rs.conf()',resource[:admin_user],resource[:admin_password])
    Puppet.warning("get_replset_properties " + output.inspect)
    if output['members']
      members = output['members'].collect do |val|
        val['host']
      end
      props = {
        :name     => output['_id'],
        :ensure   => :present,
        :members  => members,
        :provider => :mongo,
      }
    else
      props = nil
    end
    Puppet.warning("MongoDB replset properties: #{props.inspect}")
    props
  end

  def alive_members(hosts)
    hosts.select do |host|
      begin
        Puppet.debug "Checking replicaset member #{host} ..."
        status = rs_status(host)
        if status.has_key?('errmsg') and status['errmsg'] == 'not running with --replSet'
          raise Puppet::Error, "Can't configure replicaset #{self.name}, host #{host} is not supposed to be part of a replicaset."
        end
        if status.has_key?('set')
          if status['set'] != self.name
            raise Puppet::Error, "Can't configure replicaset #{self.name}, host #{host} is already part of another replicaset."
          end

          # This node is alive and supposed to be a member of our set
          Puppet.debug "Host #{self.name} is available for replset #{status['set']}"
          true
        elsif status.has_key?('info')
          Puppet.debug "Host #{self.name} is alive but unconfigured: #{status['info']}"
          true
        end
      rescue Puppet::ExecutionFailure
        Puppet.warning "Can't connect to replicaset member #{host}."

        false
      end
    end
  end
  
  def set_members
    Puppet.warning("set_members r+f+h: "+ @resource.inspect + " " + @property_flush.inspect + " " + @property_hash.inspect)
    if @property_flush[:ensure] == :absent
      # TODO: I don't know how to remove a node from a replset; unimplemented
      #Puppet.debug "Removing all members from replset #{self.name}"
      #@property_hash[:members].collect do |member|
      #  rs_remove(member, master_host(@property_hash[:members]))
      #end
      return
    end

    if @property_flush[:members] and ! @property_flush[:members].empty?
      Puppet.warning("set_members2 :")
      # Find the alive members so we don't try to add dead members to the replset
      alive_hosts = alive_members(@property_flush[:members])
      dead_hosts  = @property_flush[:members] - alive_hosts
      raise Puppet::Error, "Can't connect to any member of replicaset #{self.name}." if alive_hosts.empty?
      ##raise Puppet::Error, "There are some dead hosts in replicaset #{self.name} : #{dead_hosts.inspect}, aborting ; check they are up then retry." if not dead_hosts.empty?
      Puppet.debug "Alive members: #{alive_hosts.inspect}"
      Puppet.debug "Dead members: #{dead_hosts.inspect}" unless dead_hosts.empty?
    else
      alive_hosts = []
    end

    if @property_flush[:ensure] == :present and @property_hash[:ensure] != :present
      Puppet.debug "Initializing the replset #{self.name}"

      # Create a replset configuration
      hostconf = alive_hosts.each_with_index.map do |host,id|
        "{ _id: #{id}, host: \"#{host}\" }"
      end.join(',')
      conf = "{ _id: \"#{self.name}\", members: [ #{hostconf} ] }"

      # Set replset members with the first host as the master
      master = alive_hosts[0]
      output = mongo_command("rs.initiate()", master, 20) # 20 retries until it is available
      if output['ok'] == 0
        raise Puppet::Error, "rs.initiate() failed for replicaset #{self.name}: #{output['errmsg']}"
      end
      isFirst = true;
      alive_hosts.each_with_index.map do |host,id|
        if isFirst
          Puppet.warning("isFirst: " +  host)
          isFirst = false
        else
          Puppet.warning("add: " +  host)
          output = mongo_command("rs.add(\"#{host}\")", master)
          if output['ok'] == 0
            raise Puppet::Error, "rs.add() failed for replicaset #{self.name}: #{output['errmsg']}"
          end
        end
      end
      
    
    else
      # Add members to an existing replset
      alive_hosts = alive_members(@property_hash[:members]) # otherwise empty if based on @property_flush
      Puppet.warning("set_members existing alive_hosts: " + alive_hosts.inspect)
      if master = master_host(alive_hosts) # master is in existing @property_hash and not new @property_flush
        current_hosts = db_ismaster(master)['hosts']
        newhosts = alive_hosts - current_hosts
        Puppet.warning("set_members m+c+n: " + master + " " + current_hosts.inspect + " " + newhosts.inspect)
        newhosts.each do |host|
          output = rs_add(host, master)
          if output['ok'] == 0
            raise Puppet::Error, "rs.add() failed to add host to replicaset #{self.name}: #{output['errmsg']}"
          end
        end
      else
        raise Puppet::Error, "Can't find master host for replicaset #{self.name}."
      end
    end
  end

  def mongo_command(command, host, retries=4)
    # always "admin" database (otherwise can't connect)
    self.class.mongo_command('admin',command,@resource[:admin_user],@resource[:admin_password],host,retries)
  end

  def self.mongo_command(db, command, admin_user, admin_password, host=nil, retries=4)
    # Allow waiting for mongod to become ready
    # Wait for 2 seconds initially and double the delay at each retry
    wait = 2
    begin
      Puppet.warning('mongo_command : ' + command)
      args = Array.new
      args << db # else "auth failed" if admin user
      args << '--quiet'
      args << ['--host',host] if host
      args << ['-u',admin_user, '-p', admin_password] if admin_user
      args << ['--eval',"printjson(#{command})"]
      Puppet.warning("mongo: " + args.flatten.inspect)
      output = mongo(args.flatten)
      Puppet.warning("output: " + output)
    rescue Puppet::ExecutionFailure => e
      if e =~ /Error: couldn't connect to server/ and wait <= 2**max_wait
        info("Waiting #{wait} seconds for mongod to become available")
        sleep wait
        wait *= 2
        retry
      else
        Puppet.warning("output: " + output)
        raise
      end
    rescue Mongo::ConnectionError => e
      Puppet.warning('connection error : ' + e);
      if admin_user
        Puppet.warning('trying again without credentials (may be a new replset member without any...)');
        mongo_command(db, command, nil, nil, host)
      else
        raise
      end
    end

    # Dirty hack to remove JavaScript objects
    output.gsub!(/ISODate\((.+?)\)/, '\1 ')
    output.gsub!(/Timestamp\((.+?)\)/, '[\1]')

    #Hack to avoid non-json empty sets
    output = "{}" if output == "null\n"

    JSON.parse(output)
  end

end
