def findHostIpaddr(session, host_ref):

	hostObj = session.xenapi.host.get_record(host_ref)

        if len(hostObj["PIFs"]) == 1:
                pifObj = session.xenapi.PIF.get_record(hostObj["PIFs"][0])
                return pifObj["IP"]
        else:
                foundPIF = False
                for pif in hostObj["PIFs"]:
                        multiPIFObj = session.xenapi.PIF.get_record(pif)
                        if multiPIFObj["management"] == False and multiPIFObj["currently_attached"] == True and len(multiPIFObj["IP"]) > 0:
                                foundPIF = True
                                return multiPIFObj["IP"]
                                break
