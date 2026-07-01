extends Node

const JA := "ja"
const EN := "en"

var language: String = JA

const TEXT := {
	"CLICK  TO  START": {
		"ja": "クリックでスタート",
		"en": "CLICK  TO  START",
	},
	"PRESS ENTER / CLICK TO START": {
		"ja": "ENTER / クリックでスタート",
		"en": "PRESS ENTER / CLICK TO START",
	},
	"LANGUAGE": {
		"ja": "言語",
		"en": "LANGUAGE",
	},
	"Japanese": {
		"ja": "日本語",
		"en": "Japanese",
	},
	"English": {
		"ja": "英語",
		"en": "English",
	},
	"JAPANESE": {
		"ja": "日本語",
		"en": "JAPANESE",
	},
	"ENGLISH": {
		"ja": "英語",
		"en": "ENGLISH",
	},
	"GAME OVER": {
		"ja": "ゲームオーバー",
		"en": "GAME OVER",
	},
	"CLICK  TO  CONTINUE": {
		"ja": "クリックでコンティニュー",
		"en": "CLICK  TO  CONTINUE",
	},
	"ALT": {
		"ja": "高度",
		"en": "ALT",
	},
	"LIFE": {
		"ja": "ライフ",
		"en": "LIFE",
	},
	"SCORE": {
		"ja": "スコア",
		"en": "SCORE",
	},
	"EXP": {
		"ja": "経験値",
		"en": "EXP",
	},
	"BOOST": {
		"ja": "ブースト",
		"en": "BOOST",
	},
	"RANK": {
		"ja": "ランク",
		"en": "RANK",
	},
	"DURABILITY": {
		"ja": "耐久",
		"en": "DURABILITY",
	},
	"GOLDEN": {
		"ja": "ゴールデン",
		"en": "GOLDEN",
	},
	"HUBRIS": {
		"ja": "慢心",
		"en": "HUBRIS",
	},
	"UNLOCKING": {
		"ja": "解除中",
		"en": "UNLOCKING",
	},
	"MAX NO FIRE": {
		"ja": "MAX 撃てない！",
		"en": "MAX NO FIRE",
	},
	"MID-BOSS: HUBRIS SUSPENDED": {
		"ja": "中ボス戦：慢心は一旦無効",
		"en": "MID-BOSS: HUBRIS SUSPENDED",
	},
	"SOAK IN THE CARRIER ONSEN": {
		"ja": "母艦地下の温泉で慢心を解け",
		"en": "SOAK IN THE CARRIER ONSEN",
	},
	"KILLS BUILD HUBRIS": {
		"ja": "撃破で蓄積",
		"en": "KILLS BUILD HUBRIS",
	},
	"LIFE CAP": {
		"ja": "ライフ上限",
		"en": "LIFE CAP",
	},
	"MAXED": {
		"ja": "最大強化済み",
		"en": "MAXED",
	},
	"CARRY": {
		"ja": "繰越",
		"en": "CARRY",
	},
	"NEXT LV": {
		"ja": "次Lv",
		"en": "NEXT LV",
	},
	"DEBUG SPAWN": {
		"ja": "デバッグ出現",
		"en": "DEBUG SPAWN",
	},
	"CROSSING INTO": {
		"ja": "突入",
		"en": "CROSSING INTO",
	},
	"STAR GATE - FLY THROUGH": {
		"ja": "スターゲート - 通過せよ",
		"en": "STAR GATE - FLY THROUGH",
	},
	"DEEP SPACE": {
		"ja": "深宇宙",
		"en": "DEEP SPACE",
	},
	"SECTOR": {
		"ja": "セクター",
		"en": "SECTOR",
	},
	"MOTION DEBUG": {
		"ja": "モーションデバッグ",
		"en": "MOTION DEBUG",
	},
	"TO EXIT": {
		"ja": "終了",
		"en": "TO EXIT",
	},
	"GOD": {
		"ja": "神",
		"en": "GOD",
	},
	"THE GENESIS": {
		"ja": "ザ・ジェネシス",
		"en": "THE GENESIS",
	},
	"CARRIER BOARDED": {
		"ja": "母艦に侵入者",
		"en": "CARRIER BOARDED",
	},
	"LAND ON THE DECK & REPEL THEM - REPAIRS / NEW UNITS LOCKED": {
		"ja": "甲板に着艦して撃退せよ - 修理 / 新規機体ロック中",
		"en": "LAND ON THE DECK & REPEL THEM - REPAIRS / NEW UNITS LOCKED",
	},
	"CARRIER HULL": {
		"ja": "母艦耐久",
		"en": "CARRIER HULL",
	},
	"MERCENARIES": {
		"ja": "傭兵",
		"en": "MERCENARIES",
	},
	"AUTO-REPAIR": {
		"ja": "自動修復",
		"en": "AUTO-REPAIR",
	},
	"REPAIRING": {
		"ja": "修復中",
		"en": "REPAIRING",
	},
	"FULL": {
		"ja": "満タン",
		"en": "FULL",
	},
	"NO STOCKPILE": {
		"ja": "燃料切れ",
		"en": "NO STOCKPILE",
	},
	"DESCEND TO APPROACH": {
		"ja": "降下して接近",
		"en": "DESCEND TO APPROACH",
	},
	"CARRIER SIGNAL": {
		"ja": "母艦信号",
		"en": "CARRIER SIGNAL",
	},
	"ATMOSPHERE ENTRY IN": {
		"ja": "大気圏突入まで",
		"en": "ATMOSPHERE ENTRY IN",
	},
	"LAUNCH IN": {
		"ja": "発進まで",
		"en": "LAUNCH IN",
	},
	"CLIMB TO ALT1000 TO RETURN TO SPACE": {
		"ja": "ALT1000まで上昇して宇宙へ帰還",
		"en": "CLIMB TO ALT1000 TO RETURN TO SPACE",
	},
	"ROUTE": {
		"ja": "ルート",
		"en": "ROUTE",
	},
	"BOSS PANEL FOUND - CLIMB TO SPACE": {
		"ja": "ボスパネル発見 - 宇宙へ上昇",
		"en": "BOSS PANEL FOUND - CLIMB TO SPACE",
	},
	"MINE THE BOSS STAR FOR THE BOSS PANEL": {
		"ja": "ボス星を採掘してボスパネルを探せ",
		"en": "MINE THE BOSS STAR FOR THE BOSS PANEL",
	},
	"TRUE GATE OPEN - CROSS TO ADVANCE": {
		"ja": "正規ゲート開放 - 通過して進行",
		"en": "TRUE GATE OPEN - CROSS TO ADVANCE",
	},
	"HIGH": {
		"ja": "高",
		"en": "HIGH",
	},
	"MID": {
		"ja": "中",
		"en": "MID",
	},
	"LOW": {
		"ja": "低",
		"en": "LOW",
	},
	"FLY TO EACH ALTITUDE TO STRIKE THAT LAYER": {
		"ja": "各高度に合わせてその階層を攻撃",
		"en": "FLY TO EACH ALTITUDE TO STRIKE THAT LAYER",
	},
	"CATCH THE CARRIER SIGNAL - LAND TO TAKE THE HELM": {
		"ja": "母艦信号を捕捉 - 着艦して操舵",
		"en": "CATCH THE CARRIER SIGNAL - LAND TO TAKE THE HELM",
	},
	"BACK TO TITLE": {
		"ja": "タイトルへ戻る",
		"en": "BACK TO TITLE",
	},
	"BOSS PLATE FOUND": {
		"ja": "ボスプレート発見",
		"en": "BOSS PLATE FOUND",
	},
	"ROUTE PLATE FOUND": {
		"ja": "ルートプレート発見",
		"en": "ROUTE PLATE FOUND",
	},
	"DEEP GUARDIAN SIGNAL DETECTED": {
		"ja": "深層ガーディアン信号を検出",
		"en": "DEEP GUARDIAN SIGNAL DETECTED",
	},
	"THE OMEGA CORE STAR HAS APPEARED - FIND IT IN SPACE": {
		"ja": "オメガコア星が出現 - 宇宙で探せ",
		"en": "THE OMEGA CORE STAR HAS APPEARED - FIND IT IN SPACE",
	},
	"ASCENDING TO SURFACE": {
		"ja": "地表へ上昇中",
		"en": "ASCENDING TO SURFACE",
	},
	"A SEALED WALL FRAMES IN AHEAD": {
		"ja": "前方に封印壁が現れた",
		"en": "A SEALED WALL FRAMES IN AHEAD",
	},
	"OOPART SECURED": {
		"ja": "オーパーツ確保",
		"en": "OOPART SECURED",
	},
	"BOSS RELIC SECURED": {
		"ja": "ボスレリック確保",
		"en": "BOSS RELIC SECURED",
	},
	"STAR RELIC": {
		"ja": "スターレリック",
		"en": "STAR RELIC",
	},
	"RELIC SECURED": {
		"ja": "レリック確保",
		"en": "RELIC SECURED",
	},
	"The player grew hubristic.": {
		"ja": "プレイヤーは慢心した。",
		"en": "The player grew hubristic.",
	},
	"Time to think.": {
		"ja": "少し考える時間が必要だ。",
		"en": "Time to think.",
	},
	"MOUSE OPTION": {"ja": "マウス設定", "en": "MOUSE OPTION"},
	"ON: cursor confined": {"ja": "ON: ポインタを画面内に固定", "en": "ON: cursor confined"},
	"OFF: cursor free": {"ja": "OFF: ポインタ自由", "en": "OFF: cursor free"},
	"BOSS PANEL FOUND": {"ja": "ボスパネル発見", "en": "BOSS PANEL FOUND"},
	"ROUTE PANEL FOUND": {"ja": "ルートパネル発見", "en": "ROUTE PANEL FOUND"},
	"CLIMB TO SPACE - CHOOSE A GATE": {"ja": "宇宙へ上昇 - ゲートを選べ", "en": "CLIMB TO SPACE - CHOOSE A GATE"},
	"DEBUG: BLACK HOLE": {"ja": "デバッグ: ブラックホール", "en": "DEBUG: BLACK HOLE"},
	"MID-BOSS: DRAGON": {"ja": "中ボス: ドラゴン", "en": "MID-BOSS: DRAGON"},
	"MID-BOSS: COMBINER": {"ja": "中ボス: 合体体", "en": "MID-BOSS: COMBINER"},
	"MID-BOSS: FLEET": {"ja": "中ボス: 艦隊", "en": "MID-BOSS: FLEET"},
	"DEBUG: LEAVING PLANET": {"ja": "デバッグ: 星から離脱", "en": "DEBUG: LEAVING PLANET"},
	"PRESS B AGAIN IN SPACE FOR THE BOSS": {"ja": "宇宙で再度B: ボス出現", "en": "PRESS B AGAIN IN SPACE FOR THE BOSS"},
	"DEBUG: GOD": {"ja": "デバッグ: 神", "en": "DEBUG: GOD"},
	"FLY THE COLUMN - STRIKE EACH ALTITUDE": {"ja": "柱を飛び、各高度を撃て", "en": "FLY THE COLUMN - STRIKE EACH ALTITUDE"},
	"地中に道が開いた": {"ja": "地中に道が開いた", "en": "A path opened underground"},
	"GATE TO THE DEEP - FLY INTO IT": {"ja": "深層へのゲート - 飛び込め", "en": "GATE TO THE DEEP - FLY INTO IT"},
	"A LEVIATHAN STIRS IN THE DARK": {"ja": "闇の中で巨獣が目覚める", "en": "A LEVIATHAN STIRS IN THE DARK"},
	"DESTROY EVERY JOINT, THEN THE CORE": {"ja": "全関節を破壊し、コアを撃て", "en": "DESTROY EVERY JOINT, THEN THE CORE"},
	"THE DARK GIVES WAY": {"ja": "闇が道を譲る", "en": "THE DARK GIVES WAY"},
	"A GATE OPENS - FLY THROUGH": {"ja": "ゲート開放 - 通過せよ", "en": "A GATE OPENS - FLY THROUGH"},
	"THE GENESIS AWAKENS": {"ja": "ザ・ジェネシス覚醒", "en": "THE GENESIS AWAKENS"},
	"OPEN FIRE - FIND ITS WEAKNESS": {"ja": "攻撃せよ - 弱点を探せ", "en": "OPEN FIRE - FIND ITS WEAKNESS"},
	"CARRIER WEAPON REQUIRED": {"ja": "母艦兵器が必要", "en": "CARRIER WEAPON REQUIRED"},
	"BEACON INBOUND - TAKE THE HELM": {"ja": "ビーコン接近 - 操舵を取れ", "en": "BEACON INBOUND - TAKE THE HELM"},
	"RETURNING TO SURFACE": {"ja": "地表へ帰還中", "en": "RETURNING TO SURFACE"},
	"GATE AHEAD - CHOOSE": {"ja": "前方ゲート - 選択せよ", "en": "GATE AHEAD - CHOOSE"},
	"BOARDERS REPELLED": {"ja": "侵入者撃退", "en": "BOARDERS REPELLED"},
	"MERCENARIES HELD THE CARRIER": {"ja": "傭兵が母艦を守り抜いた", "en": "MERCENARIES HELD THE CARRIER"},
	"CARRIER SECURED": {"ja": "母艦確保", "en": "CARRIER SECURED"},
	"CARRIER LOST TO BOARDERS": {"ja": "母艦が制圧された", "en": "CARRIER LOST TO BOARDERS"},
	"NO CARRIER SUPPORT UNTIL THE NEXT STAR SYSTEM": {"ja": "次の星系まで母艦支援なし", "en": "NO CARRIER SUPPORT UNTIL THE NEXT STAR SYSTEM"},
	"CARRIER HULL DESTROYED": {"ja": "母艦船体崩壊", "en": "CARRIER HULL DESTROYED"},
	"WARNING: CARRIER BOARDED": {"ja": "警告: 母艦に侵入者", "en": "WARNING: CARRIER BOARDED"},
	"LAND & REPEL THEM - REPAIRS / NEW UNITS LOCKED": {"ja": "着艦して撃退せよ - 修理 / 新規機体ロック中", "en": "LAND & REPEL THEM - REPAIRS / NEW UNITS LOCKED"},
	"BOSS": {"ja": "ボス", "en": "BOSS"},
	"EXPLORE": {"ja": "探索", "en": "EXPLORE"},
	"CLICK TO DISEMBARK - walk the deck": {"ja": "クリックで降機 - 甲板を歩く", "en": "CLICK TO DISEMBARK - walk the deck"},
	"DEDICATE EVERYTHING FROM THE CARRIER": {"ja": "ビーコンを取り、母艦からすべてを捧げよ", "en": "TAKE THE BEACON - DEDICATE EVERYTHING FROM THE CARRIER"},
	"THE GENESIS DEPARTED": {"ja": "THE GENESISは去っていった。", "en": "THE GENESIS DEPARTED."},
	"REPAIR FUND": {"ja": "修復ファンド", "en": "REPAIR FUND"},
	"THE GENESIS DESTROYED": {"ja": "ザ・ジェネシス破壊", "en": "THE GENESIS DESTROYED"},
	"WELCOME HOME.": {"ja": "おかえりなさい。", "en": "WELCOME HOME."},
	"DESTROYED": {"ja": "破壊", "en": "DESTROYED"},
	"THANK YOU FOR PLAYING.": {"ja": "プレイしてくれてありがとう。", "en": "THANK YOU FOR PLAYING."},
	"AND THEN, GENESIS BEGAN.": {"ja": "そして、創世記は始まった。", "en": "AND THEN, GENESIS BEGAN."},
	"STAR RELIC APPEARED": {"ja": "スターレリック出現", "en": "STAR RELIC APPEARED"},
	"FOLLOW THE LIGHT": {"ja": "光をたどれ", "en": "FOLLOW THE LIGHT"},
	"NO UNDERGROUND ON THIS WORLD": {"ja": "この星に地下はない", "en": "NO UNDERGROUND ON THIS WORLD"},
	"SURFACE-RICH PLANET": {"ja": "地表特化惑星", "en": "SURFACE-RICH PLANET"},
	"HOLE OPENED (debug)": {"ja": "穴を開放（デバッグ）", "en": "HOLE OPENED (debug)"},
	"DIVE THROUGH TO THE UNDERGROUND": {"ja": "穴から地下へ潜れ", "en": "DIVE THROUGH TO THE UNDERGROUND"},
	"OPEN SPACE": {"ja": "宇宙空間", "en": "OPEN SPACE"},
	"SEAMLESS ORBIT": {"ja": "シームレス軌道", "en": "SEAMLESS ORBIT"},
	"BACK TO OPEN SPACE": {"ja": "宇宙空間へ帰還", "en": "BACK TO OPEN SPACE"},
	"AIM THE SIGHT AT A STAR NAME AND CLICK TO TARGET": {"ja": "星名に照準を合わせクリックでターゲット", "en": "AIM THE SIGHT AT A STAR NAME AND CLICK TO TARGET"},
	"BOSS AREA SIGNAL - PROCEED DEEPER": {"ja": "ボスエリア信号 - さらに深く進め", "en": "BOSS AREA SIGNAL - PROCEED DEEPER"},
	"COMBINER CONTACT": {"ja": "合体敵接近", "en": "COMBINER CONTACT"},
	"SEPARATION PATTERN DETECTED": {"ja": "分離パターン検出", "en": "SEPARATION PATTERN DETECTED"},
	"ENEMY CARRIER APPROACHING": {"ja": "敵母艦接近", "en": "ENEMY CARRIER APPROACHING"},
	"DEEP SPACE INTERCEPT": {"ja": "深宇宙迎撃", "en": "DEEP SPACE INTERCEPT"},
	"WARNING - UNDERGROUND POLYGON BOSS": {"ja": "警告 - 地下ポリゴンボス", "en": "WARNING - UNDERGROUND POLYGON BOSS"},
	"OOPARTS RESONATING": {"ja": "オーパーツ共鳴", "en": "OOPARTS RESONATING"},
	"WARNING - GUARDIAN APPROACHING": {"ja": "警告 - ガーディアン接近", "en": "WARNING - GUARDIAN APPROACHING"},
	"WARNING - THE OMEGA CORE AWAKENS": {"ja": "警告 - オメガコア覚醒", "en": "WARNING - THE OMEGA CORE AWAKENS"},
	"RELIC RELEASED - PICK IT UP": {"ja": "レリック放出 - 回収せよ", "en": "RELIC RELEASED - PICK IT UP"},
	"OMEGA CORE DESTROYED": {"ja": "オメガコア破壊", "en": "OMEGA CORE DESTROYED"},
	"MISSION COMPLETE! THE GALAXY IS YOURS TO ROAM": {"ja": "任務完了！銀河を自由に巡れ", "en": "MISSION COMPLETE! THE GALAXY IS YOURS TO ROAM"},
	"FINAL RELIC DROPPING TO THE LOWEST LAYER": {"ja": "最下層へファイナルレリック投下", "en": "FINAL RELIC DROPPING TO THE LOWEST LAYER"},
	"GOD DESCENDS": {"ja": "神、降臨", "en": "GOD DESCENDS"},
	"GOD BARS THE WAY": {"ja": "神が道を塞ぐ", "en": "GOD BARS THE WAY"},
	"FLY THE COLUMN - STRIKE EACH ALTITUDE (HIGH/MID/LOW)": {"ja": "柱を飛び、各高度を撃て（高/中/低）", "en": "FLY THE COLUMN - STRIKE EACH ALTITUDE (HIGH/MID/LOW)"},
	"THE CROWN IS SEALED": {"ja": "冠は封印されている", "en": "THE CROWN IS SEALED"},
	"BREAK THE BODY AND WINGS FIRST": {"ja": "先に胴体と翼を破壊せよ", "en": "BREAK THE BODY AND WINGS FIRST"},
	"GOD HAS FALLEN": {"ja": "神は墜ちた", "en": "GOD HAS FALLEN"},
	"...AND THE GENESIS DAWNS": {"ja": "…そしてジェネシスが明ける", "en": "...AND THE GENESIS DAWNS"},
	"THE GENESIS IS IMMUNE": {"ja": "ザ・ジェネシスは無効化する", "en": "THE GENESIS IS IMMUNE"},
	"NORMAL WEAPONS HAVE NO EFFECT": {"ja": "通常兵器は通用しない", "en": "NORMAL WEAPONS HAVE NO EFFECT"},
	"ARMOR UNBROKEN": {"ja": "装甲は破れない", "en": "ARMOR UNBROKEN"},
	"KEEP FIRING - FIND ANOTHER WAY": {"ja": "撃ち続けろ - 別の道を探せ", "en": "KEEP FIRING - FIND ANOTHER WAY"},
	"CARRIER SIGNAL DETECTED": {"ja": "母艦信号検出", "en": "CARRIER SIGNAL DETECTED"},
	"FLY INTO THE BEACON TO CALL A CARRIER": {"ja": "ビーコンへ飛び込み母艦を呼べ", "en": "FLY INTO THE BEACON TO CALL A CARRIER"},
	"CARRIER INBOUND": {"ja": "母艦接近中", "en": "CARRIER INBOUND"},
	"BOARD ITS DECK TO REPAIR / RECOVER UNITS": {"ja": "甲板に乗り修理 / 機体復旧", "en": "BOARD ITS DECK TO REPAIR / RECOVER UNITS"},
	"SPHERE STAR / SAME ORB SURFACE": {"ja": "球体星 / 同一球面ステージ", "en": "SPHERE STAR / SAME ORB SURFACE"},
	"DESTROY EVERY GOLD BLOCK": {"ja": "金ブロックをすべて破壊", "en": "DESTROY EVERY GOLD BLOCK"},
	"FIND SIGNAL - RESCUE THE VIP": {"ja": "信号を探し要人を救出", "en": "FIND SIGNAL - RESCUE THE VIP"},
	"PASS 3 KEY GATES - ENTER BOSS GATE": {"ja": "キーゲート3つ通過 - ボスゲートへ", "en": "PASS 3 KEY GATES - ENTER BOSS GATE"},
	"SURFACE BOSS APPROACHING": {"ja": "地表ボス接近", "en": "SURFACE BOSS APPROACHING"},
	"BREAK THROUGH THE STAR DEFENSE": {"ja": "星の防衛線を突破せよ", "en": "BREAK THROUGH THE STAR DEFENSE"},
	"RESCUE SIGNAL DETECTED": {"ja": "救援信号検出", "en": "RESCUE SIGNAL DETECTED"},
	"INTERCEPT THE CYAN BEACON": {"ja": "シアンのビーコンを捕捉", "en": "INTERCEPT THE CYAN BEACON"},
	"VIP TRANSPONDER LOCKED": {"ja": "要人トランスポンダー捕捉", "en": "VIP TRANSPONDER LOCKED"},
	"RESCUE THE GOLD UNIT": {"ja": "金色ユニットを救出", "en": "RESCUE THE GOLD UNIT"},
	"VIP RESCUED": {"ja": "要人救出", "en": "VIP RESCUED"},
	"BOSS GATE OPEN": {"ja": "ボスゲート開放", "en": "BOSS GATE OPEN"},
	"KEY GATE APPROACHING": {"ja": "キーゲート接近", "en": "KEY GATE APPROACHING"},
	"ENTER THE GATE": {"ja": "ゲートへ入れ", "en": "ENTER THE GATE"},
	"BOSS GATE UNLOCKING": {"ja": "ボスゲート解放中", "en": "BOSS GATE UNLOCKING"},
	"KEEP DIVING": {"ja": "さらに潜行せよ", "en": "KEEP DIVING"},
	"CLIMB AWAY - STAR COLLAPSING": {"ja": "上昇離脱 - 星が崩壊中", "en": "CLIMB AWAY - STAR COLLAPSING"},
	"LOW ORBIT": {"ja": "低軌道", "en": "LOW ORBIT"},
	"CLIMB AWAY": {"ja": "上昇離脱", "en": "CLIMB AWAY"},
	"SURFACE BOSS DESTROYED": {"ja": "地表ボス破壊", "en": "SURFACE BOSS DESTROYED"},
	"CLIMB TO SPACE - STAR WILL VANISH": {"ja": "宇宙へ上昇 - 星は消滅する", "en": "CLIMB TO SPACE - STAR WILL VANISH"},
	"NO ROUTE PLATE HERE": {"ja": "ここにルートプレートはない", "en": "NO ROUTE PLATE HERE"},
	"THIS STAR IS RESOURCES ONLY - MOVE ON": {"ja": "この星は資源のみ - 次へ進め", "en": "THIS STAR IS RESOURCES ONLY - MOVE ON"},
	"GOLDEN WALK DEBUG": {"ja": "ゴールデン歩行デバッグ", "en": "GOLDEN WALK DEBUG"},
	"CLICK: ROBOT/FIGHTER  WHEEL DOWN: ZOOM  F5/ESC: EXIT": {"ja": "クリック: ロボ/戦闘機  ホイール下: ズーム  F5/ESC: 終了", "en": "CLICK: ROBOT/FIGHTER  WHEEL DOWN: ZOOM  F5/ESC: EXIT"},
	"GOLDEN WALK DEBUG OFF": {"ja": "ゴールデン歩行デバッグ終了", "en": "GOLDEN WALK DEBUG OFF"},
	"RETURNED TO SPACE": {"ja": "宇宙へ帰還", "en": "RETURNED TO SPACE"},
	"A SEALED WALL BARS THE WAY": {"ja": "封印壁が道を塞ぐ", "en": "A SEALED WALL BARS THE WAY"},
	"BREAK THROUGH IT": {"ja": "突破せよ", "en": "BREAK THROUGH IT"},
	"GATE BOSS - POLYGON GUARDIAN": {"ja": "ゲートボス - ポリゴンガーディアン", "en": "GATE BOSS - POLYGON GUARDIAN"},
	"DEFEAT IT TO RETURN": {"ja": "撃破して帰還せよ", "en": "DEFEAT IT TO RETURN"},
	"FINAL RELIC ON LOWEST LAYER": {"ja": "最下層にファイナルレリック", "en": "FINAL RELIC ON LOWEST LAYER"},
	"DESCEND AND COLLECT THE PURPLE CORE": {"ja": "降下して紫のコアを回収", "en": "DESCEND AND COLLECT THE PURPLE CORE"},
	"GOLDEN!": {"ja": "ゴールデン！", "en": "GOLDEN!"},
	"10 SECONDS OF OVERWHELMING POWER": {"ja": "10秒間、圧倒的パワー", "en": "10 SECONDS OF OVERWHELMING POWER"},
	"MINE THIS STAR TO FIND THE BOSS PANEL": {"ja": "この星を採掘してボスパネルを探せ", "en": "MINE THIS STAR TO FIND THE BOSS PANEL"},
	"FIND THE NEXT ROUTE PANEL": {"ja": "次のルートパネルを探せ", "en": "FIND THE NEXT ROUTE PANEL"},
	"NO ROUTE - THE GATE LEADS NOWHERE": {"ja": "ルートなし - ゲートの先は虚無", "en": "NO ROUTE - THE GATE LEADS NOWHERE"},
	"OFF-ROUTE - THE GATE LEADS NOWHERE": {"ja": "ルート外 - ゲートの先は虚無", "en": "OFF-ROUTE - THE GATE LEADS NOWHERE"},
	"A BLACK HOLE SWALLOWS THE SHIP": {"ja": "ブラックホールが機体を飲み込む", "en": "A BLACK HOLE SWALLOWS THE SHIP"},
	"A NEW STAR SYSTEM UNFOLDS": {"ja": "新たな星系が広がる", "en": "A NEW STAR SYSTEM UNFOLDS"},
	"FINAL BATTLE": {"ja": "最終決戦", "en": "FINAL BATTLE"},
	"THE BOSS AWAITS - CLIMB AND FIGHT": {"ja": "ボスが待つ - 上昇して戦え", "en": "THE BOSS AWAITS - CLIMB AND FIGHT"},
	"THE CORE IS EXPOSED": {"ja": "コア露出", "en": "THE CORE IS EXPOSED"},
	"STRIKE IT DOWN": {"ja": "撃ち落とせ", "en": "STRIKE IT DOWN"},
	"MAX LIFE": {"ja": "最大ライフ", "en": "MAX LIFE"},
	"TERRAIN ATTACK WIDENED": {"ja": "テレイン攻撃範囲拡大", "en": "TERRAIN ATTACK WIDENED"},
	"MINE STAR": {"ja": "マインスター", "en": "MINE STAR"},
	"RESCUE STAR": {"ja": "レスキュースター", "en": "RESCUE STAR"},
	"BOSS STAR": {"ja": "ボススター", "en": "BOSS STAR"},
	"FAITH": {"ja": "信仰", "en": "FAITH"},
}

func set_language(lang: String) -> void:
	language = EN if lang == EN else JA
	TranslationServer.set_locale("en" if language == EN else "ja")

func toggle_language() -> void:
	set_language(EN if language == JA else JA)

func is_ja() -> bool:
	return language == JA

func t(key: String) -> String:
	if TEXT.has(key):
		var d: Dictionary = TEXT[key]
		return String(d.get(language, d.get(EN, key)))
	return key

func pair(ja: String, en: String) -> String:
	return ja if language == JA else en
