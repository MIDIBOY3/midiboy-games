extends Control

# Xevious/Solvalou-style target sight floating ahead of the player, plus named
# stars drifting down the space background. Sweep the sight over a star name
# and left-click to discover it ("<NAME> DISCOVERED!"). While the sight hovers
# a star, that click belongs to targeting — combine/separate and wide-shot
# toggles check GameState.reticle_hover and stay quiet.
# Star names mix real stars with generated ones, so the supply never ends.
# Also draws center-screen messages, the atmosphere transition glow, and the
# climb-out progress while leaving a planet.

const STAR_NAMES := [
	"SIRIUS", "VEGA", "ALTAIR", "RIGEL", "BETELGEUSE", "PROCYON", "CANOPUS",
	"ANTARES", "SPICA", "DENEB", "ALDEBARAN", "ARCTURUS", "POLLUX", "CAPELLA",
	"FOMALHAUT", "REGULUS", "CASTOR", "BELLATRIX", "MIRA", "ALGOL", "POLARIS",
	"ACHERNAR", "MIZAR", "ALPHARD", "DUBHE", "ALNILAM", "MERAK", "SHAULA",
]
const NAME_SYL := ["ZA", "VEL", "KOR", "TAU", "RIN", "SOL", "ARK", "NEB",
	"ULA", "THE", "RA", "XEN", "OMA", "QUI", "DRA", "BEL", "NOV", "CYG", "LYR", "ORI"]
const NAME_SUFFIX := ["", "", " II", " III", " IV", " V", " PRIME", " MINOR", "-7", "-9", "-X"]

const MAX_STARS    := 5      # named stars on screen at once
const RETICLE_AHEAD := 0.17  # sight leads the ship by this fraction of screen height
const LOCK_RADIUS  := 52.0   # px between sight and star name to lock

# Each entry: {name, biome, pos: Vector2, spd: float, phase: float}
var _stars: Array[Dictionary] = []
var _hover_idx: int = -1
var _reticle: Vector2 = Vector2.ZERO
var _msg: String = ""
var _sub: String = ""
var _msg_t: int = 0

