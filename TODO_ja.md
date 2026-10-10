# 開発TODO

この文書は、開発状況とPicoRuby coreから分離して進める必要がある作業を
記録するものです。マイルストーンや検証結果が変わったときは、英語版の
`TODO.md` とこの日本語版を同時に更新します。今後の進め方や方針は、まず
この日本語版で確認してから作業します。

GitHub上のIssue、PRのタイトル・本文、検証コメントは原則として日本語で記載
します。commit messageは、既存の履歴に合わせて英語を使用します。

## 想定しているユースケース

- Raspberry Pi Picoを屋外へ持ち出し、スマホのテザリングなど既存の
  ネットワークへSTAとして接続して、スマホからPicoを操作する。
- 既存のネットワークがない場所ではPico自身をAPにし、スマホとPicoの間だけで
  直接通信できるスタンドアローン環境を用意する。
  - 例えば、簡易タイマーの操作やラジコンのリモコンとしてスマホを使う。

このgemの主な役割は後者のAP/DHCP基盤を提供することです。実際の操作画面や
HTTP通信は後続マイルストーンで扱い、既存のSTA用途を壊さないことも確認します。

## Pico TimerをMicroPython版から置き換える完成条件（2026-10-05）

基準は利用者が実機で動かしているMicroPythonの
[ptc/main.py](https://github.com/vestige/ptc/blob/main/main.py)です。
作業中に参照内容が変わらないよう、確認した版は
[commit `5275055`](https://github.com/vestige/ptc/blob/5275055db7994b5c954f834a9d7734154ed2b489/main.py)
（添付されたコードとSHA-256が一致）と記録します。古い`pcw_timer.py`は基準にしません。
この作業はgem本体のAP/DHCP API拡張とは分け、Issueごとにbranchを作って進めます。
Issue #31でAP接続、画面、Set/Start/Stop/Reset、満了表示、手動更新、終了時の
AP停止はPico 2 W + mruby/c実機で確認済みです。ただし現行例はHTTP requestが
ない間に満了処理を実行せず、物理スイッチ・LED・ブザーも未実装です。

- [x] 参照元の`ptc/main.py`の操作規則、GP15/GP16/GP21の配線、
      効果音、画面挙動を、認証情報を含めずに
      [Issue #34](https://github.com/vestige/picoruby-cyw43-ap/issues/34)へ記録した。
- [x] 現行PicoRuby Core `a90afd12`を確認し、`GPIO`、`CYW43::GPIO`、`PWM`、
      `Machine.board_millis`、`TCPServer#accept_nonblock`の利用条件を確認する。
      必要なAPIは最新upstreamに存在し、Core内のAP/Timer例に見えたものは手元の
      未merge branchだけの内容で、外部gemとは重複していない。通常のCore checkoutの
      tracked filesは変更していない。実機用buildは一時worktreeで行う。
- [x] [Issue #34](https://github.com/vestige/picoruby-cyw43-ap/issues/34)で、
      HTTP requestがなくてもPico側で時刻を進める。タイマーの満了、入力の読取、
      音の進行がsocket待受に妨げられない構成を選び、1秒・10秒の実時間試験と
      3600秒境界のhost testで確認する。満了処理は各回1度だけ実行する。
      - [x] `accept_nonblock`を使う10ms間隔のservice loopを実装し、接続なしの
        仮想1秒満了、満了状態の保持、1〜3600秒の境界、接続処理とclient closeを
        CRuby host smoke testで確認した。両ファイルの`mrbc`コンパイルも成功した。
      - [x] 最新Core `a90afd12`の一時worktreeでPico 2 W + mruby/cをbuildした。
        外部gemを含むUF2の生成とリンク済みシンボルを確認した。
      - [x] Pico 2 W実機で1秒・10秒の無通信満了と満了状態の保持、満了後の画面、
        Set・Start・Stop・再開・Resetを確認した。最初の`accept_nonblock`版では
        SandboxがCtrl-C時にtaskを外側から停止し、Rubyの`ensure`を実行しないため
        `CYW43::AP.active?`が`true`のまま残ることを検出した。
        `Machine.signal_self_manage`とservice loop内の`Machine.check_signal`で
        `Interrupt`をtask内で処理するよう修正した最終版では、10秒の無通信満了後も
        `Stopping Pico Timer`、`AP active?: false`、shell復帰、SSID消失を確認した。
- [x] [Issue #36](https://github.com/vestige/picoruby-cyw43-ap/issues/36)で、
      元の操作規則を実装する。秒数の設定は同時に開始、Stop後の次のStartは
      保存した秒数から再開始とし、現在のPicoRuby例の「Setのみ」「残り時間から再開」
      との差を解消する。範囲は1〜3600秒とする。
      - [x] 元の`ptc/main.py`を再確認し、Set時の即時開始、Stop、保存秒数からの
        Start、PicoRuby固有のResetの意味をhost smoke testで確認した。
      - [x] 最新Core `a90afd12`でPico W + mruby/cをbuildした。最初のコマンドでは
        `R2P2_NO_SHARED_ALLOC=1`を指定したが、現行Coreにはこの環境変数への参照がなく、
        build結果には影響していない。外部gemのリンク済みシンボルと
        2,603,008 bytesのUF2（SHA-256
        `e281ee1b166d236435d79e42d240665ce6831ad3c83c5ded66eec2c2b67436fe`）を確認した。
      - [x] 初期化許可済みの別個体Pico Wで、Setによる即時開始、Stop中の残り時間保持、
        次のStartで停止時の残りではなく保存した30秒から再開始すること、無通信満了を
        確認した。最初の試行後にLittleFSのファイル読取破損が発生したため、公式の
        `flash_nuke.uf2`で全消去して同一SHA-256のfirmwareを書き直した。Timerのmrbは
        転送後の読戻しでCRC32とSHA-256が一致し、破損は再現しなかった。Ctrl-Cでは
        `Stopping Pico Timer`、`AP active?: false`、shell復帰、SSID消失を確認した。
- [ ] GP15の外付けLEDを開始時に消灯、満了時に点灯し、LED Off操作または次の
      開始まで点灯を保持する。ブラウザを閉じたまま満了させ、LEDとタイマー状態を
      実機確認する。
- [ ] GP16のGNDへ落とすタクトスイッチをpull-upで読み、1回の押下を1回の
      操作として扱う。計測中は停止、満了LED点灯中は消灯、それ以外は保存秒数で
      開始する。チャタリングと長押しによる重複操作を実機確認する。
- [ ] GP21の圧電ブザーをPWMで駆動し、開始・停止・満了の効果音を再生する。
      音の再生はHTTP、スイッチ、満了判定を止めず、終了時にはPWMを停止する。
- [ ] Pico W/2 Wの内蔵LEDを動作中の目印として点滅させる。ブラウザの残り時間と
      LED状態を自動更新し、通信失敗時・再接続後もPico側の状態と一致させる。
- [ ] 元の`main.py`と同様にPicoを通常起動するだけでアプリが立ち上がる方法を
      整理する。APの予期しない停止からの回復、Ctrl-Cや異常終了時のsocket・AP・
      GPIO/PWMの後始末、スマホの通常Wi-Fi復旧を確認する。
- [ ] Pico 2 W + mruby/cの実配線で、スマホを閉じたままの満了、スイッチのみの
      操作、ブラウザ操作、再接続、複数回の開始・停止・満了を通しで検証する。
      元のPico Wを置き換える完成判定では、Pico W + mruby/cでも同じ通し試験を行う。
      host test、対象firmwareのビルド、実機ログ、未検証のVM構成を記録する。

Core側の既知課題#510・#516・#524は現在クローズ済みで、外部gemのIssue/PRにも
openのものはありません。現時点で上記を始める前に必須のCore修正は確認されて
いません。[Core #439](https://github.com/picoruby/picoruby/issues/439)はSTA接続時の
エラーコードと再試行に関する未解決の相談であり、このAP版Timerとは別に追います。
Coreのローカルbranchやprunableな一時worktreeの整理は別の保守作業です。

## 2026-09-11時点の状態記録

- このリポジトリはPicoRuby本体とは別に開発したmrbgem
  `picoruby-cyw43-ap`です。
- `main` は `vestige/picoruby-cyw43-ap` の `origin/main` を追跡しています。
- このリポジトリは、GitHub上のMIT License初期コミットを基点にしています。
- 初回実装には、gem本体、英語・日本語ドキュメント、型シグネチャ、サンプルを
  含めます。
- 対象3構成のコンパイルとリンクは検証済みです。実機でのAP/DHCP検証はまだ
  進行中です。
- Pico 2 W + mruby/cの実機で、AP起動、SSID検出、クライアント接続、Ruby API
  による状態・IPv4情報取得、AP停止を確認済みです。
- 同じ実機検証で、クライアントにDHCPで `192.168.4.2/24`、routerとして
  `192.168.4.1` が割り当てられることを確認済みです。クライアントのWi-Fi設定
  画面で接続中の表示が約10秒続いたことを記録します。遅延箇所は未特定です。
- AP停止経路のコード監査で、DHCP PCBの削除と参照の破棄、lease配列の消去を
  確認済みです。実機では停止後のAPI状態とSSID消失を確認済みです。
- Picoを再起動せずにAPを再有効化し、クライアントの再接続と同じDHCP設定の
  取得を確認済みです。2回目の接続は1回目より速く、差の原因は未特定です。
- Pico 2 W + mruby/cの実機で、AP稼働中のforce initによる停止・driver再初期化と、
  その後のAP再有効化・DHCP再取得を確認済みです。mruby/cとmrubyの両bindingで
  force init前のcleanup経路を監査済みです。
- 同じfirmwareでSTA専用接続が `LINK_UP` となってIPv4設定を取得し、APが
  inactiveのままであることと、STA切断後に `LINK_DOWN` となることを確認済み
  です。接続情報は暗号化された端末内設定だけを使用し、記録していません。
- PicoRuby core外の最小HTTPサーバー例を追加し、Pico 2 W + mruby/c実機で
  ブラウザへのplain text応答と、Ctrl-C終了後のAP停止を確認済みです。
- 同じAP・HTTP serverで20回の逐次request、response、client closeに成功しました。
  ただし、停止後に同じportを再利用するにはPicoの再起動が必要で、待受中の
  Ctrl-Cでは `TCPServer#accept` 由来の終了例外が発生することを確認しました。
  いずれもPicoRuby socket側の後続課題としてIssue #16で追跡します。
- Issue #16の切り分けで、client接続がなければAPの再起動後も同じportへ即座に
  再bindできる一方、APを停止せず1件だけacceptしてclientとserverをcloseすると
  再bindに失敗することを確認しました。現在の `picoruby-socket` はlistenerへ
  `SOF_REUSEADDR` を設定しますが、PicoRuby用 `lwipopts.h` では `SO_REUSE` が
  有効化されておらず、lwIPのTIME_WAIT再利用処理はコンパイルされません。
  一時worktreeで `SO_REUSE=1` だけを有効にした比較用firmwareでは、同じ1接続後の
  即時再bindに成功しました。さらに、1接続ごとにclientとserverをcloseして
  同一portへ再bindする処理を10回連続で実行し、10回すべて成功しました。
  この実機比較により、再bind失敗の原因を確認済みです。さらにPicoRuby最新
  upstream `80efbea3` でも、未適用firmwareでは同じ1接続後の即時再bindが失敗し、
  `SO_REUSE=1` だけを適用したfirmwareでは成功することをPico 2 W + mruby実機で
  再確認しました。
- 同じ `SO_REUSE=1` の比較用firmwareでも、`TCPServer#accept` 待受中のCtrl-C後に
  `server is not initialized` が発生しました。`ensure` によるAP停止は成功し、
  `active?` はfalseでした。この終了例外は再bind問題とは独立した課題です。
  mruby版でも1接続後の即時再bindに成功し、Ctrl-C時にはcleanup内のserver再closeで
  `server is not initialized`、割り込み終了時に `Already stopped` が発生しました。
  AP cleanupは成功しており、再bind修正とCtrl-C課題のどちらもbinding固有では
  ありません。最初のmruby版接続ではクライアントWi-Fiが一度切れましたが、再試行
  ではHTTP応答と再bindに成功し、この切断は再現していません。
- Core後続対応の当時の状況（2026-09-16）：再bind修正の
  [PR #506](https://github.com/picoruby/picoruby/pull/506) はマージ済みです。
  [PR #509](https://github.com/picoruby/picoruby/pull/509) のCIは4項目とも成功しました。
  コミット `95bf98ac` は割り込み後のacceptを止め、
  INT handlerを復元し、mrubyのserver closeを二重実行しても安全にします。
  socketテストは両VMで57/57成功、Steepも成功しました。Pico 2 Wの両VMでは、
  `Interrupt` をrescueするテストでcleanup、AP inactive、シェル復帰を確認し、
  server lifecycleエラーはありませんでした。上記のエラー記録は修正前の観測です。
- Core後続対応の現在の状況（2026-09-26）：PR #509は、実際のR2P2 Ctrl-C経路では
  `ensure`が実行されずhandlerが残ること、複数task間のhandler復元順序、
  `accept_loop`のblock実行中の割り込みを十分に扱えないためcloseされました。
  代替修正の [PR #513](https://github.com/picoruby/picoruby/pull/513) はmerge済みです。
  今後の実機検証は#513を含む最新upstreamを基準にし、#509の`95bf98ac`を新しい
  buildの基点には使いません。
- [Core #505](https://github.com/picoruby/picoruby/issues/505) はPR #506で解決して
  close済みであり、#513後の再検証による更新は不要です。
- AP/socketを使わないスクリプトの再実行時の断続的な不安定さは、修正前後の
  mruby/c firmwareで観測しています。原因は未特定で、
  [Core #510](https://github.com/picoruby/picoruby/issues/510) で別途追跡します。
- このgemを導入するためにPicoRuby coreを変更してはいけません。
- HTTPサーバーとsocket lifecycleの作業は、最初のAP/DHCPマイルストーンの
  対象外です。

## 初回コミット前

- [x] すべてのuntrackedファイルをレビューし、認証情報、ファームウェア、
      ビルド出力、シリアルログ、一時symlinkが含まれていないことを確認する。
- [x] LICENSEの著作権表記を整理する。GitHub版は `Makoto Yonezawa`、以前の
      ローカル案は `picoruby-cyw43-ap contributors` だった。
- [x] `mrbgem.rake` が `picoruby-cyw43` への依存を宣言していることを確認する。
- [x] `CYW43::AP` APIとPR #489互換メソッド名をレビューする。
- [x] `CYW43.init(force: true)` の前にDHCPを終了するために使う、privateなRuby
      エントリポイント `_init` への限定的な依存をレビューする。
- [x] TinyUSB由来のDHCPコードに著作権表示とMIT License全文が保持されている
      ことを確認する。
- [x] ソース変更後はすべてのビルド検証を再実行する。
- [x] 明示的な許可を得た後にのみコミットおよびpushする。

## 最初のAP/DHCPマイルストーン

- [x] PicoRuby coreのtracked filesを変更せず、外部mrbgemとしてビルドする。
- [x] Pico 2 W + mruby/cでコンパイルおよびリンクする。
- [x] Pico 2 W + mrubyでコンパイルおよびリンクする。
- [x] `R2P2_NO_SHARED_ALLOC=1` を使い、Pico W + mruby/cでコンパイルおよび
      リンクする。
- [x] Pico WまたはPico 2 WでAPを開始し、クライアントからSSIDを検出する。
- [x] クライアントがDHCPでアドレスを取得することを確認する。
- [x] Rubyから `active?`、`ssid`、`ipv4_address`、`ipv4_netmask` を確認する。
- [x] APを停止し、DHCP PCBとleaseが解放されることを確認する。
- [x] AP停止後に再びAPを有効化できることを確認する。
- [x] `CYW43.init(force: true)` 実行時のcleanupを確認する。
- [x] 既存のSTA専用プログラムが以前と同じように動作することを確認する。

基板、BOOTSELボリューム、シリアルデバイス、シリアルポートの所有プロセスを
一意に特定できない限り、実機へ書き込まないでください。検証専用のPicoRuby
build config変更は、一時worktree内だけに保持します。

## 後続マイルストーン

AP/DHCPマイルストーンが安定してから開始します。

- [x] PicoRuby coreの外部に最小構成のHTTPサーバー例を追加する。
- [x] `accept`、`recv`、`close` の繰り返しlifecycleをテストする。
- [x] リロード、複数タブ、再接続、クライアントWi-Fiの復旧をテストする。
      - [x] PR #509のCore `95bf98ac` を使い、Pico 2 W + mruby/cで逐次リロードを
        検証しました。blockingな `gets` を上限付きnonblocking header readへ変更後、
        同じタブから21回すべて期待した応答を受信し、socketエラーはありませんでした。
        Ctrl-C後にAP停止とシェル復帰、別確認でinactive・SSID nilを確認しました。
      - [x] 複数タブとブラウザからの同時接続を検証する。
        - Pico 2 W + mruby/c、Core `95bf98ac` で、ブラウザから合計20件を
          最大1、2、3件ずつ同時実行する自動テストを実施しました。最大1件は
          20/20、最大2件は3周で60/60、最大3件は最初の2周で40/40成功しました。
        - 最大3件の3周目は7/20成功後、次のrequestを読み終えた
          `client.write` から戻らず、残りはブラウザ側の10秒timeoutになりました。
          それ以前のclientはすべてwriteとcloseを完了しています。同様の停止は
          別の試行でも発生しましたが、開始直後に必ず再現するものではありません。
          AP gem固有と断定せず、`picoruby-socket` 側の別Issue候補として扱います。
        - Issue #24で、新品Pico 2 W + 公式MicroPython v1.29.0を比較しました。
          最大1件は20/20、最大2件と最大3件はそれぞれ同一AP/server sessionで
          3周、60/60成功し、すべてでread、`sendall`、closeが完了しました。
          エラーはなく、各条件のCtrl-C後にAP停止と
          REPL復帰も確認しました。別個体のため個体差は除外できませんが、単純な
          Pico 2 Wの性能限界である可能性は下がりました。
        - [x] Issue #26で、PR #513を含む最新upstreamから一時worktreeを作り、
          Pico 2 W + mruby/cを再buildする。通常のCore checkoutは変更していません。
          Coreは`729d9d55`、外部gemは`159232e`、一時worktreeは
          `/private/tmp/picoruby-issue-26.cxTtmx`です。生成したUF2は3,895,296 bytes、
          SHA-256は`0bb64e3d237e2359b47aa93dbba889a05cd806cfae5b00b55b6cbfdd84f8c593`
          です。host buildにはmacOS標準Ruby 2.6ではなくHomebrew Ruby 4.0.3を
          使用し、先に`mrbc:prod`を実行しました。
        - [x] #513のCtrl-C lifecycle、AP cleanup、shell復帰、同一port再利用を
          実機で再確認する。port 10085の`TCPServer#accept`待機中にCtrl-Cを送り、
          `cleanup active?: false`、`INTERRUPT RESCUED`、shell復帰を確認しました。
          同じboot内でもう一度同じprobeを起動して`READY`まで進み、同一port再bindと
          2回目の正常なCtrl-C cleanupも確認しました。
        - [x] [Core #507](https://github.com/picoruby/picoruby/issues/507) の完了条件として、
          Ctrl-C後に`server is not initialized`や二重closeエラーがなく、AP停止、
          shell復帰、同一port再利用が成功することを確認する。結果を英語で追記し、
          すべて成功しました。実機結果を英語で追記し、#513で解決済みとして
          2026-09-26に#507をcloseしました。
        - [x] [Core #510](https://github.com/picoruby/picoruby/issues/510) の最小
          `Interrupt` probeを、同一boot内で複数回実行する。Core revision、VM、
          実行回数、全serial出力を記録する。mruby/c、Core `729d9d55`で、1回目は
          `BEFORE`、`ENSURE`、未処理`Interrupt`の後にshellへ復帰しました。2回目は
          `Exception(vm_id=26):`まで表示して停止し、`BEFORE`もpromptも出ませんでした。
          5秒待っても復帰せず、#513後も再現することを確認しました。
        - [x] #510の再現結果をCore Issueへ英語で追記し、#513とは別のshell/VM task
          recovery問題としてopenのまま調査を続ける。十分な反復で再現しない場合に
          #513での解消を検討する案は、今回2回目で再現したため採用しませんでした。
        - [ ] clean boot後に最大3件・20 requestを3周以上実行し、#509 firmwareで
          観測した`client.write`停止が再現するか確認する。第1周はブラウザ表示が
          2/20でした。serialでは、最初のprobe responseをwrite・closeした後、次の
          接続でrequest read完了後の`client.write`から12秒以上戻りませんでした。
          ブラウザの10秒timeout後も復帰せず、Ctrl-Cでもcleanupやshell復帰は
          起きませんでした。このため当時の3周成功条件は未達です。この項目は
          過去の試験記録であり、現行Core `d392ce47`でのAP版60/60成功をIssue #22に
          記録してclose済みのため、現在の前提作業ではありません。
        - [x] 再現結果とMicroPython比較を基に、別のPicoRuby Core Issueを
          作成するか最終判断する。#513後のclean bootでも再現し、MicroPythonでは
          同じ最大3件条件を60/60成功しているため、Core socket側の別Issueとして
          [Core #516](https://github.com/picoruby/picoruby/issues/516) を作成しました。
          native `TCPSocket_send`内の正確な停止位置は#516で追跡します。
        - [x] Core側の起動報告
          [#524](https://github.com/picoruby/picoruby/issues/524)を、最新upstream
          `master`とnative markerによる直接観測で見直す。
          - [x] Core `729d9d55`、Pico 2 W、mruby/c、poll方式、標準388KB heapで、
            外部AP gemを含まない比較用firmwareをbuildする。既存build cacheには
            外部AP gemのobjectが残っていたため、build directoryを削除せず退避し、
            完全再build後に外部gemが含まれないことを確認しました。
          - [x] 通常起動ではPicoModemがACKを受け取れず、起動直後の2秒間に`s`を
            自動送信して`/etc/init.d/r2p2`をskipすると、同じfirmwareでshellへ到達し、
            `/home/background_test.rb`を6,490 bytesすべて読み出せることを確認しました。
          - [x] `/home/app.rb`と`/home/app.mrb`は存在しませんでした。認証情報を表示せず
            `/etc/network/wifi.yml`を確認し、`auto_connect=false`、`retry_if_failed=false`、
            `watchdog=false`であることを確認しました。現在の`wifi_connect`は
            `auto_connect`判定より前に`Network::WiFi.init`を実行します。
          - [x] `auto_connect=false`の早期returnを`Network::WiFi.init`より前へ移す
            最小比較版を完全再buildする。`/etc/ruby-description`だけを削除して同梱された
            system executableを再生成させ、ユーザーファイルとWi-Fi設定は保持しました。
            起動skipなしの通常起動と、その後の通常再起動の両方でPicoModemのACKと
            6,490-byte fileの完全な読み出しに成功しました。
          - [x] PicoRuby Coreへ英語の新規Issue
            [#524](https://github.com/picoruby/picoruby/issues/524)を作る。環境、最小再現手順、通常起動と
            boot skipのA/B結果、設定値、処理順序、最小比較修正、2回の通常起動成功を
            記載します。これはshell起動前の問題であり、同一boot内で`Interrupt`再実行が
            止まる#510や、AP上の`TCPSocket#write`が止まる#516を解決したとは扱いません。
          - [x] 最新Coreの専用branchで最小修正と回帰testを用意し、共有されるshell command
            への影響をmruby/cとmrubyの両方で確認する。現在の#516診断branchへ混ぜません。
            - [x] 最新upstream/master `6b7c5437`（4.0.6）から
              `issue-524/skip-disabled-auto-connect`を作り、最小の処理順変更だけを適用する。
            - [x] Pico 2 W production構成をmruby/cとmrubyの両方でbuildする。
            - [x] mruby/c版を既存filesystemと`auto_connect=false`設定を保持したPico 2 Wへ
              書き込み、起動skipなしの通常起動と通常再起動の両方でPicoModem ACKおよび
              6,490-byte file readが成功することを確認する。
            - [x] mruby版でも実機の通常起動と通常再起動を確認する。両方で
              PicoModem ACKおよび6,490-byte file readに成功しました。
            - [x] 既存test基盤では端末上の設定ファイルとCYW43を使うshell executableを
              直接実行できないため、この処理順だけのための公開helper APIは追加しない。
              mruby/c・mruby両production buildと、両VMそれぞれ2回の通常起動による
              実機A/Bを今回の変更に見合う回帰検証として記録します。
            - [x] Coreの専用branchへ`7686f0e9 Fix disabled Wi-Fi auto-connect startup`
              として1-fileの最小修正をcommitする。forkへpushし、英語PR
              [#525](https://github.com/picoruby/picoruby/pull/525)を作成しました。
          - [x] 起動修正を区切った後、完全再buildしたCore-only firmwareで#510の最小
            `Interrupt` probeを繰り返す。Pico 2 W、mruby/c、poll方式、標準388KB heap、
            Core `6b7c5437` + 未mergeの#525 `7686f0e9`、外部AP gemなしで、再起動を
            またぐ2回の通常bootそれぞれ20/20、合計40/40回shellへ復帰しました。
            各bootの1回目は通常の`Interrupt`表示だけで、2回目以降は
            `Exception(vm_id=27)`が追加表示されましたが、その後も`BEFORE`、`ENSURE`、
            通常の`Interrupt`を表示してpromptへ復帰しました。
          - [x] 上記結果を#510へ英語で
            [返信しました](https://github.com/picoruby/picoruby/issues/510#issuecomment-5932655771)。
            以前の2回目hangは今回再現しなかった
            ものの、40/40だけで解決済みとは断定せず、追加の`vm_id=27`表示と、#525が
            起動順序だけの未merge変更で#510の修正とは扱っていないことを明記します。
            最初の通常起動でshell/PicoModemが応答しない状態があり、boot scriptを省く
            救済版では応答し、保存済み`r2p2` bytecodeはbuild生成物と完全一致、Wi-Fi設定は
            `auto_connect=false`、自動起動appなし、救済shellからのWi-Fi checkとboot script
            全体の手動実行は成功しました。その後通常版へ戻すと正常起動した経緯は、
            #510のprobe結果とは分けて参考情報として記載しました。
          - [x] maintainer側では最新`master`で再現しなかったことを受け、PR #525は
            1つの設定で初期化を回避するだけで、country codeの適用まで省く可能性が
            あると理解する。PRはcloseし、原因修正として再利用しない。
          - [x] #524へ、最新masterを使い、`cyw43_arch_init_with_country`の直前・直後に
            serial markerを置いて比較すると返信する。
          - [x] 最新upstream `master`から新しい診断branch/worktreeを作る。
            `cyw43_arch_init_with_country`の前後へ観測専用markerだけを追加し、初期化順序や
            挙動は変更しない。
          - [x] Core `d392ce47`から、外部AP gemを含まないPico 2 W mruby/c
            productionの比較用UF2をbuildする。UF2は
            `/private/tmp/picoruby-issue-524-markers.fLGEeD/build/r2p2/femtoruby/pico2_w/prod/R2P2-FEMTORUBY-4.0.6-PICO2_W-20261002-d392ce47.uf2`、
            3,908,608 bytes、SHA-256は
            `65ee71f0ebdc8395798866ff4b9a5522b946c67a92ac01e0498be20d0bd5a407`。
            UF2内に#524の両marker文字列があり、外部AP gemがbuildに含まれないことも
            確認しました。最初のbuildでは`printf`を使ったためUSB shellではなく
            Picoprobe UART向けとなり、正常bootしてもmarkerを取得できませんでした。
            markerの出力先だけを`picorb_hal_write`へ変更し、上記hashで再buildしました。
          - [x] 書き込み前にRP2350のBOOTSEL deviceを一意に確認する。filesystemと既存の
            `auto_connect=false`という比較条件は保持する。
          - [x] 同じPico 2 Wで通常起動を繰り返し、serial logを取得する。最初の起動では
            CYW43 markerより前に、古い生成物 `/bin/wifi_connect` のcompile failureが
            見つかりました。`/etc/ruby-description`を
            `/etc/ruby-description.pre-524-usb-marker`へ非破壊で退避し、次の起動で不一致の
            bundled commandを再生成しました。その起動と続く通常再起動はいずれも
            `cyw43_arch_init_with_country`の前後markerを表示し、`auto_connect=false`のまま
            shellへ到達しました。
          - [x] #524へ、再現しなかった結果と正確な条件を報告する。最初のcompile failureは
            CYW43初期化より前に発生し、bundled commandの再生成後は解消した別事象として
            説明しました。英語の訂正と謝罪をIssue comment `5953909705`として投稿し、
            PR #525の早期return仮説には戻りませんでした。
        - [x] Core #510は、sandbox VMに残っていたexception参照と追加の
          `Exception(vm_id=27)`表示をupstream PR #527が修正したため完了とする。
          この説明は手元の観測と一致し、AP/socketの結果は#510の根拠に使わない。
        - [x] Core #516のCore-only条件は、maintainerが現行Core `d392ce47`以降で確認した
          結果をもって完了とする。最大3並列・20 requestを3周して60/60、peer disconnectは
          hangせず例外、serverはその後もacceptを継続し、Ctrl-Cでshellへ戻っています。
        - [x] #524への回答後、`d392ce47`以降から外部AP gemを明示的に組み込んで、同等の
          concurrent HTTP試験をやり直す。Core-onlyが成功しAP版だけが止まる場合は、#516を
          reopenせず外部gem repositoryで続ける。外部gemなしでも再現し、nativeの停止位置を
          特定できた場合だけCore Issueのreopenまたは新規Issueを検討する。
          - [x] Issue #22の既存診断変更を破棄せず、外部gemの専用branch
            `issue-22/current-core-revalidation`を作る。
          - [x] Core `d392ce47`の使い捨てworktree
            `/private/tmp/picoruby-cyw43-ap-current.XwP9bu`を作り、外部gem symlinkと
            mruby/c Pico 2 W用の一時build設定だけを追加してproduction buildを完了する。
            build summaryに`picoruby-cyw43-ap 0.1.0`が含まれ、ELFに
            `picoruby_cyw43_ap_prepare_deinit`があることを確認しました。
          - [x] 観測変更を含まない通常版UF2を
            `/private/tmp/picoruby-cyw43-ap-current.XwP9bu/build/r2p2/femtoruby/pico2_w/prod/R2P2-FEMTORUBY-4.0.6-PICO2_W-20261002-d392ce47.uf2`、
            3,914,752 bytes、SHA-256
            `619a3c3d0212dd3d0c97224f9c62bed89502ed1dc95ad9e262dd1f28ed975310`
            として記録する。#524の診断markerが含まれないことも確認しました。
          - [x] 書き込み前にPico 2 WのRP2350 BOOTSEL volumeを一意に確認する。最初の起動では
            bundled system executableがこのfirmwareと一致したことを確認してから、HTTP結果を
            有効な試行として扱う。最初の起動は古い生成物`/bin/wifi_connect`のcompile failureで
            停止したため無効としました。boot skip後、`/etc/ruby-description`だけを
            `/etc/ruby-description.pre-issue22-d392ce47`へ退避すると、次の起動で不一致のcommandが
            再生成され、その次の通常起動は再生成なしでshellへ到達しました。
          - [x] concurrent HTTP exampleを転送して明示実行する。PicoModemで6,490 bytesすべてを
            CRC32 `a659813e`付きで`/home/issue22_current_core_d392ce47.rb`へ転送しました。
            最大3並列・20 requestを3周し、3周とも高速に完了して合計60/60でした。log上も
            全requestでresponse writeとclient closeが完了し、serverはaccept待ちへ復帰しました。
            Ctrl-C後は`Stopping HTTP server`、`AP active?: false`を表示し、cleanup errorなしで
            shellへ戻りました。
          - [x] 比較成功後、request parseとresponse buildの一時markerを削除する。公開する
            診断exampleには既存のaccept、request read、response write、client closeの境界logを
            残す。
          - [x] 再検証結果をIssue #22へコメントし、`completed`としてcloseする。
            https://github.com/vestige/picoruby-cyw43-ap/issues/22#issuecomment-5954908956
        <!-- 以下の#516診断メモは過去の経緯として残します。 -->
        <!--
        - [ ] Core #516は、次の診断方針を結果に応じて見直しながら進める。
          - 現時点では、#509のCore `95bf98ac`でも後続実行が7/20で停止していたため、
            #513で新しく発生した回帰とは判断しない。#513以後の変更が再現頻度へ
            影響した可能性は残す。
          - USB診断ログにより、`altcp_write`、`altcp_output`、`lwip_end`は完了し、
            その直後の`cyw43_arch_poll()`が戻らない実行を確認済み。送信後のpollだけを
            削除した比較版は1/20、続く実行は0/20となり、Ctrl-Cでも復帰しなかった。
            必要な通信処理も止めるため、pollの単純削除は修正案として採用しない。
          - 元の送信後pollを戻し、lwIPタイマー、CYW43ドライバー、次回タイマー更新の
            ワーカー境界を追跡しました。最初の3 probeを処理した実行では全ワーカーが
            戻りましたが、続く0/20実行ではaccept側のpollへ一度も戻らず、
            `Task::Queue#pop`で待機したままでした。pollしなければ接続イベントが発生
            せず、そのイベントを待つためpollへ戻れない循環待ちを確認しました。
          - mrubyでは既に使われているscheduler serviceのCYW43 pollをmruby/cにも
            適用する最小比較版を試しました。この版はaccept待機を越えましたが、
            2/20の後、5番目の接続の`client.write`から戻らず、Ctrl-Cにも応答しません
            でした。したがってaccept待機の循環とTCP送信中の停止は二段階で存在し、
            scheduler poll追加だけでは全体を修正できないと判断します。
          - 次はscheduler poll追加を最終案にせず、Pico SDKの公開された
            `threadsafe_background`方式を現行Coreへ必要最小限だけ適用してA/B比較する。
            過去の`e83b87ae`全体は古いsocket変更を含むためcherry-pickせず、build define、
            CMake link、poll条件だけを現行コードに合わせて移す。accept待機と送信停止の
            両方が消えるかを確認する。
          - [x] 現行Core `729d9d55`の一時worktreeで、公開された
            `threadsafe_background`構成へ切り替えた比較用firmwareをbuildする。
            scheduler-poll実験は取り除き、build define、CMake link、socket通知の
            poll依存条件だけをbackground方式へ合わせました。UF2は3,896,320 bytes、
            SHA-256は
            `0b6d6e20546349b821ffa0319971a5f91013c244fbe8b7b6b32d41b82da9e298`
            です。Coreの通常checkoutは変更していません。
          - [x] 起動時の比較条件を整理する。FLASHに残っていた別firmware由来の
            `/bin/wifi_connect`はbackground版でcompileできず、AP試験前に起動が
            止まりました。既知の救援用firmwareで起動し、生成物を退避してから
            background版を再度書き込み、同版の`wifi_connect`が再生成されてshellへ
            到達することを確認しました。`/home/app.rb`は
            `/home/app.rb.pre-background-20260928`へ退避し、以後はAPを自動起動せず、
            PicoModemで`/home/background_test.rb`へ転送して明示実行します。
            `/bin`はboot時に同梱コマンドへ同期されるため、退避した旧
            `wifi_connect`生成物は残りませんでしたが、救援用UF2から再現できます。
          - [x] background版の最初の同時request試験へRuby markerを追加する。
            最初のmarkerなし実行はブラウザが0/20で、Connection 3の
            `request read complete`後、`response write start`前に停止しました。
            request line、path、probe queryの解析、response生成、writeの境界を分けた
            marker版では1/20でした。テストページと最初のprobeは全marker、write、closeを
            完了し、その後の`Waiting for connection`で次のacceptへ進みませんでした。
            Ctrl-Cにも5秒以上応答しませんでした。したがって今回はwrite停止ではなく、
            background callbackによる次の接続の受付、またはcallbackとRuby側
            `accept_nonblock`の間の状態通知・可視性を次の対象にします。
          - [ ] background callback内では出力やRuby APIを呼ばず、accept callbackの
            呼出回数、pending socketなし、accepted socket設定完了を数値counterだけで
            記録する。counterはRuby側の安全な`accept_nonblock`文脈から出力し、次の
            接続がlwIPまで届いていないのか、届いた状態をRuby側が観測できないのかを
            分離します。callbackで`Task::Queue`を直接操作する案は、background実行文脈
            からVMを触る安全性を確認できるまで採用しません。
          - [ ] marker追加後、同じbackground版・同じ明示実行手順で再起動をまたいで
            最低2回確認する。各回についてブラウザ結果、最後のserial marker、Ctrl-C
            応答、AP停止、socket解放、shell復帰の成否を記録します。停止位置が一致
            しない場合は、再現頻度だけでなく各停止位置を別々に扱います。
          - [ ] [Core #516](https://github.com/picoruby/picoruby/issues/516) への次の英語返信は、
            上記marker試験と再起動をまたぐ最低2回のbackground比較が完了した時点で
            行います。成功・失敗のどちらでも、poll版との差、正確な最後のmarker、
            Ctrl-Cとcleanup結果、比較用変更が未確定の診断実装であることを記載します。
            現在の0/20および1/20だけでは停止位置が従来と異なるため、まだ返信しません。
          - [x] [Core #510](https://github.com/picoruby/picoruby/issues/510) への次の英語返信に
            必要な独立再検証を完了しました。APとsocketを使わない最小`Interrupt` probeを、
            上記のCore-only条件で再起動をまたいで40回実行し、すべてshellへ復帰しました。
            #516のhangを根拠にせず、両Issueは引き続き別問題として扱います。英語返信
            自体も上の独立項目として完了しました。
          - background版が成功しても直ちに最終修正とはせず、poll版との違い、callback
            実行文脈、mruby/mruby-c両方への影響を整理する。失敗する場合は#509の
            `95bf98ac`にも同じ停止位置の診断を適用して再現頻度を比較する。
          - 原因を特定してから、公開APIの範囲で最小の修正を作る。タイムアウトは
            安全装置としては検討できるが、通信状態の破損や無限処理を隠すだけなら
            根本修正とは扱わない。
          - 修正前後を同じPico 2 Wと同じテスト条件で比較する。修正後は最大3並列の
            20 requestを最低3周、AP再接続、Ctrl-C、AP停止、socket解放、shell復帰を
            確認する。原因や観測結果が仮説と異なる場合は、この順序と修正候補を
            更新してから次へ進む。
        -->
      - [x] [Issue #29](https://github.com/vestige/picoruby-cyw43-ap/issues/29)で、
        再接続とクライアントWi-Fiの復旧を検証する。
        - [x] 最新の`main` `9ad0375`から専用branch
          `issue-29/ap-reconnect-validation`を作る。検証開始時のCore upstream `master`は
          `d392ce47`です。boardはPico 2 W、VMはmruby/cを使用する。
        - [x] 初回AP接続は短時間で完了し、DHCPでIP address `192.168.4.2`、
          subnet mask `255.255.255.0`、router `192.168.4.1`を取得した。
        - [x] 同じboot内でAPを停止し、SSIDが一覧から消えることを確認した。
        - [x] 同じboot内でAPを再度有効化し、同じclientが短時間で再接続した。
          DHCP情報は初回と同じ`192.168.4.2`、`255.255.255.0`、`192.168.4.1`だった。
        - [x] 初回と再接続後の両方で、AP停止後にclientが通常利用しているWi-Fiへ自動で
          復旧し、インターネット接続を利用できることを確認した。
        - [x] 2回ともCtrl-C、HTTP server停止、`AP active?: false`、cleanup errorなし、
          shell復帰を確認した。初回接続時にブラウザへ残っていた試験ページが実行した
          20 requestも20/20成功した。結果をIssueへ記録し、`completed`としてcloseした。
          https://github.com/vestige/picoruby-cyw43-ap/issues/29#issuecomment-5966735758
- [x] [Issue #31](https://github.com/vestige/picoruby-cyw43-ap/issues/31)で、
      Pico TimerのAP版フィジビリティとブラウザ向け動作を実装する。
      - [x] `main` `11317f6`から専用branch
        `issue-31/pico-timer-feasibility`を作る。検討開始時のCore upstream `master`は
        `d392ce47`です。
      - [x] 古い`codex/pcw-timer-replacement`は資料としてだけ読み、現在のCoreへbranch
        全体を移植しない。純粋なTimerロジックとUIのうち再利用できる部分だけを選んだ。
      - [x] 過去のSTA exampleに含まれる認証情報を新しい実装へ持ち込まない。新規ファイルに
        含まれないことを検索でも確認した。現在も有効な場合は利用者側で変更し、remote
        branchの扱いは別途明示的に判断する。
      - [x] 現在の`CYW43::AP` APIと検証済みHTTP server lifecycleを使い、秒数設定、開始、
        停止、reset、残り時間・状態表示を持つ最小AP Timer example
        `example/pico_w_ap_timer.rb`を実装した。自動pollingは行わず、状態は手動reloadで
        更新する。response bodyは512 bytes単位で送信する。
      - [x] 最新Coreの`Machine.board_millis`がmruby/c・mrubyの両方で公開されていること、
        HTML/responseサイズ、分割送信、host smoke test可能範囲を確認した。Timer状態と
        全routeを`example/pico_w_ap_timer_host_smoke.rb`で検証し、CRubyとPicoRuby hostの
        両方でpassした。両ファイルのPicoRuby `mrbc`コンパイルも成功した。
      - [x] 一時Core worktreeでPico 2 W + mruby/cをbuildし、通常のCore checkoutを変更しない。
        Core `d392ce47`、3,914,752 bytes、SHA-256
        `ce64d21d2f80254a2223043ec18dfac3b8a6d2c4392e8f32aa004cb39f080fd9`のUF2を生成した。
      - [x] 実機でTimer全体を再試行する前に、旧実装と現在の実行条件を切り分ける。
        旧AP TimerはCore `b526e123`のWIPで、READMEは実機完走を明記していない。
        後から追加されたfirmware埋め込みの専用VM起動はSTA Timer用であり、旧AP Timerと
        現在のshell `Sandbox#load_file`実行を同条件とは扱わない。段階的probeでは、`.mrb`
        読込・require・定数定義・local variable代入・通常class instanceへの代入は成功し、
        module自身のinstance variable代入で停止した。Timer状態を通常classへ移すと
        AP起動とブラウザ表示まで成功した。
      - [x] 実機で画面表示、Timer操作と満了、reload後の状態、Ctrl-C、AP cleanup、shell復帰、
        通常Wi-Fiへの復旧を確認する。画面表示、Set/Start/Stop/Reset、満了、Ctrl-C、
        `AP active?: false`、shell復帰は確認済み。修正前はボタン後の表示にStart約3秒、
        Stop約3〜6秒かかったとの報告があり、serialに`HTTP request timeout`と
        `send failed`を観測した。timing markerでは有効なStart/StopのHTTP処理は各8ms以内。
        その前にブラウザから来たデータなしの接続を約5.6秒待つ例があり、後続requestを
        遅らせていた。最初の1 byteだけ500msで打ち切り、データ受信後のheader期限は5秒を
        維持した結果、空の接続は約0.56秒で終了した。診断表示を外した版でもStart/Stopは
        1回で速く反映された。最後のCtrl-Cで再度AP無効化とshell復帰を確認済み。
        SSIDがWi-Fi一覧から消え、クライアントが通常Wi-Fiへ戻りインターネット接続も
        復旧したことを利用者が確認した。
      - [x] 検証結果をREADME、日英TODO、Issueへ記録する。
        https://github.com/vestige/picoruby-cyw43-ap/issues/31#issuecomment-5980469546
      - [x] コードと文書の差分を利用者とレビューし、承認後に`46fd211`をcommitし、
        [PR #32](https://github.com/vestige/picoruby-cyw43-ap/pull/32)をmergeした。

## PicoRuby coreの参照情報

coreリポジトリ: `/Users/vestige/Spike/picoruby`

外部gemのレビュー済み初回コミットが作成され、移行したコードの由来が文書化
されるまでは、次の参照情報を保持します。

- `codex/cyw43-ap-dhcp-review` / `c94d9808`: PR #489のAP/DHCPコードを統合したもの。
- `codex/cyw43-ap-review` / `44d01d06`: PR #489の段階的な開発履歴。
- `codex/sta-connect-retry-once-example` / `e83b87ae`: STAサンプルとsocketの
  background handling。この外部gemの開発ブランチではない。
- `codex/pcw-timer-replacement` および `codex/cyw43-ap-*` ブランチ: 以前のAP、
  HTTP、timer、socketの実験。

### 後で行うブランチ整理

- [ ] `origin` と `upstream` の両方をfetchし、現在の先端を記録する。
- [ ] 削除前に各候補を `git branch -vv`、`git branch --merged`、
      `git branch --no-merged` で確認する。
- [ ] ローカルブランチを削除する前に、PR #489のコミットをtag、remote branch、
      または記録したcommit IDで保全する。
- [ ] `git worktree list` を実行し、現在も存在するworktreeを確認する。
- [ ] `git worktree prune` は明示的に `prunable` と表示された項目にだけ使い、
      稼働中の検証worktreeを推測で削除しない。
- [ ] `master`、`codex/master-reset`、serial-runnerブランチ、timerブランチは、
      それぞれ独立した整理判断として扱う。
- [ ] 通常のローカル整理の一環としてforce-pushやremote branch削除を行わない。

## 検証用コマンド

このgemを参照する一時PicoRuby worktreeから実行します。

```sh
PATH=/opt/homebrew/opt/ruby/bin:$PATH \
  rake r2p2:femtoruby:pico2_w:prod

PATH=/opt/homebrew/opt/ruby/bin:$PATH \
  rake r2p2:picoruby:pico2_w:prod

PATH=/opt/homebrew/opt/ruby/bin:$PATH \
  R2P2_NO_SHARED_ALLOC=1 rake r2p2:femtoruby:pico_w:prod
```

以前の検証worktreeは
`/private/tmp/picoruby-cyw43-ap-validate.C09rUr` です。これは破棄可能なビルド
基盤であり、このgemのsource of truthではありません。
