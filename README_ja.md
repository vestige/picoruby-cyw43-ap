# picoruby-cyw43-ap

`picoruby-cyw43-ap` は、Raspberry Pi Pico WおよびPico 2 Wへ最小構成の
DHCP付きWi-Fiアクセスポイント機能を追加する、第三者PicoRuby mrbgemです。
`picoruby-cyw43` に依存し、Pico SDKの公開API
`cyw43_arch_enable_ap_mode()` と公開オブジェクト `cyw43_state` を使用します。
PicoRuby coreへpatchを当てる必要はありません。

最初のマイルストーンには、意図的にHTTPサーバーやsocket lifecycleのコードを
含めていません。このgemが担当するのは、APの開始と停止、AP状態とIPv4情報の
取得、およびDHCPだけです。

Pico 2 W + mruby/c、Pico 2 W + mruby、Pico W + mruby/cでは、コンパイルと
リンクを検証済みです。Pico 2 W + mruby/cの実機では、AP起動、クライアント
からのSSID検出と接続、Ruby APIによる状態・IPv4情報取得、AP停止を確認済みです。
クライアントにはDHCPで `192.168.4.2/24` が割り当てられ、routerが
`192.168.4.1` になることも確認済みです。ただし、今回の検証ではクライアントの
Wi-Fi設定画面で接続中の表示が約10秒続きました。遅延箇所は未特定です。
AP停止時にDHCP PCBを削除して参照を破棄し、lease配列を消去する経路はコード
監査済みです。実機でも停止後にAP状態と各getterが停止状態になり、クライアント
からSSIDが検出されなくなることを確認済みです。さらに、Picoを再起動せずに
APを再有効化し、クライアントが再接続して同じDHCP設定を取得できることも確認
済みです。2回目の接続は1回目より速く完了しましたが、差の原因は未特定です。
Pico 2 W + mruby/cでは、AP稼働中の `CYW43.init("JP", force: true)` がAPを
停止してdriverを再初期化し、その後APとDHCPを再利用できることも実機確認済み
です。mruby/cとmrubyの両bindingで、force init前にcleanupする経路を監査済みです。
同じPico 2 W + mruby/c firmwareで、APを起動しないSTA専用接続も実機確認済み
です。STAは `LINK_UP` となってIPv4設定を取得し、その間も `CYW43::AP` は
inactiveのままで、STA切断後は `LINK_DOWN` になりました。接続情報は端末内の
暗号化設定だけを使用し、検証記録には含めていません。

## R2P2への導入

このリポジトリをPicoRubyリポジトリと同じ階層に配置し、現在のR2P2のCMake
ソース検出から参照できるように、Git管理外のsymlinkを作成します。

```sh
cd /path/to/picoruby
ln -s ../../picoruby-cyw43-ap mrbgems/picoruby-cyw43-ap
```

使用するR2P2 build configへgemを追加します。

```ruby
conf.gem gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-cyw43-ap"
```

mrbgemの依存関係により、ビルド時にはこのgemより先に `picoruby-cyw43` が
読み込まれます。FemtoRubyアプリケーションでは、実行時に次の順序で両方を
requireしてください。

```ruby
require "cyw43"
require "cyw43/ap"
```

現在のPicoRuby build configで使用できるビルドコマンドの例です。

```sh
R2P2_NO_SHARED_ALLOC=1 rake r2p2:femtoruby:pico_w:prod
rake r2p2:femtoruby:pico2_w:prod
rake r2p2:picoruby:pico2_w:prod
```

現在のPico W向けフル構成は、デフォルトのshared allocatorサイズではリンク時に
RP2040のRAM容量を超える場合があります。`R2P2_NO_SHARED_ALLOC=1` は、検証済みの
Pico Wビルドで使用した、サポート対象の省メモリ構成を選択します。

## 使用方法