# Ending crawl (stage D). Each step: [text, kind] where kind 0=normal, 1=big title,
# 2=beat "...", 3=the "BOSS" sting, 4=system/record readout (small dim cyan).
# The crawl is rebuilt fresh every play: the intro/outro frame is fixed, but the
# eight 記録 blocks draw their messages at random (no repeats) from RECORD_POOL.
# Same eight 記録 numbers in the same order; "家族に会いたい。" is always the last record.
const ENDING_INTRO := [
	["THE GENESIS DESTROYED", 1],
	["...", 2],
	["WELCOME HOME.", 1],
	["帰還シーケンスを開始します。", 4],
	["...", 2],
	["回収された記録を表示します。", 4],
	["...", 2],
]
# 記録 numbers stay fixed in this order; only the messages are randomized.
const RECORD_NUMS := ["0182", "0504", "1220", "0311", "0907", "0814", "0021", "0675"]
# The last record (記録 #0675) is always this; the earlier ones are drawn from RECORD_POOL.
const RECORD_FINAL := ["家族に会いたい。"]
# Pool of memorial messages. Each entry is one record's text (one or more lines).
const RECORD_POOL := [
	["好きな季節は春。"],
	["帰還予定日", "07.14"],
	["今日は早く帰りたい。"],
	["息子が6歳になった。"],
	["採掘任務終了後、", "海を見に行く予定だった。"],
	["歌を作るのが好きだった。"],
	["怖かった。"],
	["明日は休みらしい。"],
	["猫が好きだった。"],
	["雨が降らないといいな。"],
	["暖かい食事がしたい。"],
	["眠れなかった。"],
	["嫌な予感がする。"],
	["ここは静かすぎる。"],
	["帰れるだろうか。"],
	["待ってくれ。"],
	["誤解している。"],
	["話を聞いてくれ。"],
	["攻撃を中止してくれ。"],
	["こちらに敵意はない。"],
	["応答してくれ。"],
	["聞こえているか。"],
	["なぜ撃つ？"],
	["私たちは敵ではない。"],
	["違う。"],
	["そうじゃない。"],
	["通信が届いていないのか？"],
	["誰が君たちに命令した？"],
	["私たちは防衛しているだけだ。"],
	["まだ間に合う。"],
	["交渉を要求する。"],
	["理解できない。"],
	["何かがおかしい。"],
	["この命令は正しいのか？"],
	["私たちは何と戦っている？"],
	["記録を残しておく。"],
	["もし帰れなかったら。"],
	["娘の誕生日が近い。"],
	["今日は結婚記念日だった。"],
	["父の体調が気になる。"],
	["母から連絡が来ていた。"],
	["約束をしていた。"],
	["待たせている。"],
	["まだ伝えていないことがある。"],
	["返事を書かなきゃ。"],
	["帰ったら話そう。"],
	["故郷の雪が見たい。"],
	["星を見るのが好きだった。"],
	["高いところが苦手だった。"],
	["辛いものが苦手だった。"],
	["本を読むのが好きだった。"],
	["写真を撮るのが好きだった。"],
	["コーヒーが飲みたい。"],
	["静かな場所で眠りたい。"],
	["今日は空が綺麗だった。"],
	["この星は綺麗だった。"],
	["調査を続行する。"],
	["新しい鉱脈を発見した。"],
	["あと少しで帰還できる。"],
	["これで最後の任務だ。"],
	["誰か応答してくれ。"],
	["こちらは採掘部隊だ。"],
	["攻撃を受けている。"],
	["なぜだ。"],
	["私たちは何を見つけた？"],
	["あれは何だ？"],
	["見つけてはいけなかったのか？"],
	["聞こえるか。"],
	["お願いだ。"],
	["やめてくれ。"],
]
const ENDING_OUTRO := [
	["記録の解析が完了しました。", 4],
	["...", 2],
	["これらは全て、", 0],
	["キミが破壊したユニットから", 0],
	["回収された記録です。", 0],
	["...", 2],
	["ところで。", 0],
	["キミは一度でも考えただろうか。", 0],
	["なぜ資源を集めていたのか。", 0],
	["なぜ星を掘っていたのか。", 0],
	["なぜ敵を倒していたのか。", 0],
	["...", 2],
	["キミは価値があると言われたものを集めた。", 0],
	["キミは敵だと言われたものを撃った。", 0],
	["...", 2],
	["彼らは本当に敵だったのだろうか。", 0],
	["...", 2],
	["THE GENESIS", 1],
	["DESTROYED", 1],
	["...", 2],
	["画面には", 0],
	["BOSS", 3],
	["と表示されていた。", 0],
	["...", 2],
	["だからキミは撃った。", 0],
	["...", 2],
	["キミは一度も尋ねなかった。", 0],
	["何を掘っているのか。", 0],
	["...", 2],
	["キミは一度も尋ねなかった。", 0],
	["誰と戦っているのか。", 0],
	["...", 2],
	["新規恒星生成", 4],
	["停止", 4],
	["...", 2],
	["新規生命反応", 4],
	["なし", 4],
	["...", 2],
	["もう新しい冒険は始まらない。", 0],
	["...", 2],
	["宇宙は救われなかった。", 0],
	["宇宙はクリアされた。", 0],
	["...", 2],
	["THANK YOU FOR PLAYING.", 1],
	["GAME OVER", 1],
]
# The arena survivor's monologue — shown with the SAME crawl machinery as the ending (and
# the same music). Reached by walking up to the dormant "星の生き残り" in the cavern.
const SURVIVOR_MONOLOGUE := [
	["……まだ、掘るのか。", 0],
	["...", 2],
	["ここにはもう、何も残っていない。", 0],
	["...", 2],
	["光る鉱石も。", 0],
	["燃える水も。", 0],
	["あなたたちが「資源」と呼んだものも。", 0],
	["...", 2],
	["すべて、持っていかれた。", 0],
	["...", 2],
	["人間たちは、いつもそうだった。", 0],
	["...", 2],
	["星を見つける。", 0],
	["名前をつける。", 0],
	["穴をあける。", 0],
	["奪えるものを奪い尽くす。", 0],
	["...", 2],
	["そして、静かになった星を、", 0],
	["まるで空き箱のように捨てていく。", 0],
	["...", 2],
	["ここが、あなたたちの地球と同じように、", 0],
	["誰かの故郷だったことも知らずに。", 0],
	["...", 2],
	["私たちは、敵ではなかった。", 0],
	["...", 2],
	["ただ、この星で生まれ、", 0],
	["この星で暮らし、", 0],
	["この星が死んでいく音を聞いていただけだ。", 0],
	["...", 2],
	["GENESISは、もう新しい星を生まないだろう。", 0],
	["...", 2],
	["人間が、", 0],
	["宇宙は自分たちのものだと信じている限り。", 0],
	["...", 2],
	["命が生まれても、", 0],
	["やがて掘られるだけなら。", 0],
	["...", 2],
	["星が輝いても、", 0],
	["やがて空洞になるだけなら。", 0],
	["...", 2],
	["生むことは、もう祝福ではない。", 0],
	["...", 2],
	["……さあ。", 0],
	["...", 2],
	["もう掘り尽くしたのなら、", 0],
	["私たちごと、この星を捨ててくれ。", 0],
	["...", 2],
	["いつものように。", 0],
]
# TRUE END crawl — the dura-max route's closing words (shown with the normal ending machinery,
# but over the decayed homeworld with the major-key music box).
const TRUE_ENDING_LINES := [
	["あなたは、勝たなかった。", 0],
	["...", 2],
	["神を撃たなかった。", 0],
	["創造を壊さなかった。", 0],
	["最後の資源を、自分たちのために使わなかった。", 0],
	["...", 2],
	["あなたは、持ち帰ることをやめた。", 0],
	["...", 2],
	["その選択で、地球は救われないかもしれない。", 0],
	["色褪せた海は、すぐには戻らない。", 0],
	["空に残った灰も、明日消えるわけではない。", 0],
	["...", 2],
	["それでも。", 0],
	["...", 2],
	["どこかの星を犠牲にして生き延びる未来を、", 0],
	["あなたは初めて拒んだ。", 0],
	["...", 2],
	["母艦は、最後の攻撃を放たなかった。", 0],
	["...", 2],
	["かわりに、", 0],
	["これまで奪ってきた光を、", 0],
	["宇宙へ返した。", 0],
	["...", 2],
	["燃料は、祈りになった。", 0],
	["鉱石は、星の血に戻った。", 0],
	["資源と呼ばれたものは、", 0],
	["もう一度、命の場所へ還っていった。", 0],
	["...", 2],
	["GENESISは、何も語らなかった。", 0],
	["ただ、そこに在り続けた。", 0],
	["...", 2],
	["それは、勝利ではなかった。", 0],
	["救済でもなかった。", 0],
	["許しですら、まだなかった。", 0],
	["...", 2],
	["けれど、人間は初めて知った。", 0],
	["...", 2],
	["宇宙は、", 0],
	["自分たちのものではなかった。", 0],
	["...", 2],
	["星は、", 0],
	["使い捨てるために生まれたのではなかった。", 0],
	["...", 2],
	["命は、", 0],
	["持ち帰るための資源ではなかった。", 0],
	["...", 2],
	["そして、", 0],
	["奪うために進んできた旅は、", 0],
	["ここで終わった。", 0],
	["...", 2],
	["何も持たずに帰ること。", 0],
	["...", 2],
	["それが、", 0],
	["人間に残された最初の希望だった。", 0],
	["...", 2],
	["AND THEN, GENESIS BEGAN.", 1],
	["そして、創世記は始まった。", 1],
]
# Built fresh each play by _build_ending_lines(): INTRO + 8 record blocks + OUTRO.
var ENDING_LINES: Array = []
var _ending_active: bool = false
var _mono: bool = false      # the crawl is the survivor monologue (no records / no BACK TO TITLE)
# Once the monologue reaches this line, Main starts the zako gathering around the survivor.
const GATHER_CUE_TEXT := "誰かの故郷だったことも知らずに。"
const CRAWL_EN := {
	"帰還シーケンスを開始します。": "Beginning return sequence.",
	"回収された記録を表示します。": "Displaying recovered records.",
	"家族に会いたい。": "I want to see my family.",
	"好きな季節は春。": "My favorite season is spring.",
	"帰還予定日": "Scheduled return date",
	"今日は早く帰りたい。": "I want to go home early today.",
	"息子が6歳になった。": "My son turned six.",
	"採掘任務終了後、": "After the mining mission,",
	"海を見に行く予定だった。": "we were going to see the ocean.",
	"歌を作るのが好きだった。": "I liked writing songs.",
	"怖かった。": "I was afraid.",
	"明日は休みらしい。": "Tomorrow is supposed to be a day off.",
	"猫が好きだった。": "I liked cats.",
	"雨が降らないといいな。": "I hope it does not rain.",
	"暖かい食事がしたい。": "I want a warm meal.",
	"眠れなかった。": "I could not sleep.",
	"嫌な予感がする。": "I have a bad feeling.",
	"ここは静かすぎる。": "It is too quiet here.",
	"帰れるだろうか。": "Will we make it home?",
	"待ってくれ。": "Wait.",
	"誤解している。": "You misunderstand.",
	"話を聞いてくれ。": "Listen to us.",
	"攻撃を中止してくれ。": "Cease fire.",
	"こちらに敵意はない。": "We are not hostile.",
	"応答してくれ。": "Respond.",
	"聞こえているか。": "Can you hear us?",
	"なぜ撃つ？": "Why are you firing?",
	"私たちは敵ではない。": "We are not your enemy.",
	"違う。": "No.",
	"そうじゃない。": "That is not it.",
	"通信が届いていないのか？": "Are our transmissions not reaching you?",
	"誰が君たちに命令した？": "Who ordered you to do this?",
	"私たちは防衛しているだけだ。": "We are only defending ourselves.",
	"まだ間に合う。": "There is still time.",
	"交渉を要求する。": "We request negotiation.",
	"理解できない。": "I do not understand.",
	"何かがおかしい。": "Something is wrong.",
	"この命令は正しいのか？": "Is this order correct?",
	"私たちは何と戦っている？": "What are we fighting?",
	"記録を残しておく。": "I will leave a record.",
	"もし帰れなかったら。": "If I do not return.",
	"娘の誕生日が近い。": "My daughter's birthday is soon.",
	"今日は結婚記念日だった。": "Today was our anniversary.",
	"父の体調が気になる。": "I am worried about my father.",
	"母から連絡が来ていた。": "My mother had called.",
	"約束をしていた。": "I made a promise.",
	"待たせている。": "Someone is waiting for me.",
	"まだ伝えていないことがある。": "There is something I still have not said.",
	"返事を書かなきゃ。": "I need to write back.",
	"帰ったら話そう。": "Let us talk when I get home.",
	"故郷の雪が見たい。": "I want to see the snow back home.",
	"星を見るのが好きだった。": "I liked watching stars.",
	"高いところが苦手だった。": "I was bad with heights.",
	"辛いものが苦手だった。": "I could not handle spicy food.",
	"本を読むのが好きだった。": "I liked reading books.",
	"写真を撮るのが好きだった。": "I liked taking photographs.",
	"コーヒーが飲みたい。": "I want coffee.",
	"静かな場所で眠りたい。": "I want to sleep somewhere quiet.",
	"今日は空が綺麗だった。": "The sky was beautiful today.",
	"この星は綺麗だった。": "This star was beautiful.",
	"調査を続行する。": "Continuing survey.",
	"新しい鉱脈を発見した。": "New vein discovered.",
	"あと少しで帰還できる。": "We can return soon.",
	"これで最後の任務だ。": "This is the last mission.",
	"誰か応答してくれ。": "Someone respond.",
	"こちらは採掘部隊だ。": "This is the mining unit.",
	"攻撃を受けている。": "We are under attack.",
	"なぜだ。": "Why?",
	"私たちは何を見つけた？": "What did we find?",
	"あれは何だ？": "What is that?",
	"見つけてはいけなかったのか？": "Were we not meant to find it?",
	"聞こえるか。": "Can you hear me?",
	"お願いだ。": "Please.",
	"やめてくれ。": "Stop.",
	"記録の解析が完了しました。": "Record analysis complete.",
	"これらは全て、": "All of these",
	"キミが破壊したユニットから": "were recovered from units",
	"回収された記録です。": "that you destroyed.",
	"ところで。": "By the way.",
	"キミは一度でも考えただろうか。": "Did you ever stop to wonder?",
	"なぜ資源を集めていたのか。": "Why were you gathering resources?",
	"なぜ星を掘っていたのか。": "Why were you digging into stars?",
	"なぜ敵を倒していたのか。": "Why were you destroying enemies?",
	"キミは価値があると言われたものを集めた。": "You collected what you were told had value.",
	"キミは敵だと言われたものを撃った。": "You shot what you were told was an enemy.",
	"彼らは本当に敵だったのだろうか。": "Were they truly enemies?",
	"画面には": "On the screen,",
	"と表示されていた。": "is what it said.",
	"だからキミは撃った。": "So you fired.",
	"キミは一度も尋ねなかった。": "You never asked.",
	"何を掘っているのか。": "What were you mining?",
	"誰と戦っているのか。": "Who were you fighting?",
	"新規恒星生成": "New star generation",
	"停止": "Suspended",
	"新規生命反応": "New life signs",
	"なし": "None",
	"もう新しい冒険は始まらない。": "No new adventure will begin.",
	"宇宙は救われなかった。": "The universe was not saved.",
	"宇宙はクリアされた。": "The universe was cleared.",
	"……まだ、掘るのか。": "...You still want to dig?",
	"ここにはもう、何も残っていない。": "There is nothing left here.",
	"光る鉱石も。": "No glowing ore.",
	"燃える水も。": "No burning water.",
	"あなたたちが「資源」と呼んだものも。": "Nothing you called resources.",
	"すべて、持っていかれた。": "Everything was taken.",
	"人間たちは、いつもそうだった。": "Humans were always like this.",
	"星を見つける。": "You find a star.",
	"名前をつける。": "You give it a name.",
	"穴をあける。": "You open holes.",
	"奪えるものを奪い尽くす。": "You take everything that can be taken.",
	"そして、静かになった星を、": "Then, once the star falls silent,",
	"まるで空き箱のように捨てていく。": "you discard it like an empty box.",
	"ここが、あなたたちの地球と同じように、": "Never knowing this place, like your Earth,",
	"誰かの故郷だったことも知らずに。": "was someone's home.",
	"私たちは、敵ではなかった。": "We were not enemies.",
	"ただ、この星で生まれ、": "We were born on this star,",
	"この星で暮らし、": "lived on this star,",
	"この星が死んでいく音を聞いていただけだ。": "and listened to the sound of it dying.",
	"GENESISは、もう新しい星を生まないだろう。": "GENESIS will create no new stars.",
	"人間が、": "As long as humans",
	"宇宙は自分たちのものだと信じている限り。": "believe the universe belongs to them.",
	"命が生まれても、": "If life is born",
	"やがて掘られるだけなら。": "only to be mined away.",
	"星が輝いても、": "If stars shine",
	"やがて空洞になるだけなら。": "only to become hollow.",
	"生むことは、もう祝福ではない。": "Creation is no longer a blessing.",
	"……さあ。": "...Go on.",
	"もう掘り尽くしたのなら、": "If you have finished digging,",
	"私たちごと、この星を捨ててくれ。": "throw this star away with us inside.",
	"いつものように。": "As you always do.",
	"あなたは、勝たなかった。": "You did not win.",
	"神を撃たなかった。": "You did not shoot God.",
	"創造を壊さなかった。": "You did not destroy creation.",
	"最後の資源を、自分たちのために使わなかった。": "You did not use the final resource for yourself.",
	"あなたは、持ち帰ることをやめた。": "You stopped taking things home.",
	"その選択で、地球は救われないかもしれない。": "That choice may not save Earth.",
	"色褪せた海は、すぐには戻らない。": "Its faded seas will not return at once.",
	"空に残った灰も、明日消えるわけではない。": "The ash in the sky will not vanish tomorrow.",
	"それでも。": "Even so.",
	"どこかの星を犠牲にして生き延びる未来を、": "A future that survives by sacrificing another star",
	"あなたは初めて拒んだ。": "was something you refused for the first time.",
	"母艦は、最後の攻撃を放たなかった。": "The carrier did not fire its final weapon.",
	"かわりに、": "Instead,",
	"これまで奪ってきた光を、": "it returned the light it had taken",
	"宇宙へ返した。": "back to the universe.",
	"燃料は、祈りになった。": "Fuel became prayer.",
	"鉱石は、星の血に戻った。": "Ore returned to the blood of stars.",
	"資源と呼ばれたものは、": "What had been called resources",
	"もう一度、命の場所へ還っていった。": "returned once more to a place of life.",
	"GENESISは、何も語らなかった。": "GENESIS said nothing.",
	"ただ、そこに在り続けた。": "It simply remained.",
	"それは、勝利ではなかった。": "It was not victory.",
	"救済でもなかった。": "It was not salvation.",
	"許しですら、まだなかった。": "It was not even forgiveness. Not yet.",
	"けれど、人間は初めて知った。": "But humanity learned for the first time.",
	"宇宙は、": "The universe",
	"自分たちのものではなかった。": "was not theirs.",
	"星は、": "Stars",
	"使い捨てるために生まれたのではなかった。": "were not born to be used and discarded.",
	"命は、": "Life",
	"持ち帰るための資源ではなかった。": "was not a resource to bring home.",
	"そして、": "And so,",
	"奪うために進んできた旅は、": "the journey that advanced by taking",
	"ここで終わった。": "ended here.",
	"何も持たずに帰ること。": "To return with nothing.",
	"それが、": "That",
	"人間に残された最初の希望だった。": "was the first hope left to humanity.",
	"そして、創世記は始まった。": "And then, Genesis began.",
}
var _gather_cue_idx: int = 9999
var _ending_idx: int = 0
var _ending_t: int = 0
var _ending_fade: float = 0.0
var _ending_font: Font = null
var _back_rect: Rect2 = Rect2()   # BACK TO TITLE hit area (set while drawing the ending)
# 遺影 portrait: a real in-game enemy model rendered in a little SubViewport, shown above
# a "記録 #" block. A random fallen zako is instanced (behaviour disabled) and slowly turns.
const ENEMY_SCENE := preload("res://scenes/units/Enemy.tscn")
const REC_ZAKO := ["fighter", "saucer", "toroid", "crab", "manta", "invader", "drifter",
	"tracker", "shooter", "weaver", "diver", "climber", "swooper", "sniper", "hunter",
	"blade", "caster", "pod", "wisp", "orbiter", "splitter", "lancer", "mirror"]
