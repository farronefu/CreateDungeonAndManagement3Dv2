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
| P | 一時停止 / 再開。一時停止画面でダンジョンの魔物の種類と数を確認できる |
| 中ドラッグ / Q・E / Home | カメラ回転 / リセット |
| F | （侵攻中）勇者をカメラで追う / 解除 |
| F12 | スクリーンショット（`user://`） |
| マウスを合わせる | 魔物のHP・養分・状態、土の養分量をポップアップ表示 |

### コントローラー（Xbox配置）

| ボタン | 内容 |
| --- | --- |
| 十字キー / 左スティック | カーソル移動（長押しでリピート、押し続けるほど速く。スティックを倒し切ると高速） |
| A | 掘る・決定（魔王の配置・メニュー・カットインのスキップ）。**押しながら十字キーで一直線に連続で掘る** |
| Start | 一時停止 / 再開（一時停止画面に魔物の種類と数を表示） |
| Y | （建設中）勇者を呼ぶ |
| RB | ゲーム速度 x1 → x2 → x3 |
| LB | （侵攻中）勇者をカメラで追う / 解除 |
| 右スティック | カメラアングルを自由に回転・傾け（R3 でリセット） |

マウスでも回転できます（中ボタンドラッグ / Q・E キー / Home でリセット）。コントローラー操作中は、カーソル位置の情報ポップアップと操作ガイドが表示されます。

### 画面

- 左上の黒い枠：建設中は勇者の到着までの時間と「勇者を呼ぶ」、魔王配置中は案内文、侵攻中は勇者の HP / MP
- 右上：速度（x1 / x2 / x3）
- 左下：掘れる回数
- 一時停止（Start / P）：魔物の種類と数、土の養分。一時停止中は「再開する」以外は操作できません

## ゲームの流れ

タイトル → 勇者来訪カットイン → **建設フェーズ**（150秒 or「勇者を呼ぶ」）→ **魔王配置** →
勇者出現カットイン → **侵攻フェーズ**（掘り続けられる）→ 勝利 → **リザルト**（撃退タイムと残り採掘数で進化ポイント）
→ 進化ポイントを「掘削上限」「モコチュリ進化」「ザクザクムシ進化」に割り振り → 次のステージ（ダンジョン・魔物を引き継ぎ）

- 勝利条件: 勇者のHPを0にする
- 敗北条件: 勇者が魔王を入口まで運ぶ

## 土ブロックの種類

ブロックは1マスずつ分かれた丸みのある土の塊です。**養分がたまるほど右の段階へ移ります**（魔物が養分を運ぶので、遊んでいる間にも変わります）。

| 段階 | 養分 | 見た目 | 掘ると |
| --- | --- | --- | --- |
| ① 何もない土 | 0 | 土と小石だけ | 何も生まれない |
| ② 少し植生がある土 | 1〜4 | 苔の斑点・草・短いツタ | モコチュリ |
| ③ 植生が多い土 | 5〜9 | 緑の葉が茂り、ツタが垂れる | モコチュリ |
| ④ 少し枯れた土 | 10〜12 | 緑と黄色の葉が混ざる | ザクザクムシ（ダンゴムシ） |
| ⑤ 枯れた土 | 13〜16 | 黄色く枯れた葉 | ザクザクムシ（ダンゴムシ） |

段階の境目は `scripts/core/balance.gd` の `SOIL_STAGE_MIN`、出現する魔物の境目は `MOSS_SPAWN_MIN` / `BUG_SPAWN_MIN` です。マップの外周は掘れない岩です。

## 生態系（ニジリゴケ／ガジガジムシの関係を参考にしたオリジナル設計）

養分は **保存量** です。土・魔物の間を移動するだけで、魔物が死ぬと周囲の土に戻ります。

| 魔物 | 役割 | 仕様 |
| --- | --- | --- |
| **モコチュリ**（被食） | 養分の運び屋 | 養分1〜9の土を掘ると誕生。壁に当たるまで直進し、隣の土と養分をやり取り（所持1なら吸収、2以上なら放出）。養分2以上・HP2以下で **ツボミ** に根付き、5×5から養分を集めて8で **モコバナ** に開花。寿命で最大5匹の子を生む（繁殖） |
| **ザクザクムシ**（捕食） | モコチュリを食べる | 養分10以上の土で誕生。空腹になるとモコチュリを探して食べる。HP60で **サナギ** → 20秒で **成虫**。成虫は養分とHPを使って幼虫を産む。勇者に近いと襲いかかる |

数値はすべて [`scripts/core/balance.gd`](scripts/core/balance.gd) にまとまっています。

## モデルの差し替え

### 勇者
[`data/heroes/allen.tres`](data/heroes/allen.tres)（`HeroProfile` リソース）の `model_path` を差し替えるだけです。
- `icon_path`: 勇者のアイコン（左上の枠・ツールチップで共通）。現在は `assets/ui/hero_icon.png`（元画像 `hero_icon_source.png` を 64px に縮小したもの。作り直しは `scripts/debug/make_icon.gd`）
- `model_height`: 画面上の身長（1 = ブロック1個分。自動で足元を床に合わせます）
- `anim_idle` / `anim_walk` / `anim_attack`: GLB 内のアニメーション名
- `attack_hit_time`: 攻撃アニメの何秒目でダメージを与えるか
- ステータス（HP/MP/攻撃/移動速度など）も同じファイルで調整できます

現在は `assets/models/hero/hero.glb`（idle / walk / attack）を使用しています。

### 草の魔物・木・進化演出（2026-09-24 差し替え）

提供モデル一式（Mossbound）を使用しています。

