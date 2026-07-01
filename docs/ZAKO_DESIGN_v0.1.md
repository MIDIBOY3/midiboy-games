# 「雑魚になろう。」開発設計書 v0.1

> Authoritative design brief (pasted by the user 2026-07-01). GENESIS/TSG を土台に、新作
> 「雑魚になろう。」のプロトタイプを作る。**最初の検証目的はただ一つ：雑魚プレイだけで面白いか。**

## 目的

GENESIS / TSG で作った縦STGの操作感・高度システム・地形生成・ローポリ表現を土台に、
新作「雑魚になろう。」のプロトタイプを作る。完成版オンラインゲームを作るのが目的ではない。
まず検証するのは一つ：**雑魚プレイだけで面白いか。**

## ゲームコンセプト

オンラインゲームが苦手な人でも責任なく参加できる、非対称オンライン縦シューティング。
名もない雑魚として戦場に入り、数秒で倒されてもいい／一発撃って死んでもいい／5分だけ抜けてもいい。
それでも戦場の一部になれる。

## 基本思想

**弱くていい。すぐ死んでいい。責任がないから楽しい。**

## 世界構造

Hero側とZako側は別マップではなく **同じWorldを共有**する。
Heroは現在の戦場を進み、ZakoはHeroの **約10画面先**（未来の戦場）に存在する。

```text
Hero現在地 → 約10画面先 → Zako Front → Heroが後で到達する戦場
```

Zako側で生成された地形・砲台・障害物は、Heroが後で到達したときそのまま登場する。
= **敵側が未来のステージを作る** 構造。

## 重要な実装方針

### 1. World座標を使う
Hero / Zako / 地形 / 砲台 / 弾 / チャンクは全てWorld座標で管理。Screen座標で本体位置を管理しない。
描画時だけ `screenY = worldY - cameraY` のように変換する。

### 2. activeActor基準にする
F9でHero/Zakoを切り替えるとき、以下を全てactiveActor基準に：
`activeActor / cameraTarget / scrollTarget / terrainGenerationOrigin / spawnOrigin / visibleChunks / collisionChunks`。
Hero固定のままだとZakoを10画面先に出しても地形が生成されずスクロールが破綻する。

### 3. チャンクは共有する
Hero用/Zako用を別々に持たず、World全体のChunkManagerを共有する。
描画・当たり判定・敵AI更新はactiveActor周辺だけに限定：
```text
保持：Hero周辺 / Zako周辺チャンク    描画：activeActor周辺のみ
更新：activeActor周辺のみ            眠らせる：画面外の敵・弾・エフェクト
```

## F9切替仕様（開発用デバッグ）

最終的にはオンラインでHero/Zakoは別プレイヤー。今は1人で両方確認するためF9で切替。

**F9でZakoへ:** ①Heroの現在worldY取得 ②Heroの約10画面先にZako配置 ③Zako周辺にEnemy Front Chunk生成
④activeActor=Zako ⑤cameraTarget=Zako ⑥terrainGenerationOrigin=Zako ⑦visibleChunksをZako基準で再計算

**F9でHeroへ:** ①activeActor=Hero ②cameraTarget=Hero ③terrainGenerationOrigin=Hero ④visibleChunks再計算
⑤Zako側で作ったEnemy Front Chunkは破棄しない ⑥Heroが進行したらそのFront Chunkに到達できるように

## Enemy Front Chunk

Zakoは敵軍の前線に出撃する。生成物：`地形 / 砲台 / 障害物 / 敵スポーン地点 / レーザー塔 / バリア / 地雷 / 補給強化ポイント / 将来のボス素材`。
最初は `地形 / 砲台 / 障害物 / 敵スポーン` だけで十分。

**保存:** Enemy Front Chunkは見た目でなくWorldデータとして保存。HeroがそのworldYに到達したとき同じ地形・砲台・障害物が表示され機能する必要がある。**これが最初のプロトタイプの核。**

## 高度システム

`HIGH / MID / LOW` を維持。Hero/Zako両方が高度移動できる。高度は探索ギミックでなく戦術要素。
将来：LOW限定砲台 / HIGH限定攻撃 / MID安定移動 / LOW限定地形 / HIGH限定空中機雷 など。
最初は既存の高度システムを壊さずHero/Zako両方で動くことを優先。

## まず無効化するGENESIS由来要素（削除でなくprototype modeで無効化）

無効化：`クリック星 / 母艦 / ゲート / 星系選択 / BOSS KEY / BUDDY KEY / ストーリーイベント / エンディング進行 / 母艦帰還 / 星間移動`
残す：`Hero操作 / Zako操作 / F9切替 / 高度システム / スクロール / 地形チャンク生成 / 砲台 / 敵弾 / 当たり判定 / 爆発演出 / ローポリ・シェーダー表現`

## 最初に完成させるループ

```text
1. Heroで進む
2. F9でZakoへ切り替える
3. ZakoはHeroの10画面先に出る
4. Zako周辺にEnemy Front Chunkが生成される
5. Zakoとして前線を確認できる
6. F9でHeroへ戻る
7. Heroで進む
8. Zako側で作られた前線基地に遭遇する
```

## 重くしないための方針

10画面先を生成しても10画面分を常時描画・更新しない。
OK：チャンクデータ保持／必要範囲だけ描画／activeActor周辺だけ当たり判定／画面外の敵・弾・エフェクト停止。
NG：10画面分全描画／全チャンクの敵AI常時稼働／画面外の弾・爆発を更新し続ける。

## 将来仕様

- **オンライン化:** Hero少人数 / Zako多数。Zakoはいつでも参加・離脱可能。
- **プレイヤー抽選:** ZakoでHero希望ON → Hero撃墜 → 抽選 → PLAYER SELECTED → Hero → 死亡 → またZako。主人公も一時的な役割。
- **匿名無線:** ボイスチャットでなく匿名の戦場無線演出。誰が話しているか分からない＝責められない＝気軽。
- **ボス合体:** 多数のZakoが集結して巨大ボス（移動/砲台/シールド/雑魚射出担当）。倒されたら全員また雑魚へ。

## 優先順位

- **最優先:** World座標化 / activeActor切替 / ChunkManager共有 / Enemy Front Chunk生成 / HeroがFrontに到達できること
- **次:** Zako操作感 / 砲台配置 / 高度対応 / 画面外チャンクのスリープ
- **その次:** 匿名無線演出 / プレイヤー抽選演出 / ボス合体 / オンライン同期

## プロトタイプ第一段階の成功条件

```text
F9でZakoに切り替えると、Heroの未来に敵前線がある
Zako周辺に地形・砲台・障害物が生成される
Heroへ戻って進むと、その前線に実際に遭遇する
Hero/Zakoどちらでも高度移動が破綻しない
スクロール・カメラ・地形生成がactiveActor基準で動く
```

## 最後に

GENESISは発売用でなくR&Dだった。ここでは操作感/高度システム/ローポリ/シェーダー/地形生成/爆発演出/
Godot開発経験/AI開発ワークフローを使う。まず **雑魚で遊ぶだけで笑えるか** を証明する。