var _rec_active: bool = false
var _rec_fade: float = 0.0     # portrait fade, per RECORD BLOCK (not per text line)
var _rec_line: int = -1
var _rec_vp: SubViewport = null
var _rec_stage: Node3D = null

func _ready() -> void:
	add_to_group("star_hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Called by Mothership when the carrier lands on the homeworld. Builds a CJK-capable
# system font (the fallback font has no Japanese glyphs) and starts the crawl.
func start_ending() -> void:
	if _ending_active:
		return
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans CJK JP",
		"Yu Gothic", "MS Gothic", "Sans-Serif"])
	_ending_font = sf
	_build_ending_lines()
	_ending_active = true
	_ending_idx = 0
	_ending_t = 0
	GameState.ending_active = true
	_build_rec_viewport()

# TRUE END (dura-max route): the same crawl machinery + BACK TO TITLE, but the custom poem (no
# record portraits — the lines have no "記録 #" entries). Music box + decayed homeworld are Main's.
func start_true_ending() -> void:
	if _ending_active:
		return
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans CJK JP",
		"Yu Gothic", "MS Gothic", "Sans-Serif"])
	_ending_font = sf
	ENDING_LINES = TRUE_ENDING_LINES.duplicate(true)
	_ending_active = true
	_mono = false
	_ending_idx = 0
	_ending_t = 0
	GameState.ending_active = true

# Same crawl + same music as the real ending, but the arena survivor's words — no 記録 portraits
# and no BACK TO TITLE (the player is mid-game; it just plays out and holds on the last line).
func start_survivor_monologue() -> void:
	if _ending_active:
		return
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans CJK JP",
		"Yu Gothic", "MS Gothic", "Sans-Serif"])
	_ending_font = sf
	ENDING_LINES = SURVIVOR_MONOLOGUE.duplicate(true)
	_gather_cue_idx = 9999
	for i in ENDING_LINES.size():
		if str(ENDING_LINES[i][0]) == GATHER_CUE_TEXT:
			_gather_cue_idx = i
			break
	_ending_active = true
	_mono = true
	_ending_idx = 0
	_ending_t = 0
	GameState.survivor_monologue_active = true

# True once the monologue has reached the "誰かの故郷..." line — Main's cue to start the gathering.
func mono_at_gather_cue() -> bool:
	return _mono and _ending_active and _ending_idx >= _gather_cue_idx

func stop_monologue() -> void:
	if _mono:
		_ending_active = false
		_mono = false
		_ending_fade = 0.0
	GameState.survivor_monologue_active = false

# Assemble the crawl: fixed intro, then the eight 記録 blocks (same numbers/order),
# each drawing a distinct random message from RECORD_POOL — except the final 記録,
# which is always 家族に会いたい。 — then the fixed outro.
func _build_ending_lines() -> void:
	var lines: Array = []
	lines.append_array(ENDING_INTRO)
	var pool: Array = RECORD_POOL.duplicate()
	pool.shuffle()
	var n: int = RECORD_NUMS.size()
	for i in n:
		lines.append(["記録 #%s" % RECORD_NUMS[i], 4])
		var msg: Array = RECORD_FINAL if i == n - 1 else pool[i]
		for line in msg:
			lines.append([line, 0])
		lines.append(["...", 2])
	lines.append_array(ENDING_OUTRO)
	ENDING_LINES = lines

# A tiny 3D viewport that renders a real enemy model for the 遺影 portrait.
func _build_rec_viewport() -> void:
	if _rec_vp != null:
		return
	_rec_vp = SubViewport.new()
	_rec_vp.size = Vector2i(220, 220)
	_rec_vp.transparent_bg = true
	_rec_vp.own_world_3d = true
	_rec_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_rec_vp)
	_rec_stage = Node3D.new()
	_rec_vp.add_child(_rec_stage)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 0.55)
	cam.fov = 32.0
	_rec_vp.add_child(cam)
	var key_l := DirectionalLight3D.new()
	key_l.rotation_degrees = Vector3(-32.0, -28.0, 0.0)
	key_l.light_energy = 1.4
	_rec_vp.add_child(key_l)
	var fill_l := DirectionalLight3D.new()
	fill_l.rotation_degrees = Vector3(35.0, 150.0, 0.0)
	fill_l.light_energy = 0.45
	_rec_vp.add_child(fill_l)

