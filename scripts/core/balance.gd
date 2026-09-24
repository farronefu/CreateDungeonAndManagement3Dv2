class_name Balance
extends RefCounted
## Gameplay tuning values. Everything numeric that designers may want to tweak lives here.

# --- dungeon ---
const GRID_W := 36
const GRID_H := 26
const BLOCK_H := 0.9
const MAX_NUTRIENT := 16

# --- phases ---
const BUILD_TIME := 150.0
const DIG_MAX_BASE := 100

# --- nutrient -> spawned monster ---
const MOSS_SPAWN_MIN := 1   # 養分 1〜9 → モコゴケ
const BUG_SPAWN_MIN := 10   # 養分 10〜16 → ザクザクムシ

# --- モコゴケ (prey) ---
const MOSS_HP := 16
const MOSS_HP_MAX := 21
const MOSS_STEP_TIME := 1.15
const MOSS_ABSORB_HEAL := 4
const MOSS_ATK := 3
const MOSS_ATTACK_CD := 1.6
const BUD_HP := 12
const BUD_TARGET := 8          # nutrient needed for ツボミ → モコバナ
const BUD_ABSORB_INTERVAL := 1.4
const FLOWER_HP := 20
const FLOWER_MAX_NUTRIENT := 11
const FLOWER_LIFE := 32.0      # seconds until the flower scatters its children
const FLOWER_CHILDREN := 5

# --- ザクザクムシ (predator) ---
const LARVA_HP := 36
const LARVA_HP_MAX := 70
const LARVA_HUNGRY := 40
const LARVA_PUPATE := 60
const LARVA_STEP_TIME := 0.9
const LARVA_ATK := 5
const BUG_METABOLISM := 2.2    # seconds per 1 HP lost
const BUG_SIGHT := 4           # manhattan range to notice prey
const EAT_HEAL := 18
const PUPA_TIME := 20.0
const ADULT_HP_MAX := 95
const ADULT_STEP_TIME := 0.7
const ADULT_ATK := 9
const ADULT_HUNGRY := 55
const ADULT_LAY_HP := 40
const ADULT_LAY_NUTRIENT := 8
const ADULT_LAY_COST_HP := 10
const ADULT_LAY_COOLDOWN := 22.0
const ADULT_LIFE := 120.0
const BUG_ATTACK_CD := 1.3
const ADULT_AGGRO_RANGE := 4

# --- population caps (performance) ---
const MAX_MOSS := 70
const MAX_BUGS := 30

# --- evolution points (result screen) ---
const EP_BASE := 40
const EP_TIME_BONUS_MAX := 100   # minus 1 per EP_TIME_STEP seconds of invasion
const EP_TIME_STEP := 3.0
const EP_PER_DIG_LEFT := 1

# --- upgrades: id -> { name, desc, cost, max } ---
const UPGRADES := {
	"dig": {"name": "掘削上限アップ", "desc": "採掘可能数の上限 +10", "cost": 40, "max": 10},
	"moss": {"name": "モコゴケ進化", "desc": "HP・攻撃 +25%、モコバナの子 +1", "cost": 80, "max": 3},
	"bug": {"name": "ザクザクムシ進化", "desc": "HP・攻撃 +25%、成長が早くなる", "cost": 80, "max": 3},
}
