nagios-check_dellwarranty
=========================

Poll Dell SOAP service for service contract expiration dates.

Usage
-------
    check_dellwarranty.rb [options]
        -H, --hostname HOSTNAME          Hostname to get warranty status for. Uses SNMP
        -w, --warning                    Warning threshold for number of days
                                           remaining on contract (Default: 90)
        -c, --critical                   Critical threshold for number of days
                                           remaining on contract (Default: 30)
        -s, --servicetag                 ServiceTag ID to check
        -d, --debugging                  Enable debugging output
        -h, --help                       Display this screen

You must supply either a hostname or a service tag. If a hostname is supplied, this script will
poll OpenManage on the server via SNMP to retrieve the service tag.

Caveats
-------
* Change the hashbang line to point to your Ruby installation
* Only tested on REE 1.8.7
* You must install the 'snmp' Gem 

History
------------
### 0.4 (2012-08-29)
**Feature:** Add -v (verbose) option and make -d (debug) work better
**Fix:** Fix -w and -c params
### 0.3 (2012-08-29)
**Bugfix:** Issue #1 - Deal with instances where Dell doesn't pass back ServiceLevel codes and descriptions
### 0.2 (2012-08-28)
**Feature:** First publicly released version (That's a feature, right?!)