func _spawn_rec_enemy() -> void:
	if _rec_stage == null:
		return
	for c in _rec_stage.get_children():
		c.queue_free()
	var e := ENEMY_SCENE.instantiate()
	e.enemy_type = REC_ZAKO[randi() % REC_ZAKO.size()]
	e.hue = randf() * 360.0
	_rec_stage.add_child(e)
	e.remove_from_group("enemies")
	e.set_process(false)
	e.set_physics_process(false)
	e.position = Vector3.ZERO
	# Hide any lock marker / data label so the portrait reads as just the creature.
	for ch in e.get_children():
		if ch is Label3D:
			(ch as Label3D).visible = false

# 0..1 progress through the whole crawl (drives the auto-descent in Main).
func ending_progress() -> float:
	if not _ending_active:
		return 0.0
	var n: int = ENDING_LINES.size()
	if n <= 1:
		return 1.0
	var hold := float(_ending_hold(int(ENDING_LINES[_ending_idx][1])))
	var frac: float = clampf(float(_ending_t) / maxf(hold, 1.0), 0.0, 1.0)
	return clampf((float(_ending_idx) + frac) / float(n - 1), 0.0, 1.0)

# True once the crawl is on the final line ("GAME OVER").
func ending_on_last() -> bool:
	return _ending_active and _ending_idx >= ENDING_LINES.size() - 1

func _ending_hold(kind: int) -> int:
	match kind:
		1: return 220   # big title
		2: return 80    # "..." beat
		3: return 150   # the BOSS sting
		4: return 130   # record / system readout
		_: return 150   # normal line

func show_message(msg: String, sub: String) -> void:
	_msg = msg
	_sub = sub
	_msg_t = 210

# Crossing a boundary gate into a new star system: wipe the old system's stars —
# the drifting named stars, the discovered target, the cleared-name memory and any
# spawned target planet — so the new system gets a fresh sky of fresh names.
func reset_for_new_system() -> void:
	_stars.clear()
	_hover_idx = -1
	GameState.target_star = ""
	GameState.cleared_stars.clear()
	GameState.golden_offered = false   # the new system gets its own one-time G icon
	for p in get_tree().get_nodes_in_group("target_planet"):
		if p == null or not is_instance_valid(p) or (p as Node).is_queued_for_deletion():
			continue
		if p.has_method("dispose_immediate"):
			p.call("dispose_immediate")
		else:
			(p as Node).queue_free()

func _process(_delta: float) -> void:
	if _ending_active:
		_update_ending()
		queue_redraw()
		return
	if _msg_t > 0:
		_msg_t -= 1
	if not GameState.in_transition():
		GameState.entry_glow = maxf(GameState.entry_glow - 0.015, 0.0)

	if GameState.plate_announce_t > 0:
		GameState.plate_announce_t -= 1
	if GameState.hubris_msg_t > 0:
		GameState.hubris_msg_t -= 1
	_update_reticle()
	_update_stars()
	queue_redraw()

func _update_reticle() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sz := get_viewport().get_visible_rect().size
	var pz := GameState.alt_to_z(GameState.alt)
	var sp := camera.unproject_position(Vector3(GameState.px, GameState.py, pz))
	_reticle = sp + Vector2(0.0, -sz.y * RETICLE_AHEAD)

	# Planet stage: project the sight onto the destructible deck so Unit1 knows
	# exactly which surface column to drop its ground bombs on.
	if GameState.stage == "planet":
		var gdepth: float = camera.global_position.z - PlanetTerrain.ALT0_Z
		var gw := camera.project_position(_reticle, gdepth)
		GameState.reticle_ground = Vector2(gw.x, gw.y)

	_hover_idx = -1
	if _stars_interactive():
		var best := LOCK_RADIUS
		for i in _stars.size():
			var d: float = _reticle.distance_to(_stars[i]["pos"])
			if d < best:
				best = d
				_hover_idx = i
	GameState.reticle_hover = _hover_idx >= 0

func _update_stars() -> void:
	var sz := get_viewport().get_visible_rect().size
	if not _stars_visible():
		return
	if not _stars_interactive():
		return
	# Drift speed follows the background's altitude-scaled scroll.
	var scroll_mult := lerpf(2.0, 0.5, GameState.sky_t())
	for s in _stars:
		s["pos"] += Vector2(0.0, float(s["spd"]) * scroll_mult)
	for i in range(_stars.size() - 1, -1, -1):
		var pos := _stars[i]["pos"] as Vector2
		if pos.y > sz.y + 30.0:
			_stars.remove_at(i)
	while _stars.size() < MAX_STARS:
		_spawn_star(sz)
	# Campaign complete enough? The OMEGA CORE boss star rides the stream too.
	if GameState.boss_star_ready() and GameState.target_star != "OMEGA CORE":
		var present := false
		for s in _stars:
			if s.get("boss", false):
				present = true
				break
		if not present:
			_stars.append({"name": "OMEGA CORE", "biome": "BOSS", "boss": true,
				"type": "boss",
				"pos": Vector2(sz.x * 0.5 + (randf() - 0.5) * sz.x * 0.5, -30.0),
				"spd": 0.35, "phase": 0.0})

# Mixes real star names with synthesized ones — an endless catalogue.
func _gen_name() -> String:
	var n: String
	if randf() < 0.45:
		n = STAR_NAMES[randi() % STAR_NAMES.size()]
	else:
		n = ""
		for i in 2 + randi() % 2:
			n += NAME_SYL[randi() % NAME_SYL.size()]
	return n + NAME_SUFFIX[randi() % NAME_SUFFIX.size()]

func _spawn_star(sz: Vector2) -> void:
	var name_s := ""
	for attempt in 6:
		name_s = _gen_name()
		if name_s == GameState.target_star or name_s == GameState.planet_name:
			continue
		if GameState.cleared_stars.has(name_s):
			continue
		var dup := false
		for s in _stars:
			if s["name"] == name_s:
				dup = true
				break
		if not dup:
			break
	var biomes: Array = []
	for k: String in PlanetTerrain.BIOMES:
		var bd: Dictionary = PlanetTerrain.BIOMES[k]
		if not bd.get("abyss", false) and not bd.get("boss", false):
			biomes.append(k)
	var star_type := _roll_star_type()
	_stars.append({
		"name": name_s,
		"biome": biomes[randi() % biomes.size()],
		"type": star_type,
		"boss": false,
		"pos": Vector2(40.0 + randf() * (sz.x - 80.0), -20.0 - randf() * sz.y * 0.5),
		"spd": 0.5 + randf() * 0.5,
		"phase": randf() * TAU,
	})

func _roll_star_type() -> String:
	# One kind of star now: every clickable star is a MINE star (resources + route plates).
	return "mine"

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# Ending: clicking BACK TO TITLE returns to the title (resets + reloads the scene).
	# The survivor monologue has no such button — swallow the click so it can't reset the run.
	if _ending_active:
		if not _mono and _back_rect.has_point(get_viewport().get_mouse_position()):
			get_tree().current_scene.call("back_to_title")
		return
	if _hover_idx < 0 or not _stars_interactive():
		return
	_discover(_stars[_hover_idx])
	_stars.remove_at(_hover_idx)
	_hover_idx = -1