```ruby
require "cyw43"
require "cyw43/ap"

CYW43.init("JP")
raise "AP start failed" unless CYW43::AP.enable("PicoRuby-AP", "12345678")

puts CYW43::AP.active?       # true
puts CYW43::AP.ssid          # PicoRuby-AP
puts CYW43::AP.ipv4_address  # Pico SDKのデフォルト設定では192.168.4.1
puts CYW43::AP.ipv4_netmask  # 255.255.255.0

CYW43::AP.disable
```

### 最小HTTPサーバー例

[`example/pico_w_ap_http_server.rb`](example/pico_w_ap_http_server.rb) は、APへ
接続したブラウザへplain textを返す最小構成のHTTPサーバーです。この例には
`picoruby-socket` も必要です。build configへこのgemと `picoruby-socket` の両方を
追加し、実行時に `cyw43`、`cyw43/ap`、`socket` を読み込んでください。

例の `SSID` と `PASSWORD` は公開用のサンプル値です。必要に応じて端末上で変更し、
実際に使用する認証情報をGitへcommitしないでください。起動後、表示されたURLを
APへ接続した端末のブラウザで開きます。例は各HTTP応答後にclient socketを閉じ、
終了時にはserver socketとAPを停止します。

Pico 2 W + mruby/cの実機で、ブラウザにplain textの応答が表示されることと、
Ctrl-C終了後に例外を出さずAPがinactiveになることを確認済みです。

passwordは8〜63バイト、SSIDは1〜32バイトでなければなりません。デフォルトの
認証方式はWPA2/AES PSKです。第3引数へPico SDKの認証値を明示的に渡すことも
できます。

DHCPサーバーは、Pico SDKが作成したAP netifからネットワーク設定を取得し、
ホスト番号2〜5の4アドレスを提供します。SDKのデフォルトネットワークでは、
`192.168.4.2`〜`192.168.4.5` です。

## API

- `CYW43::AP.enable(ssid, password, auth = WPA2_AES_PSK) -> bool`
- `CYW43::AP.disable -> bool`
- `CYW43::AP.active? -> bool`
- `CYW43::AP.ssid -> String | nil`
- `CYW43::AP.ipv4_address -> String | nil`
- `CYW43::AP.ipv4_netmask -> String | nil`

PicoRuby PR #489から移行するため、同じメソッドを隔離された名前空間の下で
`enable_ap_mode`、`disable_ap_mode`、`ap_active?`、`ap_ssid`、
`ap_ipv4_address`、`ap_ipv4_netmask` としても利用できます。呼び出し側では
`CYW43.` を `CYW43::AP.` へ変更してください。このgemは意図的にトップレベルの
`CYW43` クラスへメソッドを追加せず、将来のPicoRuby core APIとの衝突を防ぎます。

## リソースのlifecycle

`CYW43::AP.disable` は、APインターフェースを無効化する前にDHCP UDP PCBとleaseを
削除します。mruby gemのfinalizerも同じcleanupを行います。mrubyとmruby/cの
両bindingは、`CYW43.init(force: true)` が使用する既存のprivateなRuby
エントリポイントをwrapし、元のcore実装へ処理を渡す前にAP/DHCPを停止します。

Pico SDKのdeinitializationを直接呼び出すnative applicationは、その前にgemの
公開C関数 `picoruby_cyw43_ap_prepare_deinit()` を呼び出す必要があります。この
gemはSDK symbolを置き換えず、PicoRuby coreのC wrapper内部には依存しません。

## 対象範囲と制限

- Raspberry Pi Pico WおよびPico 2 Wのみ。
- APインターフェースは1つ、DHCP poolは4 leaseのみ。
- custom AP network、DNS、NAT、captive portal、HTTPサーバー、接続STA数取得APIは
  提供しません。
- STAの動作は引き続き `picoruby-cyw43` が担当し、このgemでは変更しません。

## ライセンスと帰属表示

このgemはMIT Licenseで配布します。詳細は [LICENSE](LICENSE) を参照してください。
`ports/rp2040/ap_dhcp_server.c` はTinyUSBのnetworking helperを基にしており、
PicoRuby PR #489に由来するSergey Fetisovの著作権表示とMIT Licenseを保持して
います。
