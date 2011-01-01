/////////////////////////////////////////////////////////////////////////
//// Proxy Auto-Configuration (PAC) File for the E-Trade Environment ////
//// V8.87 Security Engineering CR124846  11/10/09                   ////
/////////////////////////////////////////////////////////////////////////
function FindProxyForURL(url, host) {
    /*global dnsResolve, isInNet, isResolvable, myIpAddress, shExpMatch */
    var SrcIP = myIpAddress();
    var DestIP;

    ///////////////////// Proxy Bypass Section ////////////////////
    /// If a destination is unresolveable, check it only once,
    /// and don't send it to the proxy.  Fail direct.
    if (!isResolvable(host)) {
        return "DIRECT";
    }
    /// Now that we are this far, we know we have a resolveable 
    /// destination.  For IP range comparisons, do only ONE dnsResolve,
    /// and store it in the DestIP variable for multiple fast comparisons
    DestIP = dnsResolve(host);
    
    //// For private IP range, goes direct
    if (isInNet(DestIP, "10.0.0.0", "255.0.0.0") ||
        isInNet(DestIP, "192.168.0.0", "255.255.0.0") ||
        isInNet(DestIP, "127.0.0.0", "255.0.0.0")) {
        return "DIRECT";
    }

    //// Otherwise, go through the proxy
    return "PROXY lxp6d199m0.etrade.com:6100";
}