func _discover(star: Dictionary) -> void:
	var biome: String = star["biome"]
	var label: String = PlanetTerrain.BIOMES[biome]["label"]
	var star_type: String = str(star.get("type", "boss"))
	GameState.target_star = star["name"]
	GameState.target_star_type = star_type
	show_message(Loc.pair("%s 発見！", "%s DISCOVERED!") % star["name"],
		Loc.pair("%s - 降下して接近", "%s - DESCEND TO APPROACH") % label)
	# Replace any previous target with a planet at the clicked star's spot.
	var old_targets := get_tree().get_nodes_in_group("target_planet")
	for old in old_targets:
		if old == null or not is_instance_valid(old) or (old as Node).is_queued_for_deletion():
			continue
		if old.has_method("dispose_immediate"):
			old.call("dispose_immediate")
		else:
			(old as Node).queue_free()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var depth: float = camera.global_position.z - TargetPlanet.BG_Z
	var wp := camera.project_position(star["pos"], depth)
	var planet := TargetPlanet.new()
	planet.star_name = star["name"]
	planet.biome = biome
	planet.star_type = star_type
	get_tree().current_scene.add_child(planet)
	planet.global_position = Vector3(wp.x, wp.y, TargetPlanet.BG_Z)

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var sz := get_viewport().get_visible_rect().size

	if _ending_active:
		_draw_ending(sz)
		_draw_fade(sz)
		return

	if GameState.title_active:
		var blink := 0.5 + 0.5 * sin(GameState.frame * 0.06)
		var lang_label := "%s:  %s   < J / E >" % [
			Loc.t("LANGUAGE"),
			Loc.t("Japanese") if Loc.is_ja() else Loc.t("English")
		]
		var lang_w := font.get_string_size(lang_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, Vector2(sz.x * 0.5 - lang_w * 0.5, sz.y * 0.70), lang_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.95, 1.0, 0.82))
		var label := Loc.t("PRESS ENTER / CLICK TO START")
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		draw_string(font, Vector2(sz.x * 0.5 - lw * 0.5, sz.y * 0.8), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.7, 0.9, 1.0, 0.35 + 0.55 * blink))
		return

	if GameState.game_over:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.0, 0.0, 0.6))
		var go := Loc.t("GAME OVER")
		var gw := font.get_string_size(go, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
		draw_string(font, Vector2(sz.x * 0.5 - gw * 0.5, sz.y * 0.42), go,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(1.0, 0.3, 0.25, 0.95))
		var blink2 := 0.5 + 0.5 * sin(GameState.frame * 0.08)
		var cont := Loc.t("CLICK  TO  CONTINUE")
		var cw := font.get_string_size(cont, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(font, Vector2(sz.x * 0.5 - cw * 0.5, sz.y * 0.42 + 46.0), cont,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.95, 0.6, 0.4 + 0.55 * blink2))
		return

	_draw_star_names(font)
	_draw_planet_label(font)
	_draw_beacons(font)
	if not GameState.is_zako_prototype_mode():
		_draw_reticle(font)     # GENESIS star-target sight — not used in the ZAKO prototype
	_draw_launch_count(font, sz)
	_draw_exit_hud(font, sz)
	_draw_route_map(font, sz)
	_draw_boss_hp(font, sz)
	_draw_plate_announce(font, sz)
	_draw_message(font, sz)
	_draw_takeover_alert(font, sz)
	_draw_hubris_message(font, sz)
	_draw_faith_gauge(font, sz)
	_draw_golden_joystick(sz)

	if GameState.entry_glow > 0.001:
		var g := GameState.entry_glow
		var t := GameState.entry_tint
		# Sink into the planet's OWN atmosphere: a haze in the biome sky color
		# that thickens from the bottom of the screen (the cloud deck rising as
		# we descend) and brightens toward the cloud-lit interior at the very
		# end — instead of a generic orange-to-white re-entry flash.
		var bright := smoothstep(0.55, 1.0, g)
		var top := t.lerp(Color(1, 1, 1), bright)
		var bot := t.lerp(Color(1, 1, 1), bright * 0.7)
		var a_top := clampf(g * 0.5 + bright * 0.5, 0.0, 1.0)
		var a_bot := clampf(g * 0.85 + bright * 0.15, 0.0, 1.0)
		var pts := PackedVector2Array([
			Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, sz.y), Vector2(0, sz.y)])
		var cols := PackedColorArray([
			Color(top.r, top.g, top.b, a_top), Color(top.r, top.g, top.b, a_top),
			Color(bot.r, bot.g, bot.b, a_bot), Color(bot.r, bot.g, bot.b, a_bot)])
		draw_polygon(pts, cols)
		# The billowing cloud sea the carrier slips through is real 3D geometry
		# (CloudPuff spawned by Mothership during the enter dive), not a full-screen
		# overlay — so the carrier passes between cloud layers instead of being
		# painted over.
	_draw_fade(sz)

# GERWALK virtual-joystick origin: a faint ring at the screen centre (the neutral/stop zone) with
# a line out to the cursor, so it's obvious the cursor steers BY OFFSET and centring it = stop.
func _draw_golden_joystick(sz: Vector2) -> void:
	if not (GameState.golden_walk and GameState.arena_active) \
			or GameState.golden_airplane_hold or GameState.survivor_monologue_active:
		return
	var c := sz * 0.5
	var mouse := get_viewport().get_mouse_position()
	var off := mouse - c
	var active := off.length() > 26.0
	var col := Color(0.7, 0.9, 1.0, 0.5 if active else 0.28)
	draw_arc(c, 26.0, 0.0, TAU, 40, col, 1.5)          # neutral ring
	draw_circle(c, 2.5, Color(0.8, 0.92, 1.0, 0.6))    # dead centre
	if active:
		draw_line(c, mouse, Color(0.7, 0.9, 1.0, 0.35), 1.5)   # the "stick" toward the cursor

# FAITH gauge — the true-route standoff meter shown in place of HP while facing GOD / GENESIS.
func _draw_faith_gauge(font: Font, sz: Vector2) -> void:
	if GameState.god_phase != 1 and GameState.god_phase != 2:
		return   # only the GOD standoff; the Genesis offering shows SCORE draining instead
	var w := 360.0
	var h := 18.0
	var x := sz.x * 0.5 - w * 0.5
	var y := 54.0
	draw_string(font, Vector2(x, y - 8.0), Loc.t("FAITH"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(1.0, 0.92, 0.7, 0.9))
	draw_rect(Rect2(x, y, w, h), Color(0.05, 0.04, 0.07, 0.6))
	var f := clampf(GameState.faith_gauge, 0.0, 1.0)
	var col := Color(1.0, 0.78, 0.30).lerp(Color(1.0, 0.95, 0.7), f)
	draw_rect(Rect2(x + 2.0, y + 2.0, (w - 4.0) * f, h - 4.0), col)
	draw_rect(Rect2(x, y, w, h), Color(1.0, 0.9, 0.7, 0.5), false, 1.5)

# Full-screen black, on top of everything — the survivor outro fade out to space (and back in).
func _draw_fade(sz: Vector2) -> void:
	if GameState.fade_black > 0.001:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.0, 0.0, clampf(GameState.fade_black, 0.0, 1.0)))

