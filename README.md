# CreateDungeonAndManagement3D（仮題：ダンジョン生態系）

「勇者のくせになまいきだ」（初代）× 「風来のシレン6」風の見下ろし3Dで、
**ダンジョンを掘って魔物の生態系を育て、攻めてくる勇者を魔物で撃退する** ゲームです。
現在は **ステージ1** まで遊べます（ダンジョンは次ステージへ引き継がれます）。

- エンジン: **Godot 4.7**（GDScript / Forward+）
- 目標プラットフォーム: Windows（Steam）

## 起動方法

1. Godot 4.7 Standard 版をインストール
2. Godot で `project.godot` を開き、F5 で実行
   - コマンドラインの場合: `Godot_v4.7.x_win64.exe --path .`

## exe のビルド（Windows）

```bash
godot --headless --export-pack "Windows Desktop" build/windows/DungeonEcosystem.pck
```

`build/windows/` に Godot 実行ファイルを `DungeonEcosystem.exe` として置くと、同名の `.pck` を読み込んで起動します。
公式エクスポートテンプレートを入れた場合は `godot --headless --export-release "Windows Desktop"` で単体の exe を出力できます（Steam 配布向け）。

## 操作

| 操作 | 内容 |
| --- | --- |
| 左クリック | ブロックを掘る / 魔王の配置場所を決める |
| WASD / 矢印 / 画面端 / 右ドラッグ | カメラ移動 |
| マウスホイール | ズーム |
| Space | （建設中）勇者を呼ぶ |
| F | （侵攻中）勇者をカメラで追う / 解除 |
| F12 | スクリーンショット（`user://`） |

## ゲームの流れ

タイトル → 勇者来訪カットイン → **建設フェーズ**（150秒 or「勇者を呼ぶ」）→ **魔王配置** →
勇者出現カットイン → **侵攻フェーズ**（掘り続けられる）→ 勝利 → **リザルト**（撃退タイムと残り採掘数で進化ポイント）
→ 進化ポイントを「掘削上限」「モコゴケ進化」「ザクザクムシ進化」に割り振り → 次のステージ（ダンジョン・魔物を引き継ぎ）

- 勝利条件: 勇者のHPを0にする
- 敗北条件: 勇者が魔王を入口まで運ぶ

## 生態系（ニジリゴケ／ガジガジムシの関係を参考にしたオリジナル設計）

養分は **保存量** です。土・魔物の間を移動するだけで、魔物が死ぬと周囲の土に戻ります。

| 魔物 | 役割 | 仕様 |
| --- | --- | --- |
| **モコゴケ**（被食） | 養分の運び屋 | 養分1〜9の土を掘ると誕生。壁に当たるまで直進し、隣の土と養分をやり取り（所持1なら吸収、2以上なら放出）。養分2以上・HP2以下で **ツボミ** に根付き、5×5から養分を集めて8で **モコバナ** に開花。寿命で最大5匹の子を生む（繁殖） |
| **ザクザクムシ**（捕食） | モコゴケを食べる | 養分10以上の土で誕生。空腹になるとモコゴケを探して食べる。HP60で **サナギ** → 20秒で **成虫**。成虫は養分とHPを使って幼虫を産む。勇者に近いと襲いかかる |

数値はすべて [`scripts/core/balance.gd`](scripts/core/balance.gd) にまとまっています。

## モデルの差し替え

### 勇者
[`data/heroes/allen.tres`](data/heroes/allen.tres)（`HeroProfile` リソース）の `model_path` を差し替えるだけです。
- `model_height`: 画面上の身長（1 = ブロック1個分。自動で足元を床に合わせます）
- `anim_idle` / `anim_walk` / `anim_attack`: GLB 内のアニメーション名
- `attack_hit_time`: 攻撃アニメの何秒目でダメージを与えるか
- ステータス（HP/MP/攻撃/移動速度など）も同じファイルで調整できます

