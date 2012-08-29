#!/opt/ruby/bin/ruby

##
## Author:    Andy Walker <andy@fbsdata.com>
## Copyright: Copyright (c) 2012 FBS Datasystems
## License:   GNU General Public License
##
##    This program is free software: you can redistribute it and/or modify
##    it under the terms of the GNU General Public License as published by
##    the Free Software Foundation, either version 3 of the License, or
##    (at your option) any later version.
##
##    This program is distributed in the hope that it will be useful,
##    but WITHOUT ANY WARRANTY; without even the implied warranty of
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##    GNU General Public License for more details.
##
##    You should have received a copy of the GNU General Public License
##    along with this program.  If not, see <http://www.gnu.org/licenses/>.
##

begin
  require 'date'
  require 'optparse'
  require 'soap/wsdlDriver'
rescue Exception => e
  puts "You need the date, optparse, and soap libraries installed."
  puts e.message
  exit 2
end

WSDL_URL = 'http://xserv.dell.com/services/assetservice.asmx?WSDL'
GUID     = '11111111-1111-1111-1111-111111111111'
App      = 'check_dellwarranty.rb'

PLUGIN_VERSION  = '0.2'

options = {}

optparse = OptionParser.new do|opts|
  opts.banner = "Usage: #{App} -H <hostname> | -s <servicetag> [options]"

  options[:hostname] = ""
  opts.on( '-H', '--hostname <hostname>', 'Hostname to get warranty status for. Uses SNMP' ) do |hostname|
    options[:hostname] = hostname
  end

  options[:serial] = ""
  opts.on( '-s', '--servicetag <servicetag>', 'ServiceTag ID to check' ) do |serial|
    options[:serial] = serial
  end

  options[:snmp_comm] = 'public'
  opts.on( '-C', '--community <community>', 'SNMP Community to use when polling for service tag') do |comm|
    options[:snmp_comm] = comm
  end

  options[:snmp_version] = :SNMPv2c
  opts.on( '-v', '--snmpver <snmpver>', 'SNMP Version to use when polling for service tag') do |ver|
    case ver
    when '1'
      options[:snmp_ver] = :SNMPv1
    when '2c'
      options[:snmp_var] = :SNMPv2c
    else
      puts "That SNMP version is not supported. Use 1 or 2c only"
      exit 2
    end
  end

  options[:warn_days] = 90
  opts.on( '-w', '--warning', 'Warning threshold for number of days remaining on contract (Default: 90)' ) do |w|
    options[:warn_days] = w
  end

  options[:crit_days] = 30
  opts.on( '-c', '--critical', 'Critical threshold for number of days remaining on contract (Default: 30)' ) do |c|
    options[:crit_days] = c
  end

  options[:debug] = false
  opts.on( '-d', '--debugging', 'Enable debugging output' ) do |d|
    options[:debug] = d
  end

  opts.on_tail( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit 2
  end
end

begin
  optparse.parse!
rescue StandardError => e
  puts "Error parsing command line arguments."
  puts e.message
  puts optparse
  exit 2
end

class ServiceLevel
  attr_accessor :serviceLevelDescription, :serviceLevelCode

  def endDate
    @endDate
  end

  def endDate=(endDate)
    if endDate.is_a?(DateTime)
      @endDate = endDate
    elsif endDate.is_a?(String)
      @endDate = DateTime.parse(endDate)
    else
      puts "endDate doesn't accept " + endDate.class.to_s + " types!"
      exit 2
    end
  end

  def <=>(other)
    self.endDate <=> other.endDate
  end

  def to_s
    @serviceLevelDescription + ", " + @serviceLevelCode + ", " + @endDate.strftime('%Y/%m/%d')
  end
end

class DellEntitlements
  def initialize
    @entitlements = Array.new
    @servicelevels = Hash.new
  end

  def servicelevels
    @servicelevels
  end

  def entitlements
    @entitlements
  end

  def add(ent)
    @entitlements.push ent
    if @servicelevels[ent.serviceLevelCode] != nil
      @servicelevels[ent.serviceLevelCode].endDate = [ @servicelevels[ent.serviceLevelCode].endDate, ent.endDate ].max
      
    else
      servicelevel = ServiceLevel.new
      servicelevel.endDate = ent.endDate
      servicelevel.serviceLevelDescription = ent.serviceLevelDescription
      servicelevel.serviceLevelCode = ent.serviceLevelCode

      @servicelevels[ent.serviceLevelCode] = servicelevel
    end
  end
end

class DellEntitlement < ServiceLevel
  attr_accessor :entitlementType,
    :provider

  def initialize(args)
    @entitlementType         = args[:type]
    @serviceLevelDescription = args[:desc] if args[:desc]
    @provider                = args[:prov] if args[:prov]
    @serviceLevelCode        = args[:code] if args[:code]
    self.startDate           = args[:startDate]
    self.endDate             = args[:endDate]
  end

  def startDate
    @startDate
  end

  def startDate=(startDate)
    if startDate.is_a?(DateTime)
      @startDate = startDate
    elsif startDate.is_a?(String)
      @startDate = DateTime.parse(startDate)
    else
      puts "startDate doesn't accept " + startDate.class.to_s + " types!"
      exit 2
    end
  end
end

def suppress_warning
  back = $VERBOSE
  $VERBOSE = nil
  begin
    yield
  ensure
    $VERBOSE = back
  end
end

def get_snmp_serial ( args )
  begin
    require 'rubygems'
    require 'snmp'
  rescue Exception => e
    puts "You need the snmp gem installed."
    puts e.message
    exit 2
  end

  serial = ''
  SNMP::Manager.open(:host => args[:hostname], :community => args[:community], :version => args[:version]) do |manager|
    val = manager.get_value('1.3.6.1.4.1.674.10892.1.300.10.1.11.1')
    serial = val.split[0]
  end

  serial
end

def get_dell_warranty(serial)
  ents = DellEntitlements.new

  driver = suppress_warning { SOAP::WSDLDriverFactory.new(WSDL_URL).create_rpc_driver }
  result = driver.GetAssetInformation(:guid => GUID, :applicationName => App, :serviceTags => serial)

  result.getAssetInformationResult.asset.entitlements.entitlementData.each do | ent | 
    entargs = Hash.new

    entargs[:type]      = ent.entitlementType
    entargs[:startDate] = ent.startDate
    entargs[:endDate]   = ent.endDate
    entargs[:prov] = ent.provider                if defined? ent.provider
    entargs[:desc] = ent.serviceLevelDescription if defined? ent.serviceLevelDescription
    entargs[:code] = ent.serviceLevelCode        if defined? ent.serviceLevelCode

    ents.add DellEntitlement.new(entargs)
  end

  ents
end

entitlements = DellEntitlements.new
serial       = ''
now          = DateTime.now
errlevel     = 0
count        = 0
expiring     = 0
nextexpire   = nil

errlevels = { 0 => "OK",
              1 => "WARNING",
              2 => "CRITICAL",
              3 => "UNKNOWN"
            }

if options[:hostname].length > 0
  puts "Hostname: #{options[:hostname]}" if options[:debug]
  serial = get_snmp_serial( :hostname => options[:hostname],
                            :community => options[:snmp_comm],
                            :version => options[:snmp_ver] )
elsif options[:serial].length > 0
  serial = options[:serial]
else
  puts "ERROR: Must supply either a hostname or servicetag!"
  puts optparse
  exit 2
end

puts "Serial: #{serial}" if options[:debug]
entitlements = get_dell_warranty(serial)

entitlements.servicelevels.sort_by { |k,v| v }.each do |k,sl|
  endDate  = sl.endDate
  desc     = sl.serviceLevelDescription
  daysleft = (endDate - now).round
  count += 1

  ## TODO: Condense the following logic a little bit. Also, decide what to do when daysleft is
  ##   a large negative number (been expired for 2 weeks? Probably not going to renew)

  if daysleft >= 0
    nextexpire = (nextexpire == nil) ? daysleft : [nextexpire,daysleft].min
  end

  if daysleft < options[:crit_days]
    puts "CRITICAL: '#{desc}' support ends in #{daysleft} days"
    expiring += 1
    errlevel = [ errlevel, 2 ].max
  elsif daysleft < options[:warn_days]
    puts "WARNING: '#{desc}' support ends in #{daysleft} days"
    expiring += 1
    errlevel = [ errlevel, 1 ].max
  elsif options[:debug]
    puts "OK: '#{desc}' support ends in #{daysleft} days"
  end
end

puts "#{errlevels[errlevel]}: #{expiring} of #{count} service contracts are expiring (Next: #{nextexpire} days)"

exit errlevel