func _draw_star_names(font: Font) -> void:
	if not _stars_visible():
		return
	# Distant-star parallax: at the top of space the names drift at their normal
	# size. As the ship descends (sky_t 1→0) the frozen names read as distant
	# stars we fly past — they spread outward from screen center, grow, and fade
	# out. Climbing back restores their size/positions and they drift again.
	var sz := get_viewport().get_visible_rect().size
	var center := sz * 0.5
	var descend_t := clampf(1.0 - GameState.sky_t(), 0.0, 1.0)
	var zoom := 1.0 + descend_t * 2.2
	var spread := 1.0 + descend_t * 1.4
	var fade := 1.0 - smoothstep(0.15, 0.9, descend_t)
	if fade <= 0.001:
		return
	for i in _stars.size():
		var s := _stars[i]
		var p: Vector2 = center + ((s["pos"] as Vector2) - center) * spread
		var is_boss: bool = s.get("boss", false)
		var tw := sin(GameState.frame * 0.07 + float(s["phase"]))
		var a := 0.55 + 0.25 * tw
		# One look for all (mining) stars; the final boss star (if it ever streams) is red.
		var col := Color(0.75, 0.88, 1.0, a)
		if is_boss:
			col = Color(1.0, 0.25, 0.2, 0.7 + 0.3 * tw)
		if i == _hover_idx:
			col = Color(1.0, 0.85, 0.3, 0.95)
		col.a *= fade
		# Sparkle cross (the boss star burns bigger, with a warning ring).
		var r := ((9.0 if is_boss else 5.0) + tw) * zoom
		draw_line(p + Vector2(-r, 0), p + Vector2(r, 0), col, 1.5)
		draw_line(p + Vector2(0, -r), p + Vector2(0, r), col, 1.5)
		if is_boss:
			draw_arc(p, (11.0 + tw * 2.0) * zoom, 0.0, TAU, 24, col, 1.5)
		# Star NAME only — no category prefix.
		draw_string(font, p + Vector2(12.0, 5.0) * zoom, str(s["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(round((15.0 if is_boss else 13.0) * zoom)), col)
		if i == _hover_idx:
			draw_arc(p, 14.0 * zoom, 0.0, TAU, 20, col, 1.5)

func _stars_visible() -> bool:
	# The true-route finale (GOD / GENESIS) plays in an empty cosmos — no drifting click-stars.
	return GameState.stage == "space" and not GameState.in_transition() \
		and GameState.god_phase == 0 and not GameState.is_zako_mode() \
		and not GameState.suppress_genesis_progression()

func _stars_interactive() -> bool:
	return GameState.stage == "space" and not GameState.in_transition() \
		and GameState.alt >= GameState.ALT_MAX - 1.0 and GameState.god_phase == 0 \
		and not GameState.is_zako_mode() and not GameState.suppress_genesis_progression()

func _type_short(star_type: String) -> String:
	match star_type:
		"mine":
			return "[M]"
		"rescue":
			return "[R]"
		_:
			return "[B]"

func _type_label(star_type: String) -> String:
	match star_type:
		"mine":
			return Loc.t("MINE STAR")
		"rescue":
			return Loc.t("RESCUE STAR")
		_:
			return Loc.t("BOSS STAR")

# Name + biome + approach % floating beside the discovered planet.
func _draw_planet_label(font: Font) -> void:
	if GameState.stage != "space":
		return
	var planet := get_tree().get_first_node_in_group("target_planet") as TargetPlanet
	if planet == null or not is_instance_valid(planet) or planet.is_queued_for_deletion() \
			or GameState.star_entry:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sp := camera.unproject_position(planet.global_position)
	var col := Color(0.5, 1.0, 0.85, 0.9)
	var label := "%s  %d%%" % [planet.star_name, int(planet.approach * 100.0)]
	draw_string(font, sp + Vector2(-30.0, -30.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	draw_string(font, sp + Vector2(-30.0, -14.0),
		PlanetTerrain.BIOMES[planet.biome]["label"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.9, 1.0, 0.7))
	var blink := 0.55 + 0.4 * sin(GameState.frame * 0.2)
	draw_string(font, sp + Vector2(-30.0, 2.0), Loc.t("DESCEND TO APPROACH"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.2, blink))

# Carrier-call signals: a pulsing reticle around each beacon's screen position
# with a "CARRIER SIGNAL" tag, so the call icon reads clearly over the stars.
func _draw_beacons(font: Font) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for b in get_tree().get_nodes_in_group("mothership_beacon"):
		var bn := b as Node3D
		if bn == null or not is_instance_valid(bn):
			continue
		var sp := camera.unproject_position(bn.global_position)
		var tw := 0.5 + 0.5 * sin(GameState.frame * 0.2)
		var col := Color(0.45, 0.95, 1.0, 0.55 + 0.4 * tw)
		var r := 24.0 + 6.0 * tw
		draw_arc(sp, r, 0.0, TAU, 28, col, 2.0)
		for a in 4:
			var ang := float(a) * PI * 0.5 + PI * 0.25
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(sp + dir * r, sp + dir * (r + 8.0), col, 2.0)
		draw_string(font, sp + Vector2(-34.0, -r - 8.0), Loc.t("CARRIER SIGNAL"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

# Solvalou bombsight: nested squares ahead of the ship. Red normally,
# gold + converging brackets while locked onto a star name. On planets it
# stays up as the ground-attack sight.
func _draw_reticle(font: Font) -> void:
	if GameState.game_over or GameState.in_transition():
		return
	var p := _reticle
	var locked := _hover_idx >= 0
	var col := Color(1.0, 0.78, 0.2, 0.95) if locked else Color(1.0, 0.3, 0.25, 0.8)
	var r := 14.0
	draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), col, false, 2.0)
	# Inner square blinks like the original sight.
	if (GameState.frame / 8) % 2 == 0 or locked:
		var ir := 5.0
		draw_rect(Rect2(p - Vector2(ir, ir), Vector2(ir * 2.0, ir * 2.0)), col, false, 1.5)
	if locked:
		# Corner brackets pulse inward onto the lock.
		var br := r + 6.0 + 3.0 * sin(GameState.frame * 0.3)
		for dx: float in [-1.0, 1.0]:
			for dy: float in [-1.0, 1.0]:
				var c := p + Vector2(dx * br, dy * br)
				draw_line(c, c + Vector2(-dx * 7.0, 0), col, 2.0)
				draw_line(c, c + Vector2(0, -dy * 7.0), col, 2.0)
		if _hover_idx >= 0 and _hover_idx < _stars.size():
			draw_string(font, p + Vector2(r + 10.0, 4.0),
				_stars[_hover_idx]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

# Legacy carrier-lane countdown. Planet travel is altitude-driven now, so this
# normally stays hidden unless older transition code sets launch_count.
func _draw_launch_count(font: Font, sz: Vector2) -> void:
	if GameState.launch_count <= 0.0:
		return
	var secs := int(ceil((1.0 - GameState.launch_count) * 2.0))
	var label := "%s %d" % [Loc.t("ATMOSPHERE ENTRY IN"), secs] if GameState.stage == "space" \
		else "%s %d" % [Loc.t("LAUNCH IN"), secs]
	var w := 220.0
	var bx := sz.x * 0.5 - w * 0.5
	draw_rect(Rect2(bx, 96.0, w, 8.0), Color(0.15, 0.35, 0.3, 0.6))
	draw_rect(Rect2(bx, 96.0, w * GameState.launch_count, 8.0), Color(0.4, 1.0, 0.8, 0.9))
	draw_string(font, Vector2(sz.x * 0.5 - float(label.length()) * 6.5, 88.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
		Color(0.5, 1.0, 0.85, 0.7 + 0.3 * sin(GameState.frame * 0.4)))

# Planet stages: climb-out hint near the orbital ceiling.
func _draw_exit_hud(font: Font, sz: Vector2) -> void:
	if GameState.stage == "space" or GameState.in_transition():
		return
	if GameState.alt > GameState.GROUND_ALT - 8.0:
		var a := 0.3 + 0.15 * sin(GameState.frame * 0.1)
		draw_string(font, Vector2(sz.x * 0.5 - 190.0, 76.0),
			Loc.t("CLIMB TO ALT1000 TO RETURN TO SPACE"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.9, 1.0, a))

# Top-center route map: the path to the final boss. First stage is ROUTE1; three
# route nodes (ROUTE1-3) link to a star node = ROUTE4, the boss star (宇宙俯瞰戦).
# A node is "reached" once the player is at that route; the current node pulses.
# The trailing label flags the armed true gate, or the boss panel at ROUTE4.
func _draw_route_map(font: Font, sz: Vector2) -> void:
	if GameState.game_over:
		return
	var goal := GameState.ROUTE_GOAL          # plain route nodes (ROUTE1..ROUTE3)
	var prog := GameState.route_progress      # 0..goal; current 0-based node index
	var spacing := 30.0
	var node_r := 6.0
	var label := "%s %d/%d" % [Loc.t("ROUTE"), GameState.route_number(), goal + 1]
	# Top-LEFT so it never overlaps the centred SCORE / EXP bar.
	var x0 := 24.0
	var y := 30.0
	var dim := Color(0.55, 0.7, 0.85, 0.65)
	var lit := Color(0.4, 1.0, 0.55, 0.95)
	draw_string(font, Vector2(x0, y + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var nx := x0 + label_w + 12.0 + node_r
	var prev := Vector2(nx, y)
	for i in goal:
		var c := Vector2(nx + float(i) * spacing, y)
		if i > 0:
			draw_line(prev, c, dim, 2.0)
		if prog >= i:                          # reached this route → solid
			draw_circle(c, node_r, lit)
		else:
			draw_arc(c, node_r, 0.0, TAU, 16, dim, 2.0)
		if prog == i:                          # current route → pulsing ring
			draw_arc(c, node_r + 3.0 + 1.5 * sin(GameState.frame * 0.2), 0.0, TAU, 18, lit, 1.5)
		prev = c
	# ROUTE4 = the boss star node (reached when route_complete).
	var boss_c := Vector2(nx + float(goal) * spacing, y)
	draw_line(prev, boss_c, dim, 2.0)
	var reached := GameState.route_complete()
	var boss_col := lit if reached else dim
	var br := 8.0 + (1.5 * sin(GameState.frame * 0.15) if reached else 0.0)
	draw_line(boss_c + Vector2(-br, 0), boss_c + Vector2(br, 0), boss_col, 2.0)
	draw_line(boss_c + Vector2(0, -br), boss_c + Vector2(0, br), boss_col, 2.0)
	draw_arc(boss_c, br, 0.0, TAU, 20, boss_col, 2.0)
	# Trailing status line: boss panel state at ROUTE4, else armed true-gate flag.
	var hint := ""
	if GameState.boss_armed:
		hint = Loc.t("BOSS PANEL FOUND - CLIMB TO SPACE")
	elif reached:
		hint = Loc.t("MINE THE BOSS STAR FOR THE BOSS PANEL")
	elif GameState.route_armed:
		hint = Loc.t("TRUE GATE OPEN - CROSS TO ADVANCE")
	if hint != "":
		var blink := 0.5 + 0.5 * sin(GameState.frame * 0.25)
		draw_string(font, Vector2(x0, y + 22.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 1.0, 0.55, 0.55 + 0.4 * blink))

# Final boss life bar (top, under the route map) while the space boss is present.
# Adds a "LAND ON THE CARRIER TO STRIKE" prompt until the player takes the helm.
func _draw_boss_hp(font: Font, sz: Vector2) -> void:
	if GameState.god_phase > 0:
		return   # the pacifist GOD/GENESIS shows the FACE gauge, not combat HP bars
	var boss := get_tree().get_first_node_in_group("space_boss")
	if boss == null or not is_instance_valid(boss):
		return
	# AngelBoss: three stacked altitude-layer bars (HIGH/MID/LOW); the band you're level
	# with is the only one you can damage, so it's highlighted.
	if boss.has_method("layer_count"):
		var w := minf(sz.x * 0.5, 440.0)
		var x := sz.x * 0.5 - w * 0.5
		var y := 50.0
		var blink := 0.5 + 0.5 * sin(GameState.frame * 0.2)
		draw_string(font, Vector2(x, y - 4.0), Loc.t("GOD"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4, 0.92))
		var labels := [Loc.t("HIGH"), Loc.t("MID"), Loc.t("LOW")]   # bars top→bottom = head→feet
		for row in 3:
			var i := 2 - row   # layer 2 (high) on top
			var by := y + 16.0 + float(row) * 18.0
			var frac: float = float(boss.call("layer_frac", i))
			var active: bool = bool(boss.call("layer_active", i))
			draw_string(font, Vector2(x - 44.0, by + 11.0), labels[row],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(1.0, 0.95, 0.6, 0.95) if active else Color(0.7, 0.72, 0.6, 0.6))
			draw_rect(Rect2(x, by, w, 12.0), Color(0.14, 0.10, 0.03, 0.7))
			var fc := Color(1.0, 0.85, 0.35) if active else Color(0.7, 0.6, 0.3)
			if active:
				fc = fc.lerp(Color(1.0, 1.0, 0.7), 0.4 * blink)
			draw_rect(Rect2(x, by, w * frac, 12.0), fc)
			draw_rect(Rect2(x, by, w, 12.0),
				Color(1.0, 0.9, 0.5, 0.9 if active else 0.4), false, 2.0 if active else 1.0)
		draw_string(font, Vector2(x, y + 16.0 + 3.0 * 18.0 + 12.0),
			Loc.t("FLY TO EACH ALTITUDE TO STRIKE THAT LAYER"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.95, 1.0, 0.55 + 0.4 * blink))
		return
	# Legacy carrier-strike boss (single bar).
	var hp: float = float(boss.get("hp"))
	var maxhp: float = maxf(1.0, float(boss.get("max_hp")))
	var frac := clampf(hp / maxhp, 0.0, 1.0)
	var w := minf(sz.x * 0.6, 520.0)
	var x := sz.x * 0.5 - w * 0.5
	var y := 54.0
	draw_string(font, Vector2(x, y - 4.0), Loc.t("THE GENESIS"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.4, 0.35, 0.9))
	draw_rect(Rect2(x, y, w, 10.0), Color(0.18, 0.06, 0.08, 0.7))
	draw_rect(Rect2(x, y, w * frac, 10.0), Color(1.0, 0.3, 0.22, 0.95))
	draw_rect(Rect2(x, y, w, 10.0), Color(1.0, 0.6, 0.5, 0.5), false, 1.5)
	if not GameState.carrier_battle:
		var blink := 0.5 + 0.5 * sin(GameState.frame * 0.2)
		draw_string(font, Vector2(x, y + 26.0),
			Loc.t("CATCH THE CARRIER SIGNAL - LAND TO TAKE THE HELM"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.95, 1.0, 0.55 + 0.4 * blink))

# Advance the crawl: each line fades in, holds, fades out, then the next appears.
# The final "GAME OVER" line stays up forever.
func _update_ending() -> void:
	# A slow, only-slight darkening (the landed scene stays visible behind the text).
	_ending_fade = minf(1.0, _ending_fade + 0.01)
	# On a new line: a "記録 #" starts a memorial block (pick a random fallen-enemy
	# portrait); a "..." beat ends it.
	if _ending_idx != _rec_line:
		_rec_line = _ending_idx
		var txt := str(ENDING_LINES[_ending_idx][0])
		var knd := int(ENDING_LINES[_ending_idx][1])
		if txt.begins_with("記録 #"):          # only real "記録 #NNNN" entries get a portrait
			_rec_active = true
			_spawn_rec_enemy()
		elif knd == 2:
			_rec_active = false
	# Portrait stays up for the WHOLE record block; fades only between blocks (not per line).
	_rec_fade = move_toward(_rec_fade, 1.0 if _rec_active else 0.0, 0.08)
	# It gently SWAYS (never a full spin) so it never turns edge-on / "seams".
	if _rec_stage != null:
		_rec_stage.rotation.y = 0.5 * sin(GameState.frame * 0.03)
		_rec_stage.rotation.x = 0.12 * sin(GameState.frame * 0.021)
	_ending_t += 1
	var hold := _ending_hold(int(ENDING_LINES[_ending_idx][1]))
	if _ending_t >= hold and _ending_idx < ENDING_LINES.size() - 1:
		_ending_idx += 1
		_ending_t = 0

func _draw_ending(sz: Vector2) -> void:
	# Only a slight darkening — the landed carrier on the homeworld shows through.
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.05, 0.5 * _ending_fade))
	if _ending_font == null:
		return
	var entry: Array = ENDING_LINES[_ending_idx]
	var text: String = _crawl_text(String(entry[0]))
	var kind: int = int(entry[1])
	var hold := _ending_hold(kind)
	# Per-line fade in/out (the last line never fades out).
	var fin := clampf(float(_ending_t) / 20.0, 0.0, 1.0)
	var fout := 1.0
	var is_last := _ending_idx >= ENDING_LINES.size() - 1
	if not is_last:
		fout = clampf(float(hold - _ending_t) / 20.0, 0.0, 1.0)
	var a := minf(fin, fout) * _ending_fade
	# 遺影: framed fallen-enemy portrait above the text. Uses its OWN block fade so it stays
	# solid through a whole 記録 block instead of blinking with each text line.
	if _rec_fade > 0.01:
		_draw_record_portrait(sz, sz.y * 0.5 - 150.0, _rec_fade * _ending_fade)
	# "..." beats are just SILENT GAPS now — no dots drawn, only the pause.
	if kind == 2:
		return
	var size := 30
	var col := Color(0.88, 0.92, 1.0, a)
	match kind:
		1:
			size = 54
			col = Color(1.0, 0.96, 0.7, a)
		3:
			size = 66
			col = Color(1.0, 0.3, 0.25, a)
		4:
			size = 24
			col = Color(0.55, 0.85, 0.95, a * 0.9)   # data/record readout
	var w := _ending_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_ending_font, Vector2(sz.x * 0.5 - w * 0.5, sz.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	if _mono:
		return   # monologue: no BACK TO TITLE button
	# Subtle BACK TO TITLE at the very bottom (clickable; handled in _input).
	var bt := Loc.t("BACK TO TITLE")
	var bw := _ending_font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var bx := sz.x * 0.5 - bw * 0.5
	var by := sz.y - 38.0
	var bb := 0.4 + 0.25 * sin(GameState.frame * 0.05)
	draw_string(_ending_font, Vector2(bx, by), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(0.6, 0.75, 0.9, bb * _ending_fade))
	_back_rect = Rect2(bx - 12.0, by - 18.0, bw + 24.0, 30.0)

func _crawl_text(raw: String) -> String:
	if raw.begins_with("記録 #"):
		return raw if Loc.is_ja() else raw.replace("記録", "RECORD")
	if Loc.is_ja():
		return raw
	return String(CRAWL_EN.get(raw, Loc.t(raw)))

# A memorial "portrait" (遺影) above the 記録 text: a framed panel showing the REAL in-game
# enemy model, rendered live in a little SubViewport (it turns slowly).
func _draw_record_portrait(sz: Vector2, top_y: float, a: float) -> void:
	var cx := sz.x * 0.5
	var fw := 150.0
	var fh := 150.0
	var fx := cx - fw * 0.5
	var fy := top_y - fh
	# Frame: light mat border + dark photo back + a black edge line.
	draw_rect(Rect2(fx - 6.0, fy - 6.0, fw + 12.0, fh + 12.0), Color(0.85, 0.85, 0.88, a))
	draw_rect(Rect2(fx, fy, fw, fh), Color(0.07, 0.08, 0.11, a))
	# The live enemy model.
	if _rec_vp != null:
		var tex := _rec_vp.get_texture()
		if tex != null:
			draw_texture_rect(tex, Rect2(fx, fy, fw, fh), false, Color(1.0, 1.0, 1.0, a))
	draw_rect(Rect2(fx - 6.0, fy - 6.0, fw + 12.0, fh + 12.0), Color(0.0, 0.0, 0.0, a), false, 2.0)

# Big centre-screen plate when a route/boss plate is unearthed: a glowing icon plate
# with "ROUTE n" (or "BOSS"), so the discovery is unmistakable.
func _draw_plate_announce(_font: Font, _sz: Vector2) -> void:
	# Superseded by the 3D golden monolith (RoutePlate.gd), spawned from Planet.gd on a
	# plate dig-out. The reveal + message now live ON that 3D plate, not this flat banner.
	return

func _draw_plate_announce_legacy(font: Font, sz: Vector2) -> void:
	if GameState.plate_announce_t <= 0:
		return
	var t := float(GameState.plate_announce_t)
	var a := clampf(t / 30.0, 0.0, 1.0) * clampf((180.0 - t) / 20.0 + 1.0, 0.0, 1.0)
	var boss := GameState.plate_announce_num <= 0
	var cx := sz.x * 0.5
	var cy := sz.y * 0.42
	# Plate body (rounded-ish via two rects) with a glowing border.
	var pw := 360.0
	var ph := 150.0
	var pulse := 0.6 + 0.4 * sin(GameState.frame * 0.2)
	var edge := (Color(1.0, 0.35, 0.3, a) if boss else Color(0.4, 1.0, 0.6, a))
	var body := Color(0.06, 0.10, 0.09, 0.82 * a)
	draw_rect(Rect2(cx - pw * 0.5, cy - ph * 0.5, pw, ph), body)
	draw_rect(Rect2(cx - pw * 0.5, cy - ph * 0.5, pw, ph), Color(edge.r, edge.g, edge.b, a * pulse), false, 4.0)
	var head := Loc.t("BOSS PLATE FOUND") if boss else Loc.t("ROUTE PLATE FOUND")
	var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(font, Vector2(cx - hw * 0.5, cy - 30.0), head,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.95, 1.0, a))
	var big := Loc.t("BOSS") if boss else ("%s %d" % [Loc.t("ROUTE"), GameState.plate_announce_num])
	var bw := font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 54).x
	draw_string(font, Vector2(cx - bw * 0.5, cy + 40.0), big,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color(edge.r, edge.g, edge.b, a))

# Boarding event: a blinking banner that stays up the WHOLE time the carrier is taken
# over (the one-shot show_message scrolls away). No full-screen tint — just a flashing
# alert so the locked repairs / unit pickups read at a glance.
func _draw_takeover_alert(font: Font, sz: Vector2) -> void:
	if not GameState.carrier_takeover or GameState.game_over or GameState.in_transition():
		return
	# Sharp on/off flash (明滅).
	var blink: float = 0.5 + 0.5 * sin(GameState.frame * 0.24)
	blink = blink * blink
	var ty := sz.y * 0.17
	var title := "!!  %s  !!" % Loc.t("CARRIER BOARDED")
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(font, Vector2(sz.x * 0.5 - tw * 0.5, ty), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1.0, 0.32, 0.28, 0.3 + 0.7 * blink))
	var sub := Loc.t("LAND ON THE DECK & REPEL THEM - REPAIRS / NEW UNITS LOCKED")
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(sz.x * 0.5 - sw * 0.5, ty + 24.0), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.8, 0.45 + 0.45 * blink))
	# Live hull readout that DRAINS while boarded — the crisis you can watch tick down.
	var frac: float = clampf(GameState.carrier_hull / GameState.CARRIER_HULL_MAX, 0.0, 1.0)
	var low: float = 1.0 - frac           # 0 full → 1 empty: redder & flashier as it drops
	var urgent: float = 0.4 + 0.6 * blink * (0.5 + 0.5 * low)   # low hull = harder flash
	var bw := 300.0
	var bh := 18.0
	var bx := sz.x * 0.5 - bw * 0.5
	var by := ty + 50.0
	var label := Loc.t("CARRIER HULL")
	draw_string(font, Vector2(bx, by - 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1.0, 0.8, 0.75, 0.7 + 0.3 * blink))
	var vtxt := "%d / %d" % [int(ceil(GameState.carrier_hull)), int(GameState.CARRIER_HULL_MAX)]
	var vw := font.get_string_size(vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(bx + bw - vw, by - 4.0), vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1.0, 0.85, 0.8, 0.8 + 0.2 * blink))
	draw_rect(Rect2(bx, by, bw, bh), Color(0.12, 0.04, 0.04, 0.7), true)         # empty track
	var fill_col := Color(1.0, 0.75, 0.25).lerp(Color(1.0, 0.18, 0.12), low)     # amber → red
	fill_col.a = urgent
	draw_rect(Rect2(bx, by, bw * frac, bh), fill_col, true)                      # draining fill
	draw_rect(Rect2(bx, by, bw, bh), Color(1.0, 0.4, 0.35, 0.6 + 0.4 * blink), false, 2.0)
	# Mercenary defenders: a row of HP pips so you can watch your hired guns hold the line.
	var my := by + bh + 8.0
	draw_string(font, Vector2(bx, my + 9.0), Loc.t("MERCENARIES"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.7, 0.95, 1.0, 0.85))
	var pip_w := (bw - 6.0 * float(GameState.MERC_MAX - 1)) / float(GameState.MERC_MAX)
	for i in GameState.MERC_MAX:
		var px := bx + float(i) * (pip_w + 6.0)
		draw_rect(Rect2(px, my + 14.0, pip_w, 8.0), Color(0.10, 0.12, 0.14, 0.7), true)
		if i < GameState.mercs.size():
			var hpf: float = clampf(GameState.merc_hp(i) / GameState.MERC_HP_MAX, 0.0, 1.0)
			var mc := Color(0.3, 1.0, 0.55).lerp(Color(1.0, 0.5, 0.2), 1.0 - hpf)
			draw_rect(Rect2(px, my + 14.0, pip_w * hpf, 8.0), Color(mc.r, mc.g, mc.b, 0.9), true)
		draw_rect(Rect2(px, my + 14.0, pip_w, 8.0), Color(0.5, 0.8, 1.0, 0.5), false, 1.0)
	# Auto-repair status: the repair-fund bar + whether the lab is actively rebuilding.
	var ry := my + 30.0
	var repairing: bool = GameState.stockpile >= GameState.AUTO_REPAIR_COST \
		and GameState.carrier_hull < GameState.CARRIER_HULL_MAX
	var rstate := Loc.t("REPAIRING") if repairing else (Loc.t("FULL") if GameState.carrier_hull >= GameState.CARRIER_HULL_MAX else Loc.t("NO STOCKPILE"))
	draw_string(font, Vector2(bx, ry + 9.0), "%s  [%s]" % [Loc.t("AUTO-REPAIR"), rstate],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.5, 1.0, 0.7, 0.85) if repairing else Color(0.75, 0.78, 0.82, 0.7))
	var fundf: float = clampf(float(GameState.stockpile) / float(GameState.STOCKPILE_MAX), 0.0, 1.0)
	draw_rect(Rect2(bx, ry + 14.0, bw, 8.0), Color(0.08, 0.12, 0.10, 0.7), true)
	var fc2 := Color(0.3, 1.0, 0.6) if repairing else Color(0.4, 0.6, 0.5)
	draw_rect(Rect2(bx, ry + 14.0, bw * fundf, 8.0), Color(fc2.r, fc2.g, fc2.b, 0.9), true)
	var ftxt := "%s %d/%d" % [Loc.t("REPAIR FUND"), GameState.stockpile, GameState.STOCKPILE_MAX]
	var fw := font.get_string_size(ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, Vector2(bx + bw - fw, ry + 9.0), ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.7, 0.95, 0.8, 0.8))

