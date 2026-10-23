import 'dart:io';

/// Prefer the OS default physical network, never a casting/tunnel interface.
class TvLanAddress {
  const TvLanAddress(this.address, this.interfaceName, {this.active = false});
  final String address;
  final String interfaceName;
  final bool active;

  static bool isVirtual(String name) => RegExp(
    r'^(p2p|swlan|ap\d|softap|wifi.?direct|utun|tun|tap|wg|docker|br-|veth|tailscale|rndis)',
    caseSensitive: false,
  ).hasMatch(name);

  static InternetAddress? select(Iterable<TvLanAddress> candidates) {
    final usable = candidates.where((candidate) {
      if (isVirtual(candidate.interfaceName)) return false;
      final ip = InternetAddress.tryParse(candidate.address);
      if (ip == null || ip.type != InternetAddressType.IPv4 || ip.isLoopback) {
        return false;
      }
      final b = ip.rawAddress;
      return b[0] == 10 ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31);
    }).toList();
    int rank(TvLanAddress candidate) => candidate.active
        ? 0
        : RegExp(
            r'^(wlan|wifi|eth|en\d|enp|wlp)',
            caseSensitive: false,
          ).hasMatch(candidate.interfaceName)
        ? 1
        : 2;
    usable.sort((a, b) => rank(a).compareTo(rank(b)));
    return usable.isEmpty ? null : InternetAddress(usable.first.address);
  }
}