現在は `assets/models/hero/hero.glb`（idle / walk / attack）を使用しています。

### 魔物・魔王・ツルハシ
[`scripts/sim/monster_catalog.gd`](scripts/sim/monster_catalog.gd) のパスを差し替えます。以下のアニメーション名に対応していれば、そのまま動きます。

| モデル | アニメーション |
| --- | --- |
| moss（モコゴケ） | idle, move, absorb, attack, hurt, die, spawn |
| moss_bud（ツボミ） | idle, absorb, hurt, die, spawn |
| moss_flower（モコバナ） | idle, absorb, spawn_child, hurt, die, spawn |
| bug_larva（幼虫） | idle, move, attack, eat, hurt, die, spawn |
| bug_pupa（サナギ） | idle, hatch, hurt, die, spawn |
| bug_adult（成虫） | idle, move, attack, lay_egg, hurt, die, spawn |
| maou（魔王） | idle, carried, scared, cheer, land |

モデルは +Z 向き、1ユニット = ブロック1個分、足元を原点にしてください。

## 魔物モデルの生成（tools/modelgen）

魔物・魔王・ツルハシの 3D モデルとアニメーションは、外部依存なしの Node.js スクリプトで **SDF モデリング → メッシュ化 → スキニング → キーフレーム → GLB 出力** しています。

```bash
node tools/modelgen/build.mjs            # 全モデルを assets/models/monsters/ に出力
node tools/modelgen/build.mjs bug        # 名前に "bug" を含むモデルだけ
node tools/modelgen/preview/serve.mjs    # http://localhost:5178 でブラウザプレビュー（three.js）
```

`tools/` は `.gdignore` で Godot の読み込み対象から外しています。

## テスト・デバッグ

```bash
# 生態系の耐久シミュレーション（ヘッドレス）
godot --headless -s res://scripts/debug/sim_test.gd -- 450 90
# 本番フローを自動プレイ（タイトル→掘削→魔王配置→侵攻→リザルト）
godot -- --autoplay --seed=4 --shots_every=900
# 侵攻のヘッドレス検証
godot --headless -- --autostart --seed=1 --digs=70 --simulate=120 --invade --hero_time=240 --report --quit_after=5
```

主なデバッグ引数（`--` の後ろに指定）: `--autostart` `--seed=N` `--digs=N` `--simulate=秒` `--invade` `--hero_time=秒` `--shot=path.png --frames=N` `--cam=x,z[,zoom]` `--fps`

## フォルダ構成

```
scenes/main.tscn            メインシーン（ほぼコードで構築）
scripts/main.gd             ゲームフロー
scripts/core/               バランス値・ステージ定義
scripts/dungeon/            グリッド（ロジック）/ 描画 / 街の背景 / 松明 / 手続き生成
scripts/sim/                生態系シミュレーション / 魔物の表示
scripts/actors/             勇者 / 魔王 / モデルラッパー / 勇者プロフィール
scripts/player/             カメラ / ツルハシカーソル
scripts/ui/                 HUD / カットイン / タイトル・リザルト / テーマ
scripts/autoload/           GameState（ステージ間の持ち越し）/ Sfx（合成サウンド・BGM）
shaders/                    ブロック・床・炎
assets/models/              勇者 GLB / 生成した魔物 GLB
data/heroes/                勇者プロフィール（.tres）
tools/modelgen/             魔物モデル生成ツール
```

## 今後（10ステージ化・Steam 向け）

- `scripts/core/stage_defs.gd` にステージを追加（勇者の種類・倍率・建設時間）
- Steam: GodotSteam（実績・クラウドセーブ）、日本語フォントの同梱（現在はOSフォント）
- セーブ／ロード（`GameState` と `DungeonGrid.to_dict()` / `Ecosystem.to_array()` を利用）
- 魔物の種類追加（魔分・トカゲおとこ相当など）、勇者のスキル
- 低スペックPC向けの最適化（魔物メッシュの LOD、影の距離）
