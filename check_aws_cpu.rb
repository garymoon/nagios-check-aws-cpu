#!/usr/bin/env ruby
require 'rubygems'
require 'aws-sdk'
require 'optparse'
require 'time'

EXIT_CODES =
{
  :unknown => 3,
  :critical => 2,
  :warning => 1,
  :ok => 0
}

options =
{
  :groups => [],
  :timespan => (5*60),
  :lower => 0,
  :upper => 100,
  :instances => [],
  :debug => false,
  :stack => '',
  :tags => []
}

config = { :region => 'us-west-2' }

opt_parser = OptionParser.new do |opt|

  opt.on("-g","--groups group[,group]","which groups do you wish to report on?") do |groups|
    options[:groups] = groups.split(',')
  end

  opt.on("--stack stack","which stack do you wish to report on?") do |stack|
    options[:stack] = stack
  end

  opt.on("--tags tag,[tag]","which tag(s) do you wish to report on?") do |tags|
    options[:tags] = tags.split(',')
  end

  opt.on("-d","--debug","enable debug mode") do
    options[:debug] = true
  end

  opt.on("-i","--instances instance[,instance]","which instance(s) do you wish to report on?") do |instances|
    options[:instances] = instances.split(',')
  end

  opt.on("-r","--region region","which region do you wish to report on?") do |region|
    config[:region] = region
  end

  opt.on("-k","--key key","specify your AWS key ID") do |key|
    (config[:access_key_id] = key) unless key.empty?
  end

  opt.on("-s","--secret secret","specify your AWS secret") do |secret|
    (config[:secret_access_key] = secret) unless secret.empty?
  end

  opt.on("-u","--upper num","specify the upper bound on CPU consumption") do |upper|
    options[:upper] = Integer(upper) rescue 100
  end

  opt.on("-l","--lower num","specify the lower bound on CPU consumption") do |lower|
    options[:lower] = Integer(lower) rescue 0
  end

  opt.on("-t","--timespan mins","specify the the number of minutes over which the CPU conumption is averaged") do |mins|
    options[:timespan] = (Integer(mins) * 60)
  end

  opt.on("-h","--help","help") do
    puts opt_parser
    exit
  end
end

opt_parser.parse!

if (options[:debug])
  puts 'Options: '+options.inspect
  puts 'Config: '+config.inspect
end

raise OptionParser::MissingArgument, 'Missing "--lower" or "--upper"' if (options[:upper] == 100 and options[:lower] == 0)
raise OptionParser::MissingArgument, 'Missing "--stack" or "--tags"' if (options[:stack].empty? ^ options[:tags].empty?)
raise OptionParser::MissingArgument, 'Missing "--groups" or "--instances" or "--stack" & "--tags"' if (options[:groups].empty? and options[:instances].empty? and options[:stack].empty?)

AWS.config(config)

begin
  AWS.memoize do
    as = AWS::AutoScaling.new.client
    cw = AWS::CloudWatch.new.client
    stacks = AWS::CloudFormation.new.stacks
    options[:tags].each do |tag_name|
      options[:groups] << stacks[options[:stack]].resources[tag_name].physical_resource_id
    end
    if not (options[:groups].empty?)
      groups = as.describe_auto_scaling_groups({:auto_scaling_group_names => options[:groups]})[:auto_scaling_groups]
      groups.each { |group| group[:instances].each { |instance| options[:instances] << instance[:instance_id]} }
    end
    if (options[:instances].empty?)
      raise Exception, 'No instances to check'
    end
    if (options[:debug])
      puts 'Instances: '+options[:instances].inspect
    end
    out_of_bounds = []
    options[:instances].each do | instance|
      cw_options = 
      {
        :namespace   => "AWS/EC2",
        :dimensions  => [{:name=>"InstanceId",:value=>instance}],
        :statistics  => ["Average"],
        :metric_name => "CPUUtilization",
        :start_time  => (Time.now - options[:timespan]).iso8601,
        :end_time    => Time.now.iso8601,
        :period      => options[:timespan]
      }
      current_cpu = cw.get_metric_statistics(cw_options).data[:datapoints][0][:average]
      if (options[:debug])
        puts instance + ' CPU: ' + current_cpu.to_s
      end
      if ((current_cpu > options[:upper]) or (current_cpu < options[:lower]))
        out_of_bounds << instance
      end
    end
    if (!out_of_bounds.empty?)
      puts 'CRIT: ' + out_of_bounds.join(',') + ' out of bounds.'
      exit EXIT_CODES[:critical] unless options[:debug]
    end
  end
rescue SystemExit
  raise
# Yes I know how much this makes everyone want to club baby seals. If you can find another
# way to have Ruby display unexpected exceptions nicely in Nagios, please submit a PR.
rescue Exception => e
  puts 'CRIT: Unexpected error: ' + e.message + ' <' + e.backtrace[0] + '>'
  exit EXIT_CODES[:critical] 
end

puts 'OK: All instances are within the specified bounds.'
exit EXIT_CODES[:ok]
