function FindProxyForURL(url, host) {

  if (isInNet(host, "10.0.0.0", "255.255.255.0")) {
    return "DIRECT";
  }
  if (
    isPlainHostName(host) ||
    dnsDomainIs(host, ".apt.net")
  ) {
    return "DIRECT";
  }
  return "PROXY 10.0.0.226:8888; PROXY 10.0.0.227:8888; PROXY 10.0.0.228:8888; PROXY 10.0.0.229:8888; PROXY 10.0.0.230:8888";

}

