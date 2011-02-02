/////////////////////////////////////////////////////////////////////////
//// Proxy Auto-Configuration (PAC) File for the E-Trade Split VPN
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
    
    //// If there is a port # for 10.x, it is routed through SSH forward
    //// in localhost to allow access of non std port
    if (isInNet(DestIP, "10.0.0.0", "255.0.0.0")) {
        if (shExpMatch(url, "*:*")) {
          return "PROXY localhost:16101";
        }
        return "DIRECT";
    }
    return "DIRECT";
}