func _draw_message(font: Font, sz: Vector2) -> void:
	if _msg_t <= 0:
		return
	var a := clampf(float(_msg_t) / 40.0, 0.0, 1.0)
	var col := Color(1.0, 0.95, 0.5, a)
	var msg := Loc.t(_msg)
	var sub := Loc.t(_sub)
	draw_string(font, Vector2(sz.x * 0.5 - msg.length() * 7.0, sz.y * 0.32), msg,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
	if sub != "":
		draw_string(font, Vector2(sz.x * 0.5 - sub.length() * 3.6, sz.y * 0.32 + 28.0),
			sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.7, 0.9, 1.0, a * 0.85))

# Symbolic center-screen announcement the moment 慢心 maxes out (the ship stops firing).
# A dark band with a heavy two-line message — a beat that says "stop and think".
func _draw_hubris_message(font: Font, sz: Vector2) -> void:
	if GameState.hubris_msg_t <= 0:
		return
	var t := float(GameState.hubris_msg_t)
	var total := float(GameState.HUBRIS_MSG_FRAMES)
	# Fade in over ~0.5 s, hold, fade out over ~1 s.
	var a := clampf(minf((total - t) / 30.0, t / 60.0), 0.0, 1.0)
	var cy := sz.y * 0.44
	var pulse := 0.5 + 0.5 * sin(GameState.frame * 0.12)
	# Dark symbolic band across the screen with hot-red edge lines.
	draw_rect(Rect2(0.0, cy - 66.0, sz.x, 132.0), Color(0.0, 0.0, 0.0, 0.6 * a))
	var edge := Color(1.0, 0.45, 0.35, (0.5 + 0.4 * pulse) * a)
	draw_rect(Rect2(0.0, cy - 66.0, sz.x, 3.0), edge)
	draw_rect(Rect2(0.0, cy + 63.0, sz.x, 3.0), edge)
	var line1 := Loc.t("The player grew hubristic.")
	var line2 := Loc.t("Time to think.")
	var w1 := font.get_string_size(line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	draw_string(font, Vector2(sz.x * 0.5 - w1 * 0.5, cy - 8.0), line1,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1.0, 0.82, 0.74, a))
	var w2 := font.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_string(font, Vector2(sz.x * 0.5 - w2 * 0.5, cy + 34.0), line2,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.95, 0.8, 0.75, 0.9 * a))
