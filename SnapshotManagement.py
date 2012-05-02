def createSnapshot(sessionObj, vmRef, ss_name):
        try:
                sessionObj.xenapi.VM.snapshot(vmRef, ss_name)
                return isValidSnapshot(sessionObj, vmRef, ss_name)
        except Exception, e:
		print "Create: err:", str(e)
                return False


def removeSnapshot(sessionObj, vmRef, ss_name):
        try:
		vdises = sessionObj.xenapi.VDI
        	vbdses = sessionObj.xenapi.VBD
                vmses = sessionObj.xenapi.VM
		vmObj = vmses.get_record(vmRef)
		valid = False

		if len(vmObj["snapshots"]) > 0:
			for snap in vmObj["snapshots"]:
				snapObj = vmses.get_record(snap)
				if snapObj["name_label"] == ss_name:
					vmses.destroy(snap)

					# remove Stale VDI routine here (because of a bug in the API)
        				for thisvbd in vmObj["VBDs"]:
				                thisvbdObj = vbdses.get_record(thisvbd)
				                if thisvbdObj["type"] == "Disk":
				                        thisvdiObj = vdises.get_record(thisvbdObj["VDI"])
				                        for vdiList in thisvdiObj["snapshots"]:
				                                thisVDIObj = vdises.get_record(vdiList)
				                                if len(thisVDIObj["VBDs"]) == 0 and thisVDIObj["snapshot_of"] != "OpaqueRef:NULL" and thisVDIObj["read_only"] == False:
			                                        	vdises.destroy(vdiList)
					# ------------------------------------------------------------
					

                status = isValidSnapshot(sessionObj, vmRef, ss_name)
		#print "Snapshot state: " , status
		if status == False:
			valid = True

		return valid

        except Exception, e:
                print str(e)
                return valid


def getSnapshotUuid(sessionObj, vmRef, ss_name):
        try:
                if isValidSnapshot(sessionObj, vmRef, ss_name) == True:
                        vmses = sessionObj.xenapi.VM
			vmObj = vmses.get_record(vmRef)
                	if len(vmObj["snapshots"]) > 0:
                        	for snap in vmObj["snapshots"]:
                                	snapObj = vmses.get_record(snap)
                                	if snapObj["name_label"] == ss_name and snapObj["is_a_snapshot"] == True:
                        			return snapObj["uuid"]
						break
                else:
                        return False
        except Exception, e:
                return False


def isValidSnapshot(sessionObj,vmRef, ss_name):
	valid = False
        try:
                vmses = sessionObj.xenapi.VM
	 	vmObj = vmses.get_record(vmRef)
                if len(vmObj["snapshots"]) > 0:
                        for snap in vmObj["snapshots"]:
                                snapObj = vmses.get_record(snap)
                                if snapObj["name_label"] == ss_name:     
					valid = True
					break
        except Exception, e:
		print "isValidSnapshot: ", str(e)
                valid = False
	return valid
