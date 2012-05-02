#!/usr/bin/env python

import XenAPI
import sys
import time
from HostIP import findHostIpaddr
from SnapshotManagement import *

def main (session):
	snapshot_name = "snap1_XenVmConverter"
	DeletedVM = False				

	try:
		vmRef = session.xenapi.VM.get_by_name_label(vm_name)
		DeletedVM = removeSnapshot(session, vmRef[0], snapshot_name)
	except Exception, e:
		print "Remove error: ", str(e)
		DeletedVM = False				

	sys.stdout.write(str(DeletedVM) + "\n")
	session.xenapi.session.logout()



if __name__ == "__main__":
    if len(sys.argv) <> 5:
        print "Usage:"
        print sys.argv[0], " <url> <username> <password> <vm name>"
        sys.exit(1)
    url = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]
    vm_name = sys.argv[4]
    # First acquire a valid session by logging in:
    session = XenAPI.Session(url)
    session.xenapi.login_with_password(username, password)
    try:
        main(session)
    except Exception, e:
        print str(e)
        raise
