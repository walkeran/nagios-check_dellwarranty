#!/opt/ruby/bin/ruby

require 'date'
require 'optparse'
require 'soap/wsdlDriver'

WSDL_URL = 'http://xserv.dell.com/services/assetservice.asmx?WSDL'
GUID     = '11111111-1111-1111-1111-111111111111'
App      = 'check_dellservice'

options = {}

optparse = OptionParser.new do|opts|
  opts.banner = "Usage: check_dellwarranty.rb [options]"

  options[:hostname] = ""
  opts.on( '-H', '--hostname HOSTNAME', 'Hostname to get warranty status for. Uses SNMP' ) do |hostname|
    options[:hostname] = hostname
  end

  options[:warn_days] = 90
  opts.on( '-w', '--warning', 'Warning threshold for number of days remaining on contract (Default: 90)' ) do |w|
    options[:warn_days] = w
  end

  options[:crit_days] = 30
  opts.on( '-c', '--critical', 'Critical threshold for number of days remaining on contract (Default: 30)' ) do |c|
    options[:crit_days] = c
  end

  options[:serial] = ""
  opts.on( '-s', '--servicetag', 'ServiceTag ID to check' ) do |serial|
    options[:serial] = serial
  end

  options[:debug] = false
  opts.on( '-d', '--debugging', 'Enable debugging output' ) do |d|
    options[:debug] = d
  end

  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end

optparse.parse!

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

  def initialize(type,desc,prov,code,startDate,endDate)
    @entitlementType = type
    @serviceLevelDescription = desc
    @provider = prov
    @serviceLevelCode = code
    self.startDate = startDate
    self.endDate = endDate
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

def get_snmp_serial(hostname)
  require 'rubygems'
  require 'snmp'

  serial = ''
  SNMP::Manager.open(:host => hostname) do |manager|
    response = manager.get('1.3.6.1.4.1.674.10892.1.300.10.1.11.1')
    response.each_varbind { |vb| serial = vb.value.to_s }
  end

  serial
end

def get_dell_warranty(serial)
  ents = DellEntitlements.new

  driver = suppress_warning { SOAP::WSDLDriverFactory.new(WSDL_URL).create_rpc_driver }
  result = driver.GetAssetInformation(:guid => GUID, :applicationName => App, :serviceTags => serial)

  result.getAssetInformationResult.asset.entitlements.entitlementData.each do | ent | 
      ents.add DellEntitlement.new(
        ent.entitlementType,
        ent.serviceLevelDescription,
        ent.provider,
        ent.serviceLevelCode,
        ent.startDate,
        ent.endDate
      )
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
  serial = get_snmp_serial(options[:hostname])
elsif options[:serial].length > 0
  serial = options[:serial]
else
  puts "ERROR: Must supply either a hostname or servicetag!"
  exit
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