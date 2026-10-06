# picoruby-cyw43-ap

Raspberry Pi Pico WとPico 2 WへDHCP付きWi-Fiアクセスポイントを追加する、
PicoRuby本体とは別に開発しているmrbgemです。`picoruby-cyw43`に依存し、
Pico SDKの公開インターフェースを使用します。PicoRuby coreへのpatchは不要です。
このgemが提供するのはAPとDHCPの機能であり、HTTPサーバーは含みません。

[English README](README.md)

## R2P2への導入

このリポジトリをPicoRubyリポジトリと同じ階層に置きます。現在のR2P2のCMake
ソース検出から参照できるよう、PicoRuby側にGit管理外のsymlinkを作成します。

```sh
cd /path/to/picoruby
ln -s ../../picoruby-cyw43-ap mrbgems/picoruby-cyw43-ap
```

使用するR2P2 build configにgemを追加します。

```ruby
conf.gem gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-cyw43-ap"
```

mrbgemの依存関係により、ビルド時には`picoruby-cyw43`が先に読み込まれます。
実行時は次の順序でrequireしてください。

```ruby
require "cyw43"
require "cyw43/ap"
```

ビルドコマンドの例です。

```sh
R2P2_NO_SHARED_ALLOC=1 rake r2p2:femtoruby:pico_w:prod
rake r2p2:femtoruby:pico2_w:prod
rake r2p2:picoruby:pico2_w:prod
```

Pico Wのフル構成は、デフォルトのshared allocatorではRP2040のRAM容量を
超える場合があります。最初のコマンドはリンクを検証済みの省メモリ構成です。

## 基本的な使い方

```ruby
require "cyw43"
require "cyw43/ap"

CYW43.init("JP")
raise "AP start failed" unless CYW43::AP.enable("PicoRuby-AP", "12345678")

puts CYW43::AP.active?
puts CYW43::AP.ssid
puts CYW43::AP.ipv4_address
puts CYW43::AP.ipv4_netmask

CYW43::AP.disable
```

SSIDとパスワードは実際の用途に合わせて変更してください。SSIDは1〜32バイト、
パスワードは8〜63バイトです。認証方式のデフォルトはWPA2/AES PSKで、Pico SDKの
認証値を第3引数へ指定することもできます。DHCPは4つのクライアントアドレス
（ホスト番号2〜5）を配布します。SDKのデフォルト設定ではAPが
`192.168.4.1`、割り当て範囲が`192.168.4.2`〜`192.168.4.5`です。

## サンプル

- [最小HTTPサーバー](example/pico_w_ap_http_server.rb)：APに接続したブラウザへ
  plain textを返します。
- [AP版Pico Timer](example/pico_w_ap_timer.rb)：Set、Start、Stop、Reset、満了、
  手動の状態更新を備えたフィジビリティ例です。
- [同時HTTPリクエスト診断](example/pico_w_ap_http_concurrent_test.rb)：
  ブラウザから実行する診断用で、製品向けサーバーではありません。

HTTPのサンプルでは、build configに`picoruby-socket`も追加し、実行時に
`require "socket"`してください。SSIDとパスワードは公開用のサンプル値です。
実際の認証情報をGitへcommitしないでください。各サンプルは終了時にsocketを
閉じてAPを停止します。Timerは事前コンパイルした`.mrb`を使い、Pico 2 W +
mruby/cの実機で操作と後始末を確認済みです。Pico Wとmrubyの実機動作は未検証です。
[ホスト用スモークテスト](example/pico_w_ap_timer_host_smoke.rb)はCRubyと
PicoRuby hostで実行できます。

## API

- `CYW43::AP.enable(ssid, password, auth = WPA2_AES_PSK) -> bool`
- `CYW43::AP.disable -> bool`
- `CYW43::AP.active? -> bool`
- `CYW43::AP.ssid -> String | nil`
- `CYW43::AP.ipv4_address -> String | nil`
- `CYW43::AP.ipv4_netmask -> String | nil`

PicoRuby PR #489からの移行用に、`CYW43::AP`の下で
`enable_ap_mode`、`disable_ap_mode`、`ap_active?`、`ap_ssid`、
`ap_ipv4_address`、`ap_ipv4_netmask`も使用できます。このgemは
トップレベルの`CYW43`クラスにはメソッドを追加しません。

## 検証状況と制限

Pico 2 W + mruby/c・mruby、Pico W + mruby/cでコンパイルとリンクを
検証済みです。AP、DHCP、停止、再有効化、force init時のcleanup、STAのみの
回帰はPico 2 W + mruby/cの実機で確認しました。他のボード・VM構成は実機未検証です。
検証経緯とsocket/Core側の後続課題は[TODO_ja.md](TODO_ja.md)およびリンク先の
Issueに記録しています。HTTPサンプルは、このgemのAP/DHCP実装には含まれません。

APインターフェースは1つ、DHCP leaseは4件です。カスタムAPネットワーク、DNS、
NAT、キャプティブポータル、内蔵HTTPサーバー、接続端末数の取得APIはありません。
STAは引き続き`picoruby-cyw43`が担当します。

`CYW43::AP.disable`はAP停止前にDHCP UDP PCBとleaseを解放します。mrubyの
finalizerと`CYW43.init(force: true)`のcleanup経路でもAP/DHCPを停止します。
Pico SDKを直接deinitするnative applicationは、事前に
`picoruby_cyw43_ap_prepare_deinit()`を呼んでください。

## ライセンスと帰属表示

MIT Licenseです。詳細は[LICENSE](LICENSE)を参照してください。
`ports/rp2040/ap_dhcp_server.c`はTinyUSBのnetworking helperを基にしており、
PicoRuby PR #489に由来するSergey Fetisovの著作権表示とMIT noticeを保持します。
