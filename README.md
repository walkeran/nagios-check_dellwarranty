nagios-check_dellwarranty
=========================

Poll Dell SOAP service for service contract expiration dates.

Usage
-------
    check_dellwarranty.rb [options]
        -H, --hostname HOSTNAME          Hostname to get warranty status for. Uses SNMP
        -s, --servicetag                 ServiceTag ID to check
        -C, --community <community>      SNMP Community to use when polling for service tag
            --snmpver <snmpver>          SNMP Version to use when polling for service tag
        -w, --warning WARNDAYS           Warning threshold for number of days
                                           remaining on contract (Default: 90)
        -c, --critical CRITDAYS          Critical threshold for number of days
                                           remaining on contract (Default: 30)
        -D, --distant                    Consider only the contract expiring in the
                                           most distant future
        -l, --link                       Include an HTML link to Dell's warranty page for
                                           this server
        -t, --timeout <seconds>          Seconds to wait before timing out, while connecting to
                                           Dell's API
        -v, --verbose                    Enable verbose output
        -d, --debugging                  Enable debugging output
        -h, --help                       Display this screen

You must supply either a hostname or a service tag. If a hostname is supplied, this script will
poll OpenManage on the server via SNMP to retrieve the service tag.

Caveats
-------
* Change the hashbang line to point to your Ruby installation
* Only tested on REE 1.8.7 (Feel free to let me know if this works in other envrionments)
* You must install the 'snmp' Gem (or have the snmp Ruby library available by some other means)

History
------------
### 1.0 (2014-07-28)
* **Fix:** Refactor to use new API instead of SOAP webservice (which Dell seemed to have broken)

### 0.7 (2013-11-16)
* **Feature:** Add -t (timeout) option, so user can specify number of seconds to try connecting to Dell's webservices
* **Bugfix:** Issue #2 - Timeout gracefully when Dell's webservices are unreachable. Now returns Unknown status instead of hanging

### 0.6 (2013-10-02)
* **Fix:** Fixed an edge case where Dell was returning empty entitlement blocks, and we weren't handling it nicely

### 0.5 (2012-09-30)
* **Feature:** Add -D (most distant future) option, to only consider the contract expiring in the most distant future
* **Feature:** Add -l (html link) option, to also include an HTML link to the Dell site with the warranty details
* **Fix:** Now supports snmp libs without needing rubygems

### 0.4 (2012-08-29)
* **Feature:** Add -v (verbose) option and make -d (debug) work better  
* **Fix:** Fix -w and -c params

### 0.3 (2012-08-29)
* **Bugfix:** Issue #1 - Deal with instances where Dell doesn't pass back ServiceLevel codes and descriptions

### 0.2 (2012-08-28)
* **Feature:** First publicly released version (That's a feature, right?!)
