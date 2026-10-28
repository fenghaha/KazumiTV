import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/input/tv_lan_address.dart';

void main() {
  test('casting interface before Wi-Fi does not win the QR address', () {
    expect(
      TvLanAddress.select(const [
        TvLanAddress('192.168.49.1', 'p2p0'),
        TvLanAddress('192.168.50.10', 'wlan0'),
      ])?.address,
      '192.168.50.10',
    );
  });
  test('OS active Ethernet takes priority over another private interface', () {
    expect(
      TvLanAddress.select(const [
        TvLanAddress('10.1.0.2', 'wlan0'),
        TvLanAddress('192.168.50.10', 'eth0', active: true),
      ])?.address,
      '192.168.50.10',
    );
  });
  test('no QR is generated from only casting and VPN interfaces', () {
    expect(
      TvLanAddress.select(const [
        TvLanAddress('192.168.49.1', 'p2p-wlan0-0', active: true),
        TvLanAddress('10.8.0.2', 'tun0'),
      ]),
      isNull,
    );
  });
  test('real LAN addresses are not hardcoded to the home subnet', () {
    for (final ip in ['10.8.0.3', '172.20.0.4', '192.168.49.8']) {
      expect(
        TvLanAddress.select([TvLanAddress(ip, 'wlan0', active: true)])?.address,
        ip,
      );
    }
  });
  test('loopback, public, invalid, and IPv6 candidates are rejected', () {
    expect(
      TvLanAddress.select(const [
        TvLanAddress('127.0.0.1', 'wlan0'),
        TvLanAddress('8.8.8.8', 'eth0'),
        TvLanAddress('::1', 'eth0'),
        TvLanAddress('bad', 'eth0'),
      ]),
      isNull,
    );
  });
}
