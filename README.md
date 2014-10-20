nagios-check-aws-cpu
====================

A nagios check for monitoring the CPU consumption of AWS instances using the CloudWatch API


Usage
-----
    Usage: check_aws_cpu [options]
        -g, --groups group[,group]       which groups do you wish to report on?
        --stack stack                which stack do you wish to report on?
        --tags tag,[tag]             which tag(s) do you wish to report on?
        -d    , --debug                      enable debug mode
        -i instance[,instance],          which instance(s) do you wish to report on?
          --instances
        -r, --region region              which region do you wish to report on?
        -k, --key key                    specify your AWS key ID
        -s, --secret secret              specify your AWS secret
        -u, --upper num                  specify the upper bound on CPU consumption
        -l, --lower num                      specify the lower bound on CPU consumption
        -t, --timespan mins              specify the the number of minutes over which the CPU conumption is averaged

Configuration
-------------
define command{
  command_name  check_aws_cpu
  command_line  $USER1$/check_aws_cpu.rb --stack '$ARG1$' --tags '$ARG2$' --key '$ARG3$' --secret '$ARG4$' --upper '$ARG5$' --lower '$ARG6$' --region '$ARG7$' --instances '$ARG8$' --timespan '$ARG9$' 
  }

define service{
  use                             generic-service 
  host_name                       aws
  service_description             WWWFleet CPU
  check_command                   check_aws_cpu!PROD!WWWFleet!<%= @aws_nagios_key %>!<%= @aws_nagios_secret %>!70!5!<%= @aws_region_code %>!!20!
  check_interval                  5
  notification_period             workhours
  first_notification_delay        30
}


Notes:
* The SDK will use IAM roles if you don't specify a key pair
* The default region is us-west-2 (Oregon)