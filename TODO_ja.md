# 開発TODO

この文書は、開発状況とPicoRuby coreから分離して進める必要がある作業を
記録するものです。マイルストーンや検証結果が変わったときは、英語版の
`TODO.md` とこの日本語版を同時に更新します。今後の進め方や方針は、まず
この日本語版で確認してから作業します。

## 想定しているユースケース

- Raspberry Pi Picoを屋外へ持ち出し、スマホのテザリングなど既存の
  ネットワークへSTAとして接続して、スマホからPicoを操作する。
- 既存のネットワークがない場所ではPico自身をAPにし、スマホとPicoの間だけで
  直接通信できるスタンドアローン環境を用意する。
  - 例えば、簡易タイマーの操作やラジコンのリモコンとしてスマホを使う。

このgemの主な役割は後者のAP/DHCP基盤を提供することです。実際の操作画面や
HTTP通信は後続マイルストーンで扱い、既存のSTA用途を壊さないことも確認します。

## 現在の状態（2026-09-09）

- このリポジトリは第三者mrbgem `picoruby-cyw43-ap` です。
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
- [ ] `CYW43.init(force: true)` 実行時のcleanupを確認する。
- [ ] 既存のSTA専用プログラムが以前と同じように動作することを確認する。

基板、BOOTSELボリューム、シリアルデバイス、シリアルポートの所有プロセスを
一意に特定できない限り、実機へ書き込まないでください。検証専用のPicoRuby
build config変更は、一時worktree内だけに保持します。

## 後続マイルストーン

AP/DHCPマイルストーンが安定してから開始します。

- [ ] PicoRuby coreの外部に最小構成のHTTPサーバー例を追加する。
- [ ] `accept`、`recv`、`close` の繰り返しlifecycleをテストする。
- [ ] リロード、複数タブ、再接続、クライアントWi-Fiの復旧をテストする。
- [ ] Pico Timerアプリケーションとブラウザ向け動作を再検討する。

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
