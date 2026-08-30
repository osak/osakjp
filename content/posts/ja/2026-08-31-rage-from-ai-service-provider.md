---
title: "怒れるAIサービスプロバイダ"
slug: "2026-08-31-rage-from-ai-service-provider"
date: 2026-08-31T00:00:00+09:00
draft: false
---

AIサービスプロバイダの中の人がTwitterで理不尽なキレ方をしている事案を立て続けに2つ見た。

1つ目はfal AI。MiniMax H3を改良して超高速に動画生成ができるようにしたMiniMax H3 Maxを8/29にリリースした。しかし同じ日にHao AI Labという研究室もMiniMax H3の高速化板をOSSとして公開した。これが気に食わなかったらしく "batuhan the fal guy" という名前のfalの中の人がHao AI Labをボロクソにこき下ろした。

https://x.com/isidentical/status/2093482587268522188

> But when you see people claiming they are X times faster than original while messing the quality to a degree that the outputs has nothing to do with original model, it is annoying.

> Without preference and quality evals in the loop, ai-slop-performance agents can just lead you into a way you generate random pixels and it is just dishonest to call it anything but a random-pixel-generator.

非営利の大学の研究室が公開する研究結果に対する反応としては度を超えた罵詈雑言を投げつけている。攻撃された研究室のHao Zhangが冷静に対応している点もfal側の滑稽さと下品さを際立たせている。

https://x.com/haozhangml/status/2093501374172697035

----

2つ目はOpenAI。[Cursorに対してサービス提供をやめる](https://openai.com/index/our-decision-on-cursor-following-its-acquisition-by-spacex/)というニュースリリースがあり、それを受けて「CursorのOpenAIシェアは5%だったけどね」と強がりを言ったSpaceXAIの中の人に対し、OpenAIのTiboが「（5%がトークン数ベースの話なんだとしたら）OpenAIの価値は5％なんてものじゃなかったはずだ（意訳）」と反駁していた。

https://x.com/mntruell/status/2093532254006063557
https://x.com/thsottiaux/status/2093784314714657110

> The 5% here should have come with strong caveat and I would love for Michael to share the math.

> Tokens are not a proxy for revenue nor value created and the OpenAI models are on the very frontier of token efficiency. Smaller or less strong models require many more tokens to achieve a task and therefore will inflate traffic share significantly.

契約破棄にはイーロン・マスクとの確執が原因の一つにあるらしく、その前提でSpaceX側から強がりを言うのもあまり行儀がいいとは言えないが、サービス提供側から契約を打ち切るという力関係の中で、打ち切られた側の捨て台詞に対して反駁していくTiboの反応はかなり下品だと感じる。

----

これらの事例に限らず、AnthoropicがClaude Codeの利用量制限を絞ろうとして反発を受けていたりと、AIサービスのプロバイダにとっては黒字化に向けてのかなり厳しい局面になっているんだろうなと感じる。今回AIプロバイダの中の人から出てきた苛烈な対応は、安くユーザーを囲い込もうとしたのに思うようにパイが取れなくなっており、垂れ流した赤字を回収できなくなる恐怖の裏返しなんだろうと思う。AIの拓いた可能性にただ熱狂する時代が終わり、正しく価値と向き合って値付けする時代へシフトしていく流れの中の出来事として象徴的に感じた。