| ゲーム内 | ファイル | 使用クリップ |
| --- | --- | --- |
| 勇者 | `assets/models/hero/hero.glb` | idle / walk / attack / death（死亡）/ joy（魔王を見つけて喜ぶ）/ look_around（分かれ道で見回す） |
| モコチュリ（草の魔物） | `assets/models/grass/grass.glb` | walk（移動）/ attack（体当たり、0.44 の位置で命中）/ gather（養分吸収）/ die（枯れて粒になって消える）。idle は walk の先頭姿勢から生成 |
| ツボミ・モコバナ（進化後の木） | `assets/models/grass/tree.glb` | attack（トゲの根で隣のマスを突き刺す、0.44 で命中）/ die（枯れて粒になって消える）。idle は attack の先頭姿勢。吸収・被弾はゲーム側の揺れで表現 |
| ザクザクムシ 幼虫（ダンゴムシ幼体） | `assets/models/pillbug/juvenile-pillbug.glb` | Walk（移動）/ Attack（体当たり・捕食、44% で命中）/ Death（粉々に割れて消える） |
| ザクザクムシ サナギ | 同上 | Curl（幼虫からサナギになる時に丸まる）→ CurlIdle（丸まったまま呼吸）/ Uncurl（羽化の直前に戻る）/ Death |
| ザクザクムシ 成虫（鎌と羽の魔物） | `assets/models/broad-scythe/broad-scythe.glb` | Fly（移動）/ Hover（待機）/ Attack（鎌の二段斬り・捕食）/ LayEgg（尻尾を地面に振り下ろし、接地した瞬間＝1.0秒目に尻尾の先 `tail_tip` から幼虫が1匹生まれる）/ Death |
| サナギ → 成虫の進化演出 | `assets/models/broad-scythe/pillbug-to-scythe-evolution.glb` | Evolve（3.5秒：丸まったダンゴムシが割れて成虫が飛び出す） |
| 進化演出 | `assets/models/grass/evolution.glb` + `evolution-color.json` + `shaders/autumn.gdshader` | モコチュリがツボミになる時に 7 秒再生（秋色への色変化つき） |

### 魔物・魔王・ツルハシ
[`scripts/sim/monster_catalog.gd`](scripts/sim/monster_catalog.gd) のパスを差し替えます。クリップ名が違う場合は `anims` で対応付けできます（例: `{"move": "walk", "absorb": "gather"}`）。無いクリップは揺れ・ポップ・縮小などで自動的に代用します。

旧来の生成モデルの対応アニメーション:

| モデル | アニメーション |
| --- | --- |
| moss（モコチュリ） | idle, move, absorb, attack, hurt, die, spawn |
| moss_bud（ツボミ） | idle, absorb, hurt, die, spawn |
| moss_flower（モコバナ） | idle, absorb, spawn_child, hurt, die, spawn |
| bug_larva（幼虫） | idle, move, attack, eat, hurt, die, spawn |
| bug_pupa（サナギ） | idle, hatch, hurt, die, spawn |
| bug_adult（成虫） | idle, move, attack, lay_egg, hurt, die, spawn |
| maou（魔王） | idle, carried, scared, cheer, land |

モデルは +Z 向き、1ユニット = ブロック1個分、足元を原点にしてください。

## 見た目の方針

画風を「3D＋トゥーン調」に統一しています。

- **地上の町はボクセルアート**（`scripts/town/`）：道の奥に、左から城・家×2・防具屋｜洞窟｜武器屋・教会・宿屋が並び、すべてプレイヤー側を向いています。宿屋は添付の `voxel-inn.html` をそのまま移植し、ほかの建物も同じ作り方（1ボクセル＝0.22マス、8×8の質感ノイズ、窓とランタンは発光）でコードから生成しています（`town_models.gd`）。建物の奥はボクセルの森と山並み。地面は草のボクセルタイル（`shaders/town_ground.gdshader`）と石畳の道で、柵・街灯・井戸・荷車・樽・木箱・茂み・花・草むらも配置（`surface_world.gd`）。勇者は道から岩山のアーチをくぐり、スロープを下ってダンジョンに入ります。モデル生成は起動時に約0.5秒
- **地面**：1マスずつ細い隙間で分かれた丸みのある土ブロック（段階は「土ブロックの種類」を参照）。上面は明るく側面は暗くして立体感を出し、土・苔・草の模様は3段階の階調で塗り分け。掘った通路の床は暗い土色にして、魔物が目立つようにしています
- **地上とダンジョンの境目**：地上の草原とダンジョンの土は同じシェーダーで塗り分けているため、背景が漏れる隙間はありません
- **仕上げの画面処理**（`shaders/post.gdshader`）：輪郭線・色調補正・画面端を暗くする処理と、遠景ぼかし（建物の奥の森と山ほど強くぼける。`town_blur_*` で調整）。キャラクターのモデルにはトゥーン調の光沢と弱いリムライトを自動で付与
- **照明**：描画レイヤー（`scripts/core/render_layers.gd`）でライトを分けています。太陽は地上（町と最上段の草ブロック）だけを照らし、地下は落ち着いた洞窟光で奥ほど暗く、魔物・勇者・魔王には専用のキーライトとリムライトが当たるので地下でも鮮やかなまま
- **UI**：ドット絵風のウィンドウ枠（輪郭線＋ベベル）。フォントはドット文字の DotGothic16 を同梱（SIL OFL、`assets/fonts/`）
- 松明は置いていません（最初の通路にも、掘った後にも置かれない）

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
scripts/dungeon/            グリッド（ロジック）/ 描画 / 地上の配置 / 松明 / 手続き生成
scripts/town/               ボクセルモデル生成（VoxelBuilder）/ 町の建物・木・山（TownModels）
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
