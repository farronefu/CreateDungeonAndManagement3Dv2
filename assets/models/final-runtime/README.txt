MonsterChain 最終版ランタイムモデル集 / Final Runtime Models
2026-10-03

このZIPに入っているもの
・最終修正版GLB 9点（models/）
・manifest.json：正確なファイル名、バイト数、SHA-256、版、既存の対応先とスケール
・SHA256SUMS.txt：展開後の照合用
・この説明書
編集用Blenderファイル、元モデル、動画は含みません。GLBの中身は納品済み最終版と完全に同じです。

使い方
1. ZIPを1つのフォルダーに展開してください。自動インストーラーではありません。
2. models/内のGLBをゲームへ取り込みます。manifest.jsonのSHA-256で旧版との取り違えを防いでください。
3. 既存コントローラーのアニメーション名、イベント、倍率を維持し、ゲーム上で動作確認してください。
既存コードの確認対象コミット：fa9a2a7b6110a1fafc35a38651d9b7c8c9e04bcd

版の見分け方
・モコチュリ v2：緑の吸収エフェクト＋目の奥行き修正
・魔王通常／捕獲 v1：元の顔・髪・服・体型に合わせた修正版
・成虫／虫進化 v1：4枚羽の羽ばたき修正版
・ツボミ／モコバナ v1：太く尖らせた攻撃ツタ
・草進化 v1：目の修正、進化終了時のサイズ整合、残留エフェクト除去
・ブレイカー v0：最終版（この機器には追加改訂なし）

Integration contract
Axes: glTF/Godot +Y up, +Z forward. Keep authored origins, hierarchy and source units.
Do not normalize height, bake a second scale, flatten meshes, or rename bones/clips.
Actor scales: breaker .45; king/captured .47; adult insect .30; insect evolution .38;
moss .37; bud .29; flower .37; plant evolution .37.

IMPORTANT SHARED TREE RESOURCE
Tsubomi and Mokobana are alias exports of the SAME source-sized tree geometry.
Both current catalog entries use res://assets/models/grass/tree.glb, at .29 and .37.
Their file hashes differ because their alias metadata differs. Keep the shared resource
or use two explicit resource paths; do not overwrite one tree path twice assuming two shapes.
No scale is baked for those catalog multipliers. The unlisted shared master is not required.

Clips and game timing (native clip seconds unless noted)
Moss: walk1.0 (move alias, ordinary game step1.15), attack1.5 (game1.0),
  gather4.0 (absorb alias, game1.6), die1.933333.
Both trees: attack1.5 (game1.0), die1.933333. Attack impact stays at game .44s.
Plant evolution: Scene7.0 once, actor .37. End subtree already has .29/.37 correction.
  Keep Sprout_Mesh_01, its texture-backed first surface, autumn.gdshader and evolution-color.json.
  The shader still owns the animated color transition. Do not apply a second scale correction.
Adult insect: Hover .8, Fly .8, Attack1.4, LayEgg1.5, Death1.5.
  idle→Hover; move→Fly; attack/eat→Attack; lay_egg→LayEgg; die→Death.
  Existing game attack .6s, eat1.0s, ordinary move .7s. Hit .264s; egg event1.0s.
  Retain tail_tip skeleton bone. Existing eat alias marks shared Attack looping;
  retain the play_once/busy-timer behavior rather than changing it silently.
Insect evolution: Evolve3.5 once at actor .38. Its .30/.38 endpoint scale is already present.
  Wing end phase matches Hover0 relative to thorax. A small original body-pose difference remains.
King: idle3.0 and cower1.0 loop; look_around6.333333, cower_in.8, cower_out.8 one-shot.
Captured: struggle1.2 loops via idle alias. Preserve existing XZ AABB centering.
  Captured head faces +Z, origin near the legs.
Breaker: keep catalog anim map EMPTY; actual dig_cursor.gd owns all motion.
  HoverCycle_Preview and DigBurst_Preview are inspection aids: NEVER autoplay them with the controller.
  Keep BreakerRoot, BreakerBody, MetalChisel; MetalChisel neutral local position
  (-.039801061,1.105000019,.267682195); downward local-Y stroke.
  Current dig is three35ms extend/70ms return blows, .30/.24/.24 model-unit strokes,
  .05-world-unit recoil; yaw, tilt, hover and pivot remain controller-owned.

Loop/event ownership
GLTF has no standard engine loop flag. Preserve ModelActor loop setup and all existing
simulation hit/birth events. Moss walk/gather loop; plant attack/death/evolution do not.
Procedural hurt flashes, squash, spawn, tree absorb, flower child-spawn, king cheer,
landing/capture/drag, and breaker motion stay in runtime code. Do not add baked duplicates.
Keep the existing time_scale distinctions instead of globally retiming every animation.

Materials, bounds and physics
Preserve embedded textures, COLOR_0 vertex colors, emission and imported material flags.
fix_colors=false does not disable imported vertex colors. King face/iris textures and
insect-evolution crack emission are intentional. Moss nutrient cubes are green emissive.
Keep the existing toonify processing; do not replace all surfaces with flat materials.
Bounds exclusions are case-sensitive: Withered, Thorned, Shard, fx_, Nutrient, SwirlLeaf.
No GLB contains a collider or physics body. Existing combat/movement are simulation-owned;
do not auto-generate detailed mesh collision from these visual models.

Validation and performance
Every packed GLB is byte-identical to its verified final artifact. Standalone Blender/Godot
import/playback and motion/visual checks were completed. Full-game integration/performance
must still be tested. King normal198,304 triangles; captured128,548. Profile in-game before
reducing geometry in a way that changes the approved face or silhouette.
This package does not include the earlier completed pillbug/block model deliveries.
