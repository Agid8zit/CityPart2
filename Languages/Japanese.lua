return {
	-- Key: unique identifier for the string
	-- Value: either a string (if no dialects), or a table of dialects + fallback
	
	__default_dialect = "ja_kanto",
	
--Numbers & Stuff
	["1"] = {
		["_default"] = "..."
	},

	["2"] = {
		["_default"] = "..."
	},

	["3"] = {
		["_default"] = "..."
	},

	["4"] = {
		["_default"] = "..."
	},

	["5"] = {
		["_default"] = "..."
	},

	["6"] = {
		["_default"] = "..."
	},

	["7"] = {
		["_default"] = "..."
	},

	["8"] = {
		["_default"] = "..."
	},
	
	["9"] = {
		["_default"] = "..."
	},

	["0"] = {
		["_default"] = "..."
	},


-- Main UI

	--Main UI
	["Build"] = {
		["_default"] = "...",
		["ja_kanto"] = "建設"
	},
	["Home"] = {
		["_default"] = "This is an example translation."
	},
	
	["Undo"] = {
		["_default"] = "...",
		["ja_kanto"] = "元に戻す"
	},
	["Redo"] = {
		["_default"] = "...",
		["ja_kanto"] = "やり直し"
	},

	--TABS
	["Transport"] = {
		["_default"] = "...",
		["ja_kanto"] = "交通"
	},
	["Zones"] = {
		["_default"] = "...",
		["ja_kanto"] = "ゾーン"
	},
	["Services"] = {
		["_default"] = "...",
		["ja_kanto"] = "サービス"
	},
	["Supply"] = {
		["_default"] = "...",
		["ja_kanto"] = "資源"
	},
	["Road"] = {
		["_default"] = "...",
		["ja_kanto"] = "道路"
	},
	["Bus"] = {
		["_default"] = "...",
		["ja_kanto"] = "バス"
	},
	["Bus Depot"] = {
		["_default"] = "Bus Depot",
		["ja_kanto"] = "...",
	},
	["Bus Depot Owned"] = {
		["_default"] = "Bus Depot (Owned)",
		["ja_kanto"] = "...",
	},
	["Metro"] = {
		["_default"] = "...",
		["ja_kanto"] = "地下鉄"
	},
	["METRO"] = {
		["_default"] = "...",
		["ja_kanto"] = "地下鉄"
	},
	["Airport"] = {
		["_default"] = "...",
		["ja_kanto"] = "空港"
	},
	["AIRPORT"] = {
		["_default"] = "...",
		["ja_kanto"] = "空港"
	},
	["Airport Owned"] = {
		["_default"] = "Airport (Owned)",
		["ja_kanto"] = "...",
	},

	--Zones
	["Residential Zone"] = {
		["_default"] = "...",
		["ja_kanto"] = "住宅地"
	},
	["Commercial Zone"] = {
		["_default"] = "...",
		["ja_kanto"] = "商業地"
	},
	["Industrial Zone"] = {
		["_default"] = "...",
		["ja_kanto"] = "工業地"
	},
	["Dense Residential Zone"] = {
		["_default"] = "...",
		["ja_kanto"] = "高密度住宅地"
	},
	["Dense Commercial Zone"] = {
		["_default"] = "...",
		["ja_kanto"] = "高密度商業地"
	},
	["Dense Industrial Zone"] = {
		["_default"] = "...",
		["ja_kanto"] = "高密度工業地"
	},

	--Services
	["Leisure"] = {
		["_default"] = "...",
		["ja_kanto"] = "娯楽"
	},
	["Fire Dept"] = {
		["_default"] = "...",
		["ja_kanto"] = "消防署"
	},
	["Police"] = {
		["_default"] = "...",
		["ja_kanto"] = "警察"
	},
	["Health"] = {
		["_default"] = "...",
		["ja_kanto"] = "医療"
	},
	["Education"] = {
		["_default"] = "...",
		["ja_kanto"] = "教育"
	},
	["Sports"] = {
		["_default"] = "...",
		["ja_kanto"] = "スポーツ"
	},
	["Landmarks"] = {
		["_default"] = "...",
		["ja_kanto"] = "ランドマーク"
	},

	--Supply
	["Power"] = {
		["_default"] = "...",
		["ja_kanto"] = "電力"
	},
	["Water"] = {
		["_default"] = "...",
		["ja_kanto"] = "水道"
	},
	["Garbage"] = {
		["_default"] = "...",
		["ja_kanto"] = "ゴミ"
	},
	["Graves"] = {
		["_default"] = "...",
		["ja_kanto"] = "墓地"
	},

	--COOP
	["Co-Op"] = {
		["_default"] = "...",
		["ja_kanto"] = "協力プレイ"
	},
	["You've been invited to co-op PlayerName"] = {
		["_default"] = "...",
		["ja_kanto"] = "PlayerNameに協力プレイへ招待されました"
	},
	["Ignore"] = {
		["_default"] = "...",
		["ja_kanto"] = "無視する"
	},
	["Accept"] = {
		["_default"] = "...",
		["ja_kanto"] = "承諾"
	},
	["Invite Friends"] = {
		["_default"] = "...",
		["ja_kanto"] = "友達を招待"
	},
	["Leave Co-Op"] = {
		["_default"] = "...",
		["ja_kanto"] = "協力プレイを退出"
	},
	["Invite"] = {
		["_default"] = "...",
		["ja_kanto"] = "招待"
	},

	--Demands
	["Demands"] = {
		["_default"] = "...",
		["ja_kanto"] = "需要"
	},
	["Demand = Higher Bar"] = {
		["_default"] = "...",
		["ja_kanto"] = "需要レベル＝バーの高さ"
	},
	["Poor"] = {
		["_default"] = "...",
		["ja_kanto"] = "低所得"
	},
	["Medium"] = {
		["_default"] = "...",
		["ja_kanto"] = "中所得"
	},
	["Wealthy"] = {
		["_default"] = "...",
		["ja_kanto"] = "高所得"
	},

	--Power
	["Produced"] = {
		["_default"] = "...",
		["ja_kanto"] = "生産量"
	},
	["Used"] = {
		["_default"] = "...",
		["ja_kanto"] = "使用量"
	},
	["Usage"] = {
		["_default"] = "...",
		["ja_kanto"] = "使用量"
	},

	--Load Menu
	["Build A City"] = {
		["_default"] = "...",
		["ja_kanto"] = "街を作る"
	},
	["Load"] = {
		["_default"] = "...",
		["ja_kanto"] = "ロード"
	},
	["New"] = {
		["_default"] = "...",
		["ja_kanto"] = "新規"
	},
	["Last Played"] = {
		["_default"] = "...",
		["ja_kanto"] = "前回のプレイ"
	},

	--Premium Shop
	["Money"] = {
		["_default"] = "...",
		["ja_kanto"] = "所持金"
	},
	["Gamepass"] = {
		["_default"] = "...",
		["ja_kanto"] = "ゲームパス"
	},
	["10% More!"] = {
		["_default"] = "...",
		["ja_kanto"] = "10％増量！"
	},
	["15% More!"] = {
		["_default"] = "...",
		["ja_kanto"] = "15％増量！"
	},
	["25% More!"] = {
		["_default"] = "...",
		["ja_kanto"] = "25％増量！"
	},
	["Best Deal!"] = {
		["_default"] = "...",
		["ja_kanto"] = "最もお得！"
	},
	["$"] = {
		["_default"] = "...",
		["ja_kanto"] = "¥"
	},
	["Purchase"] = {
		["_default"] = "...",
		["ja_kanto"] = "購入"
	},
	["Ok"] = {
		["_default"] = "...",
		["ja_kanto"] = "OK"
	},

	--Robux Thanks
	["Thank you!"] = {
		["_default"] = "...",
		["ja_kanto"] = "拝謝申し上げます！"
	},
	["Thanks for supporting our team, and our charity donations :D"] = {
		["_default"] = "...",
		["ja_kanto"] = "私たちのチームと慈善活動へのご支援、拝謝申し上げます^^"
	},



--Town Twitter
--Power
	["A blackout again? I can't even call or email the electrical company when there's no power :("] = {
		["_default"] = "A blackout again? I can't even call or email the electrical company when there's no power :(",
		["ja_kanto"] = "また停電？ 電気ないと電力会社に電話もメールもできないじゃん！",
		["ja_kansai"] = "また停電かいな？ 電気ないと電力会社に電話もメールもでけへんやん！",
		["ja_tohoku"] = "また停電だすか？ 電気ねぇと電力会社に電話もでぎねぇや！",
		["ja_kyushu"] = "また停電と？ 電気なかと電力会社に電話もできんばい！",
		["ja_hokkaido"] = "また停電かよ？ 電気ねぇと電力会社に電話もできねぇや！",
		["ja_okinawa"] = "また電気ぬ切れやびーん？ 電気ねーし電力会社ん電話ち打てん！"
	},
	["Help, my TV doesn't work when there's no power!"] = {
		["_default"] = "Help, my TV doesn't work when there's no power!",
		["ja_kanto"] = "助けて、テレビが映らないよ！",
		["ja_kansai"] = "助けて～！ テレビも見れへんわ！",
		["ja_tohoku"] = "助けてぐで、テレビ映んねぇや！",
		["ja_kyushu"] = "助けてっちゃ！ テレビ映らんたい！",
		["ja_hokkaido"] = "助けてくれよ、テレビ映んねぇ！",
		["ja_okinawa"] = "助けーよー、TVん映らん！"
	},
	["Power to the people! How hard is it to build a working power grid? It’s not exactly state of the art technology."] = {
		["_default"] = "Power to the people! How hard is it to build a working power grid? It’s not exactly state of the art technology.",
		["ja_kanto"] = "電力供給ってそんなに難しいの？ 最新技術じゃないんだからさ...",
		["ja_kansai"] = "電力供給なんてそんな難しいんか？ 別に最新技術やないやろ",
		["ja_tohoku"] = "電力供給なんてそんなに難ぐねぇべ？ 最新技術じゃねぇし...",
		["ja_kyushu"] = "電力供給なんてそぎゃん難しかと？ 最新技術じゃなかばってん...",
		["ja_hokkaido"] = "電力供給なんてそんだけ難しいか？ 別に最新技術じゃねぇし",
		["ja_okinawa"] = "電力供給やてー、そんな難しくないやんねー。最新技術やねーし..."
	},
	--Water
	["Hey, guys, is the water supposed to be brown and crunchy?"] = {
		["_default"] = "Hey, guys, is the water supposed to be brown and crunchy?",
		["ja_kanto"] = "ねえ、この水って茶色くてザラザラしてるの普通？",
		["ja_kansai"] = "おい、この水茶色くてジャリジャリしてへん？",
		["ja_tohoku"] = "おら、この水茶色くてザラザラすんの？",
		["ja_kyushu"] = "おい、この水茶色かってジャリジャリすると？",
		["ja_hokkaido"] = "おい、この水茶色くてジャリジャリしてねぇか？",
		["ja_okinawa"] = "ウヤ、この水ヤマトゥカチ（茶色）やん？ジャリジャリしとーん？"
	},
	["Don't I pay my taxes for services like water??? This is absurd!"] = {
		["_default"] = "Don't I pay my taxes for services like water??? This is absurd!",
		["ja_kanto"] = "税金払ってるのにこんな水質ってありえないでしょ！",
		["ja_kansai"] = "税金払ってんのにこんなんアカンやろ！",
		["ja_tohoku"] = "税金払ってるのにこんなんおかしくねぇか！",
		["ja_kyushu"] = "税金払うちゅーにこんなんあかんばい！",
		["ja_hokkaido"] = "税金払ってるのにこんなんありえねぇ！",
		["ja_okinawa"] = "税金払ちゅーるくにこんな水やていいが？"
	},
	["I would think that fresh water is basic stuff, but NO! How long do we have to wait for working water pipes!?"] = {
		["_default"] = "I would think that fresh water is basic stuff, but NO! How long do we have to wait for working water pipes!?",
		["ja_kanto"] = "安全な水くらい供給してよ！ 水道管直すのいつまで待たせる気？",
		["ja_kansai"] = "安全な水くらい出せよ！ 水道直すのいつまで待たすねん",
		["ja_tohoku"] = "安全な水ぐれぇ出せねぇもんか！ 水道直すのいつまで待たすんだ？",
		["ja_kyushu"] = "安全な水くらい出せんと！ 水道直すのいつまで待たすとっち！",
		["ja_hokkaido"] = "安全な水くらい出せよ！ 水道直すのいつまで待たすんだ？",
		["ja_okinawa"] = "安全ん水出しゅーれー！ 水道直すん待ちゆるうや？"
	},
	["Ban crime! I want no more crime!"] = {
		["_default"] = "Ban crime! I want no more crime!",
		["ja_kanto"] = "犯罪なんてなくなればいいのに！",
		["ja_kansai"] = "犯罪なんかなくなれ～！",
		["ja_tohoku"] = "犯罪なんてねぇ方がいいすぺ！",
		["ja_kyushu"] = "犯罪なんかなくなればよか！",
		["ja_hokkaido"] = "犯罪なくすべ！",
		["ja_okinawa"] = "犯罪禁止！もう犯罪やらさんで"
	},
	["I will happily pay some extra taxes, if we can get the crime levels down."] = {
		["_default"] = "I will happily pay some extra taxes, if we can get the crime levels down.",
		["ja_kanto"] = "犯罪率下がるなら多少税金上がってもいいわ",
		["ja_kansai"] = "犯罪減るなら税金ちょい上がってもええわ",
		["ja_tohoku"] = "犯罪減るなら税金少しくらい上がってもいいべ",
		["ja_kyushu"] = "犯罪減るなら税金ちょっと上がってもよか",
		["ja_hokkaido"] = "犯罪減るなら税金多少上がってもいいべさ",
		["ja_okinawa"] = "犯罪減るなら税金少し上がちゅーるん、いいやびーん"
	},
--Misc
	["Was there always a road there? I like it."] = {
		["_default"] = "Was there always a road there? I like it.",
		["ja_kanto"] = "ここ前から道あった？ いいね",
		["ja_kansai"] = "ここに前から道あったんか？ ええなぁ",
		["ja_tohoku"] = "ここ前から道あったんだっけ？ 好きだわ",
		["ja_kyushu"] = "ここ前から道あったと？ よかね",
		["ja_hokkaido"] = "ここ前から道あったっけ？ いいね",
		["ja_okinawa"] = "クーニ前から道あったやびたん？ 好ぎやびーん"
	},
	["Did you know there are more planes in the ocean than submarines in the sky?"] = {
		["_default"] = "Did you know there are more planes in the ocean than submarines in the sky?",
		["ja_kanto"] = "海の飛行機より空の潜水艦の方が少ないって知ってた？",
		["ja_kansai"] = "海の飛行機より空の潜水艦の方が少ないって知ってた？",
		["ja_tohoku"] = "海の飛行機より空の潜水艦の方が少ねぇって知ってだ？",
		["ja_kyushu"] = "海の飛行機より空の潜水艦の方が少ないって知っとった？",
		["ja_hokkaido"] = "海の飛行機より空の潜水艦の方が少ないって知ってた？",
		["ja_okinawa"] = "海ん中飛行機より空ん中潜水艦少なやびーん知たん？"
	},
	["I like the new coffee shop downtown."] = {
		["_default"] = "I like the new coffee shop downtown.",
		["ja_kanto"] = "新しいカフェ気に入った",
		["ja_kansai"] = "新しいカフェええ感じやんか",
		["ja_tohoku"] = "新しいカフェいいすぺ",
		["ja_kyushu"] = "新しいカフェよかね",
		["ja_hokkaido"] = "新しいカフェいい感じ",
		["ja_okinawa"] = "新しく開ちたカフェ好ぎやびーん"
	},
	["Everyone has the right to be stupid, it's just some people abuse the privilege."] = {
		["_default"] = "Everyone has the right to be stupid, it's just some people abuse the privilege.",
		["ja_kanto"] = "バカになる権利は誰にでもあるけど、濫用する人いるよね",
		["ja_kansai"] = "アホになる権利はみんなあるけど、やりすぎる奴おるわ",
		["ja_tohoku"] = "バカになる権利は皆にあるけど、やりすぎる人いるんだわ",
		["ja_kyushu"] = "バカになる権利はみんにあるけど、やりすぎる奴おるばい",
		["ja_hokkaido"] = "バカになる権利はみんなあるけど、やりすぎる奴いるよな",
		["ja_okinawa"] = "バカなる権利やてー、全人にあるん。使い過ぎる人いるやびーん"
	},
	["My friend said that the old factory has a really cool abandoned tunnel in it. I don't think I'll find out for myself."] = {
		["_default"] = "My friend said that the old factory has a really cool abandoned tunnel in it. I don't think I'll find out for myself.",
		["ja_kanto"] = "廃工場に秘密トンネルあるらしいけど、自分で確かめる気ないや",
		["ja_kansai"] = "廃工場に秘密トンネルあるらしいけど、自分で見に行かへん",
		["ja_tohoku"] = "廃工場に秘密トンネルあるって聞だけど、自分で見に行がねぇ",
		["ja_kyushu"] = "廃工場に秘密トンネルあるって聞いたけど、自分で見に行かん",
		["ja_hokkaido"] = "廃工場に秘密トンネルあるって聞いたけど、自分で見に行かねぇ",
		["ja_okinawa"] = "廃工場ん中秘密トンネルあるやびたん、自分ん見行かん"
	},
	["I dont think inside the box or outside the box... I dont even know where the box is..."] = {
		["_default"] = "I dont think inside the box or outside the box... I dont even know where the box is...",
		["ja_kanto"] = "枠とか考えないタイプなんだ。そもそも枠の存在がわからん",
		["ja_kansai"] = "枠とか考えへんタイプやねん。そもそも枠の存在がわからへん",
		["ja_tohoku"] = "枠とか考えねぇタイプなんだ。そもそも枠がわがんね",
		["ja_kyushu"] = "枠とか考えんタイプやっち。そもそも枠がわからん",
		["ja_hokkaido"] = "枠とか考えねぇタイプだ。そもそも枠がわかんね",
		["ja_okinawa"] = "枠やてー考えん。そもそも枠ん所在わかん"
	},
	["I think I might paint my house blue. I like blue."] = {
		["_default"] = "I think I might paint my house blue. I like blue.",
		["ja_kanto"] = "家を青く塗ろうかな。青が好きなんだ",
		["ja_kansai"] = "家を青く塗ろっかな。青が好きやねん",
		["ja_tohoku"] = "家を青く塗ろっかな。青が好きなんだ",
		["ja_kyushu"] = "家を青く塗ろっかな。青が好きやっち",
		["ja_hokkaido"] = "家を青く塗ろっかな。青が好きなんだ",
		["ja_okinawa"] = "家青く塗ゆる考えやびーん。青好ぎやびーん"
	},
	["Things just aren’t what they used to be. And probably never were."] = {
		["_default"] = "Things just aren’t what they used to be. And probably never were.",
		["ja_kanto"] = "昔は良かったって言うけど、多分最初からダメだった",
		["ja_kansai"] = "昔は良かった言うけど、多分最初からアカンかった",
		["ja_tohoku"] = "昔は良かったって言うけど、多分最初からだめだった",
		["ja_kyushu"] = "昔は良かたって言うけど、多分最初からダメやった",
		["ja_hokkaido"] = "昔は良かったって言うけど、多分最初からダメだった",
		["ja_okinawa"] = "昔や良かったやしが、多分最初から良くなかったはず"
	},
	["I’ve always wanted to be somebody, but I see now I should’ve been more specific."] = {
		["_default"] = "I’ve always wanted to be somebody, but I see now I should’ve been more specific.",
		["ja_kanto"] = "誰かになりたかったけど、具体的に決めとけば良かった",
		["ja_kansai"] = "誰かになりたかったけど、具体的にしとけば良かった",
		["ja_tohoku"] = "誰かになりたかったけど、具体的にしとげば良かった",
		["ja_kyushu"] = "誰かになりたかたけど、具体的にしとけば良かた",
		["ja_hokkaido"] = "誰かになりたかったけど、具体的にしとけば良かった",
		["ja_okinawa"] = "誰かんなりたかたやびたん、具体的ん決ちゅーた方が良かた"
	},
	["The early bird can have the worm, because worms are gross and mornings are stupid."] = {
		["_default"] = "The early bird can have the worm, because worms are gross and mornings are stupid.",
		["ja_kanto"] = "早起きした人がミミズを獲れるって？ ミミズ気持ち悪いし朝も嫌い",
		["ja_kansai"] = "早起きの人がミミズ獲れるって？ ミミズキモいし朝も嫌いや",
		["ja_tohoku"] = "早起きの人がミミズ獲れるって？ ミミズきもいし朝も嫌いだ",
		["ja_kyushu"] = "早起きの人がミミズ獲るって？ ミミズキモかし朝も嫌いや",
		["ja_hokkaido"] = "早起きの人がミミズ獲れるって？ ミミズ気持ち悪いし朝も嫌いだ",
		["ja_okinawa"] = "早起きすん人ミミズ獲ゆるやびたん？ ミミズ嫌いや朝嫌いや"
	},
	["I love the new trees they planted in my neighborhood."] = {
		["_default"] = "I love the new trees they planted in my neighborhood.",
		["ja_kanto"] = "近所に植えた新しい木がいい感じ",
		["ja_kansai"] = "近所の新しい木ええ感じや",
		["ja_tohoku"] = "近所の新しい木いい感じだ",
		["ja_kyushu"] = "近所の新しい木よかね",
		["ja_hokkaido"] = "近所の新しい木いい感じだ",
		["ja_okinawa"] = "新しく植ちた木好ぎやびーん"
	},
	["Be yourself. No one can ever tell you’re doing it wrong."] = {
		["_default"] = "Be yourself. No one can ever tell you’re doing it wrong.",
		["ja_kanto"] = "自分らしくいれば、間違いなんてないよ",
		["ja_kansai"] = "自分らしくいんちゃい！ 誰も文句言えへんで",
		["ja_tohoku"] = "自分らしくいれば、文句言われねぇよ",
		["ja_kyushu"] = "自分らしくいんしゃい！ 誰も文句言えんばい",
		["ja_hokkaido"] = "自分らしくいれば文句言われねぇよ",
		["ja_okinawa"] = "自分らしくいちゅーれー、誰文句言えん"
	},
	["My favorite childhood memory, is not paying bills."] = {
		["_default"] = "My favorite childhood memory, is not paying bills.",
		["ja_kanto"] = "子供の頃は請求書なんてなかったのが最高だった",
		["ja_kansai"] = "子供の頃は請求書なんてなかったのが最高やった",
		["ja_tohoku"] = "子供の頃は請求書なんてなかったのが最高だった",
		["ja_kyushu"] = "子供の頃は請求書なんてなかたが最高やった",
		["ja_hokkaido"] = "子供の頃は請求書なんてなかったのが最高だった",
		["ja_okinawa"] = "子供んどぅー、請求書なかたん最高やたん"
	},
	["Did you know that birds control time? They do this out of spite."] = {
		["_default"] = "Did you know that birds control time? They do this out of spite.",
		["ja_kanto"] = "鳥が時間を支配してるって？ 意地悪でやってるんだって",
		["ja_kansai"] = "鳥が時間支配してるって？ 意地悪でやってるねんて",
		["ja_tohoku"] = "鳥が時間支配してるって？ 意地悪でやってるんだって",
		["ja_kyushu"] = "鳥が時間支配しとるって？ 意地悪でやっとるっち",
		["ja_hokkaido"] = "鳥が時間支配してるって？ 意地悪でやってるんだって",
		["ja_okinawa"] = "鳥や時間支配しちゅるやびたん？ 意地悪でやちゅるん"
	},
	["If someone makes you happy, make them happier."] = {
		["_default"] = "If someone makes you happy, make them happier.",
		["ja_kanto"] = "幸せにしてくれる人には、もっと幸せをあげよう",
		["ja_kansai"] = "幸せにしてくれる人には、もっと幸せ返そか",
		["ja_tohoku"] = "幸せにしてくれる人には、もっと幸せ返そっかな",
		["ja_kyushu"] = "幸せにしてくれる人には、もっと幸せ返そっか",
		["ja_hokkaido"] = "幸せにしてくれる人には、もっと幸せ返そう",
		["ja_okinawa"] = "幸せさす人ん、もっと幸せ返そー"
	},
	["I like bananas because they have no bones."] = {
		["_default"] = "I like bananas because they have no bones.",
		["ja_kanto"] = "バナナは骨がないから好き",
		["ja_kansai"] = "バナナは骨ないから好きや",
		["ja_tohoku"] = "バナナは骨ねぇから好きだ",
		["ja_kyushu"] = "バナナは骨なかから好きや",
		["ja_hokkaido"] = "バナナは骨ないから好きだ",
		["ja_okinawa"] = "バナナや骨なかん好ぎやびーん"
	},
	["A raccoon ate through my trashcan yesterday. It was a really cute raccoon, so I'm not really mad about it."] = {
		["_default"] = "A raccoon ate through my trashcan yesterday. It was a really cute raccoon, so I'm not really mad about it.",
		["ja_kanto"] = "アライグマがゴミ箱破ったけど可愛かったから許しちゃった",
		["ja_kansai"] = "アライグマがゴミ荒らしたけどカワイイから許した",
		["ja_tohoku"] = "アライグマがゴミ荒らしたけど可愛げだったから許しちゃった",
		["ja_kyushu"] = "アライグマがゴミ荒らしたけど可愛かたから許した",
		["ja_hokkaido"] = "タヌキがゴミ荒らしたけど可愛かったから許しちゃった",
		["ja_okinawa"] = "アライグマ ゴミ箱破ちたん、カワイカッタン許した"
	},
	["Forever is a long time. But not as long as it was yesterday."] = {
		["_default"] = "Forever is a long time. But not as long as it was yesterday.",
		["ja_kanto"] = "永遠って長いけど、昨日よりは短いかも",
		["ja_kansai"] = "永遠って長いけど、昨日よりはマシか",
		["ja_tohoku"] = "永遠って長いけど、昨日よりは短いかも",
		["ja_kyushu"] = "永遠って長かけど、昨日よりは短かかも",
		["ja_hokkaido"] = "永遠って長いけど、昨日よりは短いかも",
		["ja_okinawa"] = "永遠や長さんど、昨日より短かやびーん"
	},
	["I've heard they're getting rid of Ohio. It's for the best, really."] = {
		["_default"] = "I've heard they're getting rid of Ohio. It's for the best, really.",
		["ja_kanto"] = "オハイオ州なくすらしいよ。そりゃそうだ",
		["ja_kansai"] = "オハイオ州なくすらしいで。そらそうや",
		["ja_tohoku"] = "オハイオ州なくすらしいすぺ。そりゃそうだ",
		["ja_kyushu"] = "オハイオ州なくすらしいばい。そりゃそうや",
		["ja_hokkaido"] = "オハイオ州なくすらしい。そりゃそうだ",
		["ja_okinawa"] = "オハイオ州なくすやびたん。そりゃそうや"
	},
	["Have you seen Marvin? He owes me money."] = {
		["_default"] = "Have you seen Marvin? He owes me money.",
		["ja_kanto"] = "マービン見なかった？ 金返してくれないんだ",
		["ja_kansai"] = "マービン見えへん？ 金返してくれへんねん",
		["ja_tohoku"] = "マービン見でねぇ？ 金返してくれねぇんだ",
		["ja_kyushu"] = "マービン見んか？ 金返してくれんち",
		["ja_hokkaido"] = "マービン見なかった？ 金返してくれないんだ",
		["ja_okinawa"] = "マービン見たや？ 金返さゆるん"
	},
	["Do you think my cat knows about the feminist movement?"] = {
		["_default"] = "Do you think my cat knows about the feminist movement?",
		["ja_kanto"] = "猫ってフェミニズム運動知ってると思う？",
		["ja_kansai"] = "猫ってフェミニズム知ってると思う？",
		["ja_tohoku"] = "猫ってフェミニズム知ってるがな？",
		["ja_kyushu"] = "みんなで集まったら街の巨人倒せるっちゃなか?",
		["ja_hokkaido"] = "猫ってフェミニズム知ってると思う？",
		["ja_okinawa"] = "猫やフェミニズム知ちゅるやびーん？"
	},
	["Norbert has a face you’d want to punch. Not because there is anything wrong with the face itself, but just because it's his and he is mean."] = {
		["_default"] = "Norbert has a face you’d want to punch. Not because there is anything wrong with the face itself, but just because it's his and he is mean.",
		["ja_kanto"] = "ノーバートの顔は殴りたくなる。顔自体は普通だけど性格が最悪",
		["ja_kansai"] = "ノーバートの顔は殴りたくなる。顔は普通やけど性格が最悪",
		["ja_tohoku"] = "ノーバートの顔は殴りたくなる。顔は普通だけど性格が悪い",
		["ja_kyushu"] = "ノーバートの顔は殴りたくなる。顔は普通やけど性格が悪か",
		["ja_hokkaido"] = "ノーバートの顔は殴りたくなる。顔は普通だけど性格が最悪",
		["ja_okinawa"] = "ノーバートん顔やぶちたくなる。顔普通やど性格悪さん"
	},
	["Refusing to have an opinion, is a way of having one, isn’t it?"] = {
		["_default"] = "Refusing to have an opinion, is a way of having one, isn’t it?",
		["ja_kanto"] = "意見持たないのも、立派な意見だよね",
		["ja_kansai"] = "意見持たへんのも立派な意見やねん",
		["ja_tohoku"] = "意見持たねぇのも立派な意見だっけな",
		["ja_kyushu"] = "意見持たんのも立派な意見やっち",
		["ja_hokkaido"] = "意見持たないのも立派な意見だよな",
		["ja_okinawa"] = "意見持たんんや立派ん意見やびーん"
	},
	["My name is Len, short for Lenjamin."] = {
		["_default"] = "My name is Len, short for Lenjamin.",
		["ja_kanto"] = "俺の名前はレン。レンジャミンの略",
		["ja_kansai"] = "ウチの名前はレン。レンジャミンの略や",
		["ja_tohoku"] = "おらの名前はレン。レンジャミンの略だ",
		["ja_kyushu"] = "うちの名前はレン。レンジャミンの略や",
		["ja_hokkaido"] = "俺の名前はレン。レンジャミンの略だ",
		["ja_okinawa"] = "ワンヌ名前やレン。レンジャミンん略や"
	},
	["Do you think if we get enough of us together, we could overthrow the gigantic person that runs our city?"] = {
		["_default"] = "Do you think if we get enough of us together, we could overthrow the gigantic person that runs our city?",
		["ja_kanto"] = "みんなで集まって街を動かしてる巨人倒せるかな？",
		["ja_kansai"] = "みんなで集まって街の巨人倒せるかな？",
		["ja_tohoku"] = "みんなで集まって街の巨人倒せるがかな？",
		["ja_kyushu"] = "みんなで集まって街の巨人倒せるかな？",
		["ja_hokkaido"] = "みんなで集まって街の巨人倒せるかな？",
		["ja_okinawa"] = "皆集まてー市ん巨人倒せんやびーん？"
	},
	["I cannot become what I need to be, by remaining what I am."] = {
		["_default"] = "I cannot become what I need to be, by remaining what I am.",
		["ja_kanto"] = "今の自分じゃダメだ。変わらなきゃ",
		["ja_kansai"] = "今のままじゃアカン。変わらな",
		["ja_tohoku"] = "今のままだめだ。変わらなきゃ",
		["ja_kyushu"] = "今のままだめや。変わらんと",
		["ja_hokkaido"] = "今のままじゃダメだ。変わらなきゃ",
		["ja_okinawa"] = "今ん自分んままだめや。変わらんと"
	},
	["It’s ok that you’re not who you thought you’d be."] = {
		["_default"] = "It’s ok that you’re not who you thought you’d be.",
		["ja_kanto"] = "理想の自分じゃなくても大丈夫",
		["ja_kansai"] = "理想の自分じゃなくてもええねん",
		["ja_tohoku"] = "理想の自分じゃなくても大丈夫だべ",
		["ja_kyushu"] = "理想の自分じゃなくても大丈夫や",
		["ja_hokkaido"] = "理想の自分じゃなくても大丈夫だ",
		["ja_okinawa"] = "理想ん自分じゃなくてん大丈夫やびーん"
	},
	["If you feel like everyone else hates you, you need sleep. If you feel like you hate everyone else, you need to eat."] = {
		["_default"] = "If you feel like everyone else hates you, you need sleep. If you feel like you hate everyone else, you need to eat.",
		["ja_kanto"] = "みんなが自分を嫌ってると思うなら寝不足。自分がみんなを嫌ってるなら空腹",
		["ja_kansai"] = "皆に嫌われてる気がするなら寝不足。皆が嫌いなら空腹や",
		["ja_tohoku"] = "皆に嫌われてる気がするなら寝不足。皆が嫌いなら空腹だ",
		["ja_kyushu"] = "皆に嫌われとる気がするなら寝不足。皆が嫌いなら空腹や",
		["ja_hokkaido"] = "皆に嫌われてる気がするなら寝不足。皆が嫌いなら空腹だ",
		["ja_okinawa"] = "皆嫌い思ゆるなら寝不足。皆嫌いなら空腹や"
	},
	["Do you think whoever runs this city knows what a penguin looks like? I don't, and I am really curious."] = {
		["_default"] = "Do you think whoever runs this city knows what a penguin looks like? I don't, and I am really curious.",
		["ja_kanto"] = "この街の運営者、ペンギンの姿知ってるかな？ 気になる",
		["ja_kansai"] = "この街のボス、ペンギン知ってるかな？ 気になるわ",
		["ja_tohoku"] = "この街のボス、ペンギン知ってるが？ 気になるべ",
		["ja_kyushu"] = "この街のボス、ペンギン知っとると？ 気になるばい",
		["ja_hokkaido"] = "この街の運営者、ペンギン知ってるかな？ 気になる",
		["ja_okinawa"] = "市ん運営者、ペンギン知ちゅるやびーん？ 気になるやびーん"
	},
	["I think ultimately you become whoever would have saved you that time that no one did."] = {
		["_default"] = "I think ultimately you become whoever would have saved you that time that no one did.",
		["ja_kanto"] = "結局人は、あの時助けてくれなかった人になりたがるんだ",
		["ja_kansai"] = "結局人は、あの時助けてくれへんかった人になりたがるねん",
		["ja_tohoku"] = "結局人は、あの時助けてくれねぇ人になりたがるんだ",
		["ja_kyushu"] = "結局人は、あの時助けてくれんかった人になりたがるっち",
		["ja_hokkaido"] = "結局人は、あの時助けてくれなかった人になりたがるんだ",
		["ja_okinawa"] = "結局人や、あぬ時助けゆらん人んなりたがるやびーん"
	},
	["I learn something everyday. And a lot of times, it’s that what I learned yesterday, was wrong."] = {
		["_default"] = "I learn something everyday. And a lot of times, it’s that what I learned yesterday, was wrong.",
		["ja_kanto"] = "毎日何か学んでる。でも昨日学んだことが間違いだと気づくこと多い",
		["ja_kansai"] = "毎日何か学ぶねん。でも昨日学んだこと間違いやったって気付く",
		["ja_tohoku"] = "毎日何か学ぶべ。でも昨日学んだこと間違いだったってわかる",
		["ja_kyushu"] = "毎日何か学ぶばい。でも昨日学んだこと間違いやったってわかる",
		["ja_hokkaido"] = "毎日何か学ぶよ。でも昨日学んだこと間違いだったってわかる",
		["ja_okinawa"] = "毎日何か学ぶやびーん。昨日学んだ事間違いやったん知る"
	},
	["I know that when the world falls apart, raccoons will never judge me. They will only haunt my waking nightmares with their tiny, tiny hands."] = {
		["_default"] = "I know that when the world falls apart, raccoons will never judge me. They will only haunt my waking nightmares with their tiny, tiny hands.",
		["ja_kanto"] = "世界が終わってもアライグマは私を裁かない。ただ小さな手で悪夢を見せるだけ",
		["ja_kansai"] = "世界終わってもアライグマはウチを裁かへん。小さい手で悪夢見せるだけ",
		["ja_tohoku"] = "世界終わってもアライグマはおらを裁がねぇ。小さい手で悪夢見せるだけ",
		["ja_kyushu"] = "世界終わってもアライグマはうちを裁かん。小さい手で悪夢見せるだけ",
		["ja_hokkaido"] = "世界終わってもタヌキは俺を裁かない。小さな手で悪夢見せるだけ",
		["ja_okinawa"] = "世界終わてんアライグマワンん裁かん。小さい手で悪夢見さすん"
	},
	["I've got to be careful going in search of adventure. It’s ridiculously easy to find."] = {
		["_default"] = "I've got to be careful going in search of adventure. It’s ridiculously easy to find.",
		["ja_kanto"] = "冒険探しに行くのは注意が必要。簡単に見つかりすぎるから",
		["ja_kansai"] = "冒険探しに行ったら簡単に見つかりすぎるから注意やで",
		["ja_tohoku"] = "冒険探しに行ったら簡単に見つかりすぎるから注意だ",
		["ja_kyushu"] = "冒険探しに行ったら簡単に見つかりすぎるけん注意や",
		["ja_hokkaido"] = "冒険探しに行ったら簡単に見つかりすぎるから注意だ",
		["ja_okinawa"] = "冒険探し行ちゃん注意要る。簡単ん見つかゆるから"
	},
	["Latest news: A new type of deodorant has been invented! It does exactly the same thing as the old ones."] = {
		["_default"] = "Latest news: A new type of deodorant has been invented! It does exactly the same thing as the old ones.",
		["ja_kanto"] = "最新ニュース：新しいデオドラント発明！ 従来品と全く同じ効果",
		["ja_kansai"] = "最新ニュース：新デオドラント完成！ 今までと全然変わらん",
		["ja_tohoku"] = "最新ニュース：新デオドラント出だ！でも今までど変わんねぇ",
		["ja_kyushu"] = "最新ニュース：新デオドラント完成！ 今までと一緒ばい",
		["ja_hokkaido"] = "最新ニュース：新デオドラント開発！ 従来品と変わんね",
		["ja_okinawa"] = "最新ニュース：新デオドラント開発！ 前んと全く同じ"
	},
	["If god isn't real then why does the palm of a man fit so perfectly against the throat of a goose?"] = {
		["_default"] = "If god isn't real then why does the palm of a man fit so perfectly against the throat of a goose?",
		["ja_kanto"] = "神様いないなら、なんで人間の手首がガチョウの喉にピッタリなの？",
		["ja_kansai"] = "神様おらへんのになんで人間の手がガチョウの喉にピッタリやねん",
		["ja_tohoku"] = "神様いねぇんなら、なんで人間の手がガチョウの喉に合うんだ？",
		["ja_kyushu"] = "神様おらんとになんで人間ん手がガチョウん喉に合うとっち？",
		["ja_hokkaido"] = "神様いないなら、なんで人間の手がガチョウの喉に合うんだ？",
		["ja_okinawa"] = "神様おらんなら、なんで人間の手がガチョウの喉にぴったり合うん?"
	},
	
	



	
--On Boarding
	["BUILD SOME FUCKING WATER"] = {
		["_default"] = "Hello Citizen!",
		["DIALECT1"] = "Xello Bratan!",
		["DIALECT2"] = "Oy eh bud!",
		["DIALECT3"] = "RELEASE MY SOUL!",

	},

	["⬆️ UPGRADE"] = {
		["_default"] = "⬆️ UPGRADE",
		["ja_kanto"] = "⬆️ UPGRADE",
	},

	["Boombox Song"] = {
		["_default"] = "Boombox Song",
		["ja_kanto"] = "Boombox Song",
	},

	["CREDITS"] = {
		["_default"] = "CREDITS",
		["ja_kanto"] = "CREDITS",
	},

	["Delete"] = {
		["_default"] = "Delete",
		["ja_kanto"] = "Delete",
	},

	["No"] = {
		["_default"] = "No",
		["ja_kanto"] = "No",
	},

	["Delete Save"] = {
		["_default"] = "Delete Save",
		["ja_kanto"] = "Delete Save",
	},

	["Cancel"] = {
		["_default"] = "Cancel",
		["ja_kanto"] = "Cancel",
	},

	["Yes"] = {
		["_default"] = "Yes",
		["ja_kanto"] = "Yes",
	},

	["Offsale"] = {
		["_default"] = "Offsale",
		["ja_kanto"] = "Offsale",
	},

	["To Purchase"] = {
		["_default"] = "To Purchase",
		["ja_kanto"] = "To Purchase",
	},

	["x2 Earnings!"] = {
		["_default"] = "x2 Earnings!",
		["ja_kanto"] = "x2 Earnings!",
	},

	["Collect"] = {
		["_default"] = "Collect",
		["ja_kanto"] = "Collect",
	},

	["ON"] = {
		["_default"] = "ON",
		["ja_kanto"] = "ON",
	},

	["Template"] = {
		["_default"] = "Template",
		["ja_kanto"] = "Template",
	},

	["Settings"] = {
		["_default"] = "Settings",
		["ja_kanto"] = "Settings",
	},

	["City Name"] = {
		["_default"] = "City Name",
		["ja_kanto"] = "City Name",
	},

	["Language"] = {
		["_default"] = "Language",
		["ja_kanto"] = "Language",
	},

	["Mute"] = {
		["_default"] = "Mute",
		["ja_kanto"] = "Mute",
	},

	["Skip Song"] = {
		["_default"] = "Skip Song",
		["ja_kanto"] = "Skip Song",
	},

	["Social Media"] = {
		["_default"] = "Social Media",
		["ja_kanto"] = "Social Media",
	},

	["ConfirmDelete"] = {
		["_default"] = "ConfirmDelete",
		["ja_kanto"] = "ConfirmDelete",
	},

	["Refund_Amount"] = {
		["_default"] = "Refund_Amount",
		["ja_kanto"] = "Refund_Amount",
	},

	["Cant overlap zones"] = {
		["_default"] = "Cant overlap zones",
		["ja_kanto"] = "Cant overlap zones",
	},

	["Cant build on water"] = {
		["_default"] = "Cant build on water",
		["ja_kanto"] = "Cant build on water",
	},

	["Cant build on roads"] = {
		["_default"] = "Cant build on roads",
		["ja_kanto"] = "Cant build on roads",
	},

	["Cant build on unique buildings"] = {
		["_default"] = "Cant build on unique buildings",
		["ja_kanto"] = "Cant build on unique buildings",
	},

	["OB1_Begin"] = {
		["_default"] = "OB1_Begin",
		["ja_kanto"] = "OB1_Begin",
	},

	["OB1_Complete"] = {
		["_default"] = "OB1_Complete",
		["ja_kanto"] = "OB1_Complete",
	},

	["OB1_S1_Road_Hint"] = {
		["_default"] = "OB1_S1_Road_Hint",
		["ja_kanto"] = "OB1_S1_Road_Hint",
	},

	["OB1_S1_Road_Done"] = {
		["_default"] = "OB1_S1_Road_Done",
		["ja_kanto"] = "OB1_S1_Road_Done",
	},

	["OB1_S2_Residential_Hint"] = {
		["_default"] = "OB1_S2_Residential_Hint",
		["ja_kanto"] = "OB1_S2_Residential_Hint",
	},

	["OB1_S2_Residential_Done"] = {
		["_default"] = "OB1_S2_Residential_Done",
		["ja_kanto"] = "OB1_S2_Residential_Done",
	},

	["OB1_S3_WaterTower_Hint"] = {
		["_default"] = "OB1_S3_WaterTower_Hint",
		["ja_kanto"] = "OB1_S3_WaterTower_Hint",
	},

	["OB1_S3_WaterTower_Done"] = {
		["_default"] = "OB1_S3_WaterTower_Done",
		["ja_kanto"] = "OB1_S3_WaterTower_Done",
	},

	["OB1_S4_WaterPipe_A_Hint"] = {
		["_default"] = "OB1_S4_WaterPipe_A_Hint",
		["ja_kanto"] = "OB1_S4_WaterPipe_A_Hint",
	},

	["OB1_S4_WaterPipe_A_Done"] = {
		["_default"] = "OB1_S4_WaterPipe_A_Done",
		["ja_kanto"] = "OB1_S4_WaterPipe_A_Done",
	},

	["OB1_S5_WaterPipe_B_Hint"] = {
		["_default"] = "OB1_S5_WaterPipe_B_Hint",
		["ja_kanto"] = "OB1_S5_WaterPipe_B_Hint",
	},

	["OB1_S5_WaterPipe_B_Done"] = {
		["_default"] = "OB1_S5_WaterPipe_B_Done",
		["ja_kanto"] = "OB1_S5_WaterPipe_B_Done",
	},

	["OB1_S6_WindTurbine_Hint"] = {
		["_default"] = "OB1_S6_WindTurbine_Hint",
		["ja_kanto"] = "OB1_S6_WindTurbine_Hint",
	},

	["OB1_S6_WindTurbine_Done"] = {
		["_default"] = "OB1_S6_WindTurbine_Done",
		["ja_kanto"] = "OB1_S6_WindTurbine_Done",
	},

	["OB1_S7_PowerLines_A_Hint"] = {
		["_default"] = "OB1_S7_PowerLines_A_Hint",
		["ja_kanto"] = "OB1_S7_PowerLines_A_Hint",
	},

	["OB1_S7_PowerLines_A_Done"] = {
		["_default"] = "OB1_S7_PowerLines_A_Done",
		["ja_kanto"] = "OB1_S7_PowerLines_A_Done",
	},

	["OB1_S8_PowerLines_B_Hint"] = {
		["_default"] = "OB1_S8_PowerLines_B_Hint",
		["ja_kanto"] = "OB1_S8_PowerLines_B_Hint",
	},

	["OB1_S8_PowerLines_B_Done"] = {
		["_default"] = "OB1_S8_PowerLines_B_Done",
		["ja_kanto"] = "OB1_S8_PowerLines_B_Done",
	},

	["OB1_S9_Road2_Hint"] = {
		["_default"] = "OB1_S9_Road2_Hint",
		["ja_kanto"] = "OB1_S9_Road2_Hint",
	},

	["OB1_S9_Road2_Done"] = {
		["_default"] = "OB1_S9_Road2_Done",
		["ja_kanto"] = "OB1_S9_Road2_Done",
	},

	["OB1_S10_Commercial_Hint"] = {
		["_default"] = "OB1_S10_Commercial_Hint",
		["ja_kanto"] = "OB1_S10_Commercial_Hint",
	},

	["OB1_S10_Commercial_Done"] = {
		["_default"] = "OB1_S10_Commercial_Done",
		["ja_kanto"] = "OB1_S10_Commercial_Done",
	},

	["OB_OpenBuildMenu"] = {
		["_default"] = "OB_OpenBuildMenu",
		["ja_kanto"] = "OB_OpenBuildMenu",
	},

	["OB_OpenTransportTab"] = {
		["_default"] = "OB_OpenTransportTab",
		["ja_kanto"] = "OB_OpenTransportTab",
	},

	["OB_OpenZonesTab"] = {
		["_default"] = "OB_OpenZonesTab",
		["ja_kanto"] = "OB_OpenZonesTab",
	},

	["OB_OpenSupplyTab"] = {
		["_default"] = "OB_OpenSupplyTab",
		["ja_kanto"] = "OB_OpenSupplyTab",
	},

	["OB_OpenServicesTab"] = {
		["_default"] = "OB_OpenServicesTab",
		["ja_kanto"] = "OB_OpenServicesTab",
	},

	["OB_OpenWaterHub"] = {
		["_default"] = "OB_OpenWaterHub",
		["ja_kanto"] = "OB_OpenWaterHub",
	},

	["OB_OpenPowerHub"] = {
		["_default"] = "OB_OpenPowerHub",
		["ja_kanto"] = "OB_OpenPowerHub",
	},

	["OB2_Begin"] = {
		["_default"] = "OB2_Begin",
		["ja_kanto"] = "OB2_Begin",
	},

	["OB2_Complete"] = {
		["_default"] = "OB2_Complete",
		["ja_kanto"] = "OB2_Complete",
	},

	["OB2_WaterDeficit"] = {
		["_default"] = "OB2_WaterDeficit",
		["ja_kanto"] = "OB2_WaterDeficit",
	},

	["OB2_ConnectWater"] = {
		["_default"] = "OB2_ConnectWater",
		["ja_kanto"] = "OB2_ConnectWater",
	},

	["OB2_PowerDeficit"] = {
		["_default"] = "OB2_PowerDeficit",
		["ja_kanto"] = "OB2_PowerDeficit",
	},

	["OB2_ConnectPower"] = {
		["_default"] = "OB2_ConnectPower",
		["ja_kanto"] = "OB2_ConnectPower",
	},

	["OB_SelectRoad"] = {
		["_default"] = "OB_SelectRoad",
		["ja_kanto"] = "OB_SelectRoad",
	},

	["OB_SelectRoad_Done"] = {
		["_default"] = "OB_SelectRoad_Done",
		["ja_kanto"] = "OB_SelectRoad_Done",
	},

	["OB3_Begin"] = {
		["_default"] = "OB3_Begin",
		["ja_kanto"] = "OB3_Begin",
	},

	["OB3_Industrial_Hint"] = {
		["_default"] = "OB3_Industrial_Hint",
		["ja_kanto"] = "OB3_Industrial_Hint",
	},

	["OB3_Industrial_Done"] = {
		["_default"] = "OB3_Industrial_Done",
		["ja_kanto"] = "OB3_Industrial_Done",
	},

	["OB3_ConnectRoad"] = {
		["_default"] = "OB3_ConnectRoad",
		["ja_kanto"] = "OB3_ConnectRoad",
	},

	["OB3_ConnectRoadNetwork"] = {
		["_default"] = "OB3_ConnectRoadNetwork",
		["ja_kanto"] = "OB3_ConnectRoadNetwork",
	},

	["OB3_ConnectWater"] = {
		["_default"] = "OB3_ConnectWater",
		["ja_kanto"] = "OB3_ConnectWater",
	},

	["OB3_ConnectPower"] = {
		["_default"] = "OB3_ConnectPower",
		["ja_kanto"] = "OB3_ConnectPower",
	},

	["OB3_Complete"] = {
		["_default"] = "OB3_Complete",
		["ja_kanto"] = "OB3_Complete",
	},

	["Residential"] = {
		["_default"] = "Residential",
		["ja_kanto"] = "Residential",
	},

	["Commercial"] = {
		["_default"] = "Commercial",
		["ja_kanto"] = "Commercial",
	},

	["Industrial"] = {
		["_default"] = "Industrial",
		["ja_kanto"] = "Industrial",
	},

	["Fire Precinct"] = {
		["_default"] = "Fire Precinct",
		["ja_kanto"] = "Fire Precinct",
	},

	["Fire Station"] = {
		["_default"] = "Fire Station",
		["ja_kanto"] = "Fire Station",
	},

	["City Hospital"] = {
		["_default"] = "City Hospital",
		["ja_kanto"] = "City Hospital",
	},

	["Local Hospital"] = {
		["_default"] = "Local Hospital",
		["ja_kanto"] = "Local Hospital",
	},

	["Major Hospital"] = {
		["_default"] = "Major Hospital",
		["ja_kanto"] = "Major Hospital",
	},

	["Small Clinic"] = {
		["_default"] = "Small Clinic",
		["ja_kanto"] = "Small Clinic",
	},

	["MiddleSchool"] = {
		["_default"] = "MiddleSchool",
		["ja_kanto"] = "MiddleSchool",
	},

	["Museum"] = {
		["_default"] = "Museum",
		["ja_kanto"] = "Museum",
	},

	["NewsStation"] = {
		["_default"] = "NewsStation",
		["ja_kanto"] = "NewsStation",
	},

	["PrivateSchool"] = {
		["_default"] = "PrivateSchool",
		["ja_kanto"] = "PrivateSchool",
	},

	["Handy-Hardware"] = {
		["_default"] = "Handy-Hardware",
		["ja_kanto"] = "Handy-Hardware",
	},

	["Big-Buy-Mart"] = {
		["_default"] = "Big-Buy-Mart",
		["ja_kanto"] = "Big-Buy-Mart",
	},

	["Loading..."] = {
		["_default"] = "Loading...",
		["ja_kanto"] = "Loading...",
	},

	["Great-Grocery"] = {
		["_default"] = "Great-Grocery",
		["ja_kanto"] = "Great-Grocery",
	},

	["Supermarket"] = {
		["_default"] = "Supermarket",
		["ja_kanto"] = "Supermarket",
	},

	["Tea House"] = {
		["_default"] = "Tea House",
		["ja_kanto"] = "Tea House",
	},

	["LAUNDROMAT"] = {
		["_default"] = "LAUNDROMAT",
		["ja_kanto"] = "LAUNDROMAT",
	},

	["REPAIRS"] = {
		["_default"] = "REPAIRS",
		["ja_kanto"] = "REPAIRS",
	},

	["GROCERY"] = {
		["_default"] = "GROCERY",
		["ja_kanto"] = "GROCERY",
	},

	["Cozy Coffee"] = {
		["_default"] = "Cozy Coffee",
		["ja_kanto"] = "Cozy Coffee",
	},

	["Icecream"] = {
		["_default"] = "Icecream",
		["ja_kanto"] = "Icecream",
	},

	["Car Garage"] = {
		["_default"] = "Car Garage",
		["ja_kanto"] = "Car Garage",
	},

	["Italian-To-Go"] = {
		["_default"] = "Italian-To-Go",
		["ja_kanto"] = "Italian-To-Go",
	},

	["Corner Cafe"] = {
		["_default"] = "Corner Cafe",
		["ja_kanto"] = "Corner Cafe",
	},

	["HAIR-SALON"] = {
		["_default"] = "HAIR-SALON",
		["ja_kanto"] = "HAIR-SALON",
	},

	["CLEANERS"] = {
		["_default"] = "CLEANERS",
		["ja_kanto"] = "CLEANERS",
	},

	["HARDWARE"] = {
		["_default"] = "HARDWARE",
		["ja_kanto"] = "HARDWARE",
	},

	["Thea's Gym"] = {
		["_default"] = "Thea's Gym",
		["ja_kanto"] = "Thea's Gym",
	},

	["Auto Repair"] = {
		["_default"] = "Auto Repair",
		["ja_kanto"] = "Auto Repair",
	},

	["Tech Store"] = {
		["_default"] = "Tech Store",
		["ja_kanto"] = "Tech Store",
	},

	["Book Store"] = {
		["_default"] = "Book Store",
		["ja_kanto"] = "Book Store",
	},

	["Asian-Buffet"] = {
		["_default"] = "Asian-Buffet",
		["ja_kanto"] = "Asian-Buffet",
	},

	["Bistro"] = {
		["_default"] = "Bistro",
		["ja_kanto"] = "Bistro",
	},

	["Borgirs"] = {
		["_default"] = "Borgirs",
		["ja_kanto"] = "Borgirs",
	},

	["Pizzeria"] = {
		["_default"] = "Pizzeria",
		["ja_kanto"] = "Pizzeria",
	},

	["BUS DEPOT"] = {
		["_default"] = "BUS DEPOT",
		["ja_kanto"] = "BUS DEPOT",
	},

	["School"] = {
		["_default"] = "School",
		["ja_kanto"] = "School",
	},

	["NEWS"] = {
		["_default"] = "NEWS",
		["ja_kanto"] = "NEWS",
	},

	["FIRE STATION"] = {
		["_default"] = "FIRE STATION",
		["ja_kanto"] = "FIRE STATION",
	},

	["HOSPITAL"] = {
		["_default"] = "HOSPITAL",
		["ja_kanto"] = "HOSPITAL",
	},

	["DOCTOR"] = {
		["_default"] = "DOCTOR",
		["ja_kanto"] = "DOCTOR",
	},

	["Courthouse"] = {
		["_default"] = "Courthouse",
		["ja_kanto"] = "Courthouse",
	},

	["POLICE"] = {
		["_default"] = "POLICE",
		["ja_kanto"] = "POLICE",
	},

	["Bank"] = {
		["_default"] = "Bank",
		["ja_kanto"] = "Bank",
	},

	["CN Tower"] = {
		["_default"] = "CN Tower",
		["ja_kanto"] = "CN Tower",
	},

	["Eiffel Tower"] = {
		["_default"] = "Eiffel Tower",
		["ja_kanto"] = "Eiffel Tower",
	},

	["Empire State Building"] = {
		["_default"] = "Empire State Building",
		["ja_kanto"] = "Empire State Building",
	},

	["Ferris Wheel"] = {
		["_default"] = "Ferris Wheel",
		["ja_kanto"] = "Ferris Wheel",
	},

	["Gas Station"] = {
		["_default"] = "Gas Station",
		["ja_kanto"] = "Gas Station",
	},

	["Modern Skyscraper"] = {
		["_default"] = "Modern Skyscraper",
		["ja_kanto"] = "Modern Skyscraper",
	},

	["National Capital"] = {
		["_default"] = "National Capital",
		["ja_kanto"] = "National Capital",
	},

	["Obelisk"] = {
		["_default"] = "Obelisk",
		["ja_kanto"] = "Obelisk",
	},

	["Space Needle"] = {
		["_default"] = "Space Needle",
		["ja_kanto"] = "Space Needle",
	},

	["Statue of Liberty"] = {
		["_default"] = "Statue of Liberty",
		["ja_kanto"] = "Statue of Liberty",
	},

	["Tech Office"] = {
		["_default"] = "Tech Office",
		["ja_kanto"] = "Tech Office",
	},

	["World Trade Center"] = {
		["_default"] = "World Trade Center",
		["ja_kanto"] = "World Trade Center",
	},

	["Church"] = {
		["_default"] = "Church",
		["ja_kanto"] = "Church",
	},

	["Hotel"] = {
		["_default"] = "Hotel",
		["ja_kanto"] = "Hotel",
	},

	["Mosque"] = {
		["_default"] = "Mosque",
		["ja_kanto"] = "Mosque",
	},

	["Movie Theater"] = {
		["_default"] = "Movie Theater",
		["ja_kanto"] = "Movie Theater",
	},

	["Shinto Temple"] = {
		["_default"] = "Shinto Temple",
		["ja_kanto"] = "Shinto Temple",
	},

	["Buddha Statue"] = {
		["_default"] = "Buddha Statue",
		["ja_kanto"] = "Buddha Statue",
	},

	["Hindu Temple"] = {
		["_default"] = "Hindu Temple",
		["ja_kanto"] = "Hindu Temple",
	},

	["Courthouse"] = {
		["_default"] = "Courthouse",
		["ja_kanto"] = "Courthouse",
	},

	["PoliceDept"] = {
		["_default"] = "PoliceDept",
		["ja_kanto"] = "PoliceDept",
	},

	["PolicePrecinct"] = {
		["_default"] = "PolicePrecinct",
		["ja_kanto"] = "PolicePrecinct",
	},

	["PoliceStation"] = {
		["_default"] = "PoliceStation",
		["ja_kanto"] = "PoliceStation",
	},

	["Archery Range"] = {
		["_default"] = "Archery Range",
		["ja_kanto"] = "Archery Range",
	},

	["Basketball Court"] = {
		["_default"] = "Basketball Court",
		["ja_kanto"] = "Basketball Court",
	},

	["Basketball Stadium"] = {
		["_default"] = "Basketball Stadium",
		["ja_kanto"] = "Basketball Stadium",
	},

	["Football Stadium"] = {
		["_default"] = "Football Stadium",
		["ja_kanto"] = "Football Stadium",
	},

	["Golf Course"] = {
		["_default"] = "Golf Course",
		["ja_kanto"] = "Golf Course",
	},

	["Public Pool"] = {
		["_default"] = "Public Pool",
		["ja_kanto"] = "Public Pool",
	},

	["Skate Park"] = {
		["_default"] = "Skate Park",
		["ja_kanto"] = "Skate Park",
	},

	["Soccer Stadium"] = {
		["_default"] = "Soccer Stadium",
		["ja_kanto"] = "Soccer Stadium",
	},

	["Tennis Court"] = {
		["_default"] = "Tennis Court",
		["ja_kanto"] = "Tennis Court",
	},

	["Coal Power Plant"] = {
		["_default"] = "Coal Power Plant",
		["ja_kanto"] = "Coal Power Plant",
	},

	["Gas Power Plant"] = {
		["_default"] = "Gas Power Plant",
		["ja_kanto"] = "Gas Power Plant",
	},

	["Geothermal Power Plant"] = {
		["_default"] = "Geothermal Power Plant",
		["ja_kanto"] = "Geothermal Power Plant",
	},

	["Nuclear Power Plant"] = {
		["_default"] = "Nuclear Power Plant",
		["ja_kanto"] = "Nuclear Power Plant",
	},

	["Solar Panels"] = {
		["_default"] = "Solar Panels",
		["ja_kanto"] = "Solar Panels",
	},

	["Wind Turbine"] = {
		["_default"] = "Wind Turbine",
		["ja_kanto"] = "Wind Turbine",
	},

	["Power Lines"] = {
		["_default"] = "Power Lines",
		["ja_kanto"] = "Power Lines",
	},

	["Water Tower"] = {
		["_default"] = "Water Tower",
		["ja_kanto"] = "Water Tower",
	},

	["Water Plant"] = {
		["_default"] = "Water Plant",
		["ja_kanto"] = "Water Plant",
	},

	["Purification Water Plant"] = {
		["_default"] = "Purification Water Plant",
		["ja_kanto"] = "Purification Water Plant",
	},

	["MolecularWaterPlant"] = {
		["_default"] = "MolecularWaterPlant",
		["ja_kanto"] = "MolecularWaterPlant",
	},

	["Water Pipes"] = {
		["_default"] = "Water Pipes",
		["ja_kanto"] = "Water Pipes",
	},

	["Fire Depth"] = {
		["_default"] = "Fire Depth",
		["ja_kanto"] = "Fire Depth",
	},

	["Normal"] = {
		["_default"] = "Normal",
		["ja_kanto"] = "Normal",
	},

	["High Density"] = {
		["_default"] = "High Density",
		["ja_kanto"] = "High Density",
	},

	["Produced WATER"] = {
		["_default"] = "Produced WATER",
		["ja_kanto"] = "Produced WATER",
	},

	["Used WATER"] = {
		["_default"] = "Used WATER",
		["ja_kanto"] = "Used WATER",
	},

	["Usage WATER"] = {
		["_default"] = "Usage WATER",
		["ja_kanto"] = "Usage WATER",
	},

	["Produced POWER"] = {
		["_default"] = "Produced POWER",
		["ja_kanto"] = "Produced POWER",
	},

	["Used POWER"] = {
		["_default"] = "Used POWER",
		["ja_kanto"] = "Used POWER",
	},

	["Usage POWER"] = {
		["_default"] = "Usage POWER",
		["ja_kanto"] = "Usage POWER",
	},

	["New City"] = {
		["_default"] = "New City",
		["ja_kanto"] = "New City",
	},

	["Every night it’s sirens and shouting. Where are the police?"] = {
		["_default"] = "Every night it’s sirens and shouting. Where are the police?",
		["ja_kanto"] = "Every night it’s sirens and shouting. Where are the police?",
		["ja_kansai"] = "Every night it’s sirens and shouting. Where are the police?",
		["ja_tohoku"] = "Every night it’s sirens and shouting. Where are the police?",
		["ja_kyushu"] = "Every night it’s sirens and shouting. Where are the police?",
		["ja_hokkaido"] = "Every night it’s sirens and shouting. Where are the police?",
		["ja_okinawa"] = "Every night it’s sirens and shouting. Where are the police?",
	},

	["Break-ins everywhere. We need a police station closer than the next city over."] = {
		["_default"] = "Break-ins everywhere. We need a police station closer than the next city over.",
		["ja_kanto"] = "Break-ins everywhere. We need a police station closer than the next city over.",
		["ja_kansai"] = "Break-ins everywhere. We need a police station closer than the next city over.",
		["ja_tohoku"] = "Break-ins everywhere. We need a police station closer than the next city over.",
		["ja_kyushu"] = "Break-ins everywhere. We need a police station closer than the next city over.",
		["ja_hokkaido"] = "Break-ins everywhere. We need a police station closer than the next city over.",
		["ja_okinawa"] = "Break-ins everywhere. We need a police station closer than the next city over.",
	},

	["Feels like crime’s the only thing booming in this neighborhood."] = {
		["_default"] = "Feels like crime’s the only thing booming in this neighborhood.",
		["ja_kanto"] = "Feels like crime’s the only thing booming in this neighborhood.",
		["ja_kansai"] = "Feels like crime’s the only thing booming in this neighborhood.",
		["ja_tohoku"] = "Feels like crime’s the only thing booming in this neighborhood.",
		["ja_kyushu"] = "Feels like crime’s the only thing booming in this neighborhood.",
		["ja_hokkaido"] = "Feels like crime’s the only thing booming in this neighborhood.",
		["ja_okinawa"] = "Feels like crime’s the only thing booming in this neighborhood.",
	},

	["Every shop’s installing bars on the windows. Maybe build a precinct instead?"] = {
		["_default"] = "Every shop’s installing bars on the windows. Maybe build a precinct instead?",
		["ja_kanto"] = "Every shop’s installing bars on the windows. Maybe build a precinct instead?",
		["ja_kansai"] = "Every shop’s installing bars on the windows. Maybe build a precinct instead?",
		["ja_tohoku"] = "Every shop’s installing bars on the windows. Maybe build a precinct instead?",
		["ja_kyushu"] = "Every shop’s installing bars on the windows. Maybe build a precinct instead?",
		["ja_hokkaido"] = "Every shop’s installing bars on the windows. Maybe build a precinct instead?",
		["ja_okinawa"] = "Every shop’s installing bars on the windows. Maybe build a precinct instead?",
	},

	["Someone stole my bike again. At this point I should just rent it to them."] = {
		["_default"] = "Someone stole my bike again. At this point I should just rent it to them.",
		["ja_kanto"] = "Someone stole my bike again. At this point I should just rent it to them.",
		["ja_kansai"] = "Someone stole my bike again. At this point I should just rent it to them.",
		["ja_tohoku"] = "Someone stole my bike again. At this point I should just rent it to them.",
		["ja_kyushu"] = "Someone stole my bike again. At this point I should just rent it to them.",
		["ja_hokkaido"] = "Someone stole my bike again. At this point I should just rent it to them.",
		["ja_okinawa"] = "Someone stole my bike again. At this point I should just rent it to them.",
	},

	["Finally, a police precinct opened nearby. Streets already feel calmer."] = {
		["_default"] = "Finally, a police precinct opened nearby. Streets already feel calmer.",
		["ja_kanto"] = "Finally, a police precinct opened nearby. Streets already feel calmer.",
		["ja_kansai"] = "Finally, a police precinct opened nearby. Streets already feel calmer.",
		["ja_tohoku"] = "Finally, a police precinct opened nearby. Streets already feel calmer.",
		["ja_kyushu"] = "Finally, a police precinct opened nearby. Streets already feel calmer.",
		["ja_hokkaido"] = "Finally, a police precinct opened nearby. Streets already feel calmer.",
		["ja_okinawa"] = "Finally, a police precinct opened nearby. Streets already feel calmer.",
	},

	["Just saw officers patrolling downtown. Feels safer than it’s been in years."] = {
		["_default"] = "Just saw officers patrolling downtown. Feels safer than it’s been in years.",
		["ja_kanto"] = "Just saw officers patrolling downtown. Feels safer than it’s been in years.",
		["ja_kansai"] = "Just saw officers patrolling downtown. Feels safer than it’s been in years.",
		["ja_tohoku"] = "Just saw officers patrolling downtown. Feels safer than it’s been in years.",
		["ja_kyushu"] = "Just saw officers patrolling downtown. Feels safer than it’s been in years.",
		["ja_hokkaido"] = "Just saw officers patrolling downtown. Feels safer than it’s been in years.",
		["ja_okinawa"] = "Just saw officers patrolling downtown. Feels safer than it’s been in years.",
	},

	["Crime dropped fast once the new Police Dept went up. Great work, city!"] = {
		["_default"] = "Crime dropped fast once the new Police Dept went up. Great work, city!",
		["ja_kanto"] = "Crime dropped fast once the new Police Dept went up. Great work, city!",
		["ja_kansai"] = "Crime dropped fast once the new Police Dept went up. Great work, city!",
		["ja_tohoku"] = "Crime dropped fast once the new Police Dept went up. Great work, city!",
		["ja_kyushu"] = "Crime dropped fast once the new Police Dept went up. Great work, city!",
		["ja_hokkaido"] = "Crime dropped fast once the new Police Dept went up. Great work, city!",
		["ja_okinawa"] = "Crime dropped fast once the new Police Dept went up. Great work, city!",
	},

	["Courthouse finally opened! Justice might actually happen now!"] = {
		["_default"] = "Courthouse finally opened! Justice might actually happen now!",
		["ja_kanto"] = "Courthouse finally opened! Justice might actually happen now!",
		["ja_kansai"] = "Courthouse finally opened! Justice might actually happen now!",
		["ja_tohoku"] = "Courthouse finally opened! Justice might actually happen now!",
		["ja_kyushu"] = "Courthouse finally opened! Justice might actually happen now!",
		["ja_hokkaido"] = "Courthouse finally opened! Justice might actually happen now!",
		["ja_okinawa"] = "Courthouse finally opened! Justice might actually happen now!",
	},

	["Seeing blue lights used to mean trouble. Now it means peace of mind."] = {
		["_default"] = "Seeing blue lights used to mean trouble. Now it means peace of mind.",
		["ja_kanto"] = "Seeing blue lights used to mean trouble. Now it means peace of mind.",
		["ja_kansai"] = "Seeing blue lights used to mean trouble. Now it means peace of mind.",
		["ja_tohoku"] = "Seeing blue lights used to mean trouble. Now it means peace of mind.",
		["ja_kyushu"] = "Seeing blue lights used to mean trouble. Now it means peace of mind.",
		["ja_hokkaido"] = "Seeing blue lights used to mean trouble. Now it means peace of mind.",
		["ja_okinawa"] = "Seeing blue lights used to mean trouble. Now it means peace of mind.",
	},

	["Police doing their best, but there’s only so many of them. Fund the department!"] = {
		["_default"] = "Police doing their best, but there’s only so many of them. Fund the department!",
		["ja_kanto"] = "Police doing their best, but there’s only so many of them. Fund the department!",
		["ja_kansai"] = "Police doing their best, but there’s only so many of them. Fund the department!",
		["ja_tohoku"] = "Police doing their best, but there’s only so many of them. Fund the department!",
		["ja_kyushu"] = "Police doing their best, but there’s only so many of them. Fund the department!",
		["ja_hokkaido"] = "Police doing their best, but there’s only so many of them. Fund the department!",
		["ja_okinawa"] = "Police doing their best, but there’s only so many of them. Fund the department!",
	},

	["Response times are slow. Maybe the precinct needs more vehicles."] = {
		["_default"] = "Response times are slow. Maybe the precinct needs more vehicles.",
		["ja_kanto"] = "Response times are slow. Maybe the precinct needs more vehicles.",
		["ja_kansai"] = "Response times are slow. Maybe the precinct needs more vehicles.",
		["ja_tohoku"] = "Response times are slow. Maybe the precinct needs more vehicles.",
		["ja_kyushu"] = "Response times are slow. Maybe the precinct needs more vehicles.",
		["ja_hokkaido"] = "Response times are slow. Maybe the precinct needs more vehicles.",
		["ja_okinawa"] = "Response times are slow. Maybe the precinct needs more vehicles.",
	},

	["Wouldn’t mind a few more patrols in the alley behind my store."] = {
		["_default"] = "Wouldn’t mind a few more patrols in the alley behind my store.",
		["ja_kanto"] = "Wouldn’t mind a few more patrols in the alley behind my store.",
		["ja_kansai"] = "Wouldn’t mind a few more patrols in the alley behind my store.",
		["ja_tohoku"] = "Wouldn’t mind a few more patrols in the alley behind my store.",
		["ja_kyushu"] = "Wouldn’t mind a few more patrols in the alley behind my store.",
		["ja_hokkaido"] = "Wouldn’t mind a few more patrols in the alley behind my store.",
		["ja_okinawa"] = "Wouldn’t mind a few more patrols in the alley behind my store.",
	},

	["The courthouse backlog is wild! Cases from last year still waiting."] = {
		["_default"] = "The courthouse backlog is wild! Cases from last year still waiting.",
		["ja_kanto"] = "The courthouse backlog is wild! Cases from last year still waiting.",
		["ja_kansai"] = "The courthouse backlog is wild! Cases from last year still waiting.",
		["ja_tohoku"] = "The courthouse backlog is wild! Cases from last year still waiting.",
		["ja_kyushu"] = "The courthouse backlog is wild! Cases from last year still waiting.",
		["ja_hokkaido"] = "The courthouse backlog is wild! Cases from last year still waiting.",
		["ja_okinawa"] = "The courthouse backlog is wild! Cases from last year still waiting.",
	},

	["If they had better funding, maybe the cops could stop using scooters."] = {
		["_default"] = "If they had better funding, maybe the cops could stop using scooters.",
		["ja_kanto"] = "If they had better funding, maybe the cops could stop using scooters.",
		["ja_kansai"] = "If they had better funding, maybe the cops could stop using scooters.",
		["ja_tohoku"] = "If they had better funding, maybe the cops could stop using scooters.",
		["ja_kyushu"] = "If they had better funding, maybe the cops could stop using scooters.",
		["ja_hokkaido"] = "If they had better funding, maybe the cops could stop using scooters.",
		["ja_okinawa"] = "If they had better funding, maybe the cops could stop using scooters.",
	},

	["The new precinct’s coffee is apparently better than the café’s."] = {
		["_default"] = "The new precinct’s coffee is apparently better than the café’s.",
		["ja_kanto"] = "The new precinct’s coffee is apparently better than the café’s.",
		["ja_kansai"] = "The new precinct’s coffee is apparently better than the café’s.",
		["ja_tohoku"] = "The new precinct’s coffee is apparently better than the café’s.",
		["ja_kyushu"] = "The new precinct’s coffee is apparently better than the café’s.",
		["ja_hokkaido"] = "The new precinct’s coffee is apparently better than the café’s.",
		["ja_okinawa"] = "The new precinct’s coffee is apparently better than the café’s.",
	},

	["Finally got my wallet back from lost-and-found. Didn’t expect that level of service!"] = {
		["_default"] = "Finally got my wallet back from lost-and-found. Didn’t expect that level of service!",
		["ja_kanto"] = "Finally got my wallet back from lost-and-found. Didn’t expect that level of service!",
		["ja_kansai"] = "Finally got my wallet back from lost-and-found. Didn’t expect that level of service!",
		["ja_tohoku"] = "Finally got my wallet back from lost-and-found. Didn’t expect that level of service!",
		["ja_kyushu"] = "Finally got my wallet back from lost-and-found. Didn’t expect that level of service!",
		["ja_hokkaido"] = "Finally got my wallet back from lost-and-found. Didn’t expect that level of service!",
		["ja_okinawa"] = "Finally got my wallet back from lost-and-found. Didn’t expect that level of service!",
	},

	["Saw an officer petting a stray dog on patrol. City’s really turning around."] = {
		["_default"] = "Saw an officer petting a stray dog on patrol. City’s really turning around.",
		["ja_kanto"] = "Saw an officer petting a stray dog on patrol. City’s really turning around.",
		["ja_kansai"] = "Saw an officer petting a stray dog on patrol. City’s really turning around.",
		["ja_tohoku"] = "Saw an officer petting a stray dog on patrol. City’s really turning around.",
		["ja_kyushu"] = "Saw an officer petting a stray dog on patrol. City’s really turning around.",
		["ja_hokkaido"] = "Saw an officer petting a stray dog on patrol. City’s really turning around.",
		["ja_okinawa"] = "Saw an officer petting a stray dog on patrol. City’s really turning around.",
	},

	["Funny how crime drops when people realize there’s actually a police station now."] = {
		["_default"] = "Funny how crime drops when people realize there’s actually a police station now.",
		["ja_kanto"] = "Funny how crime drops when people realize there’s actually a police station now.",
		["ja_kansai"] = "Funny how crime drops when people realize there’s actually a police station now.",
		["ja_tohoku"] = "Funny how crime drops when people realize there’s actually a police station now.",
		["ja_kyushu"] = "Funny how crime drops when people realize there’s actually a police station now.",
		["ja_hokkaido"] = "Funny how crime drops when people realize there’s actually a police station now.",
		["ja_okinawa"] = "Funny how crime drops when people realize there’s actually a police station now.",
	},

	["A single spark out here and the whole block’s gone. Where are the firefighters?"] = {
		["_default"] = "A single spark out here and the whole block’s gone. Where are the firefighters?",
		["ja_kanto"] = "A single spark out here and the whole block’s gone. Where are the firefighters?",
		["ja_kansai"] = "A single spark out here and the whole block’s gone. Where are the firefighters?",
		["ja_tohoku"] = "A single spark out here and the whole block’s gone. Where are the firefighters?",
		["ja_kyushu"] = "A single spark out here and the whole block’s gone. Where are the firefighters?",
		["ja_hokkaido"] = "A single spark out here and the whole block’s gone. Where are the firefighters?",
		["ja_okinawa"] = "A single spark out here and the whole block’s gone. Where are the firefighters?",
	},

	["My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life."] = {
		["_default"] = "My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life.",
		["ja_kanto"] = "My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life.",
		["ja_kansai"] = "My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life.",
		["ja_tohoku"] = "My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life.",
		["ja_kyushu"] = "My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life.",
		["ja_hokkaido"] = "My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life.",
		["ja_okinawa"] = "My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life.",
	},

	["No fire station for miles...guess we’re all volunteers now."] = {
		["_default"] = "No fire station for miles...guess we’re all volunteers now.",
		["ja_kanto"] = "No fire station for miles...guess we’re all volunteers now.",
		["ja_kansai"] = "No fire station for miles...guess we’re all volunteers now.",
		["ja_tohoku"] = "No fire station for miles...guess we’re all volunteers now.",
		["ja_kyushu"] = "No fire station for miles...guess we’re all volunteers now.",
		["ja_hokkaido"] = "No fire station for miles...guess we’re all volunteers now.",
		["ja_okinawa"] = "No fire station for miles...guess we’re all volunteers now.",
	},

	["Every time I smell smoke, I start packing. We need a fire dept."] = {
		["_default"] = "Every time I smell smoke, I start packing. We need a fire dept.",
		["ja_kanto"] = "Every time I smell smoke, I start packing. We need a fire dept.",
		["ja_kansai"] = "Every time I smell smoke, I start packing. We need a fire dept.",
		["ja_tohoku"] = "Every time I smell smoke, I start packing. We need a fire dept.",
		["ja_kyushu"] = "Every time I smell smoke, I start packing. We need a fire dept.",
		["ja_hokkaido"] = "Every time I smell smoke, I start packing. We need a fire dept.",
		["ja_okinawa"] = "Every time I smell smoke, I start packing. We need a fire dept.",
	},

	["Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames."] = {
		["_default"] = "Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames.",
		["ja_kanto"] = "Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames.",
		["ja_kansai"] = "Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames.",
		["ja_tohoku"] = "Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames.",
		["ja_kyushu"] = "Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames.",
		["ja_hokkaido"] = "Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames.",
		["ja_okinawa"] = "Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames.",
	},

	["The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there."] = {
		["_default"] = "The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there.",
		["ja_kanto"] = "The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there.",
		["ja_kansai"] = "The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there.",
		["ja_tohoku"] = "The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there.",
		["ja_kyushu"] = "The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there.",
		["ja_hokkaido"] = "The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there.",
		["ja_okinawa"] = "The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there.",
	},

	["Heard sirens this morning! Quick response, city’s improving!"] = {
		["_default"] = "Heard sirens this morning! Quick response, city’s improving!",
		["ja_kanto"] = "Heard sirens this morning! Quick response, city’s improving!",
		["ja_kansai"] = "Heard sirens this morning! Quick response, city’s improving!",
		["ja_tohoku"] = "Heard sirens this morning! Quick response, city’s improving!",
		["ja_kyushu"] = "Heard sirens this morning! Quick response, city’s improving!",
		["ja_hokkaido"] = "Heard sirens this morning! Quick response, city’s improving!",
		["ja_okinawa"] = "Heard sirens this morning! Quick response, city’s improving!",
	},

	["Firefighters saved the bakery! Free muffins for heroes."] = {
		["_default"] = "Firefighters saved the bakery! Free muffins for heroes.",
		["ja_kanto"] = "Firefighters saved the bakery! Free muffins for heroes.",
		["ja_kansai"] = "Firefighters saved the bakery! Free muffins for heroes.",
		["ja_tohoku"] = "Firefighters saved the bakery! Free muffins for heroes.",
		["ja_kyushu"] = "Firefighters saved the bakery! Free muffins for heroes.",
		["ja_hokkaido"] = "Firefighters saved the bakery! Free muffins for heroes.",
		["ja_okinawa"] = "Firefighters saved the bakery! Free muffins for heroes.",
	},

	["Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore."] = {
		["_default"] = "Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore.",
		["ja_kanto"] = "Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore.",
		["ja_kansai"] = "Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore.",
		["ja_tohoku"] = "Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore.",
		["ja_kyushu"] = "Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore.",
		["ja_hokkaido"] = "Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore.",
		["ja_okinawa"] = "Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore.",
	},

	["Fire Dept’s underfunded. They’re still driving 20-year-old trucks!"] = {
		["_default"] = "Fire Dept’s underfunded. They’re still driving 20-year-old trucks!",
		["ja_kanto"] = "Fire Dept’s underfunded. They’re still driving 20-year-old trucks!",
		["ja_kansai"] = "Fire Dept’s underfunded. They’re still driving 20-year-old trucks!",
		["ja_tohoku"] = "Fire Dept’s underfunded. They’re still driving 20-year-old trucks!",
		["ja_kyushu"] = "Fire Dept’s underfunded. They’re still driving 20-year-old trucks!",
		["ja_hokkaido"] = "Fire Dept’s underfunded. They’re still driving 20-year-old trucks!",
		["ja_okinawa"] = "Fire Dept’s underfunded. They’re still driving 20-year-old trucks!",
	},

	["More firefighters, less fireworks! Give them proper funding!"] = {
		["_default"] = "More firefighters, less fireworks! Give them proper funding!",
		["ja_kanto"] = "More firefighters, less fireworks! Give them proper funding!",
		["ja_kansai"] = "More firefighters, less fireworks! Give them proper funding!",
		["ja_tohoku"] = "More firefighters, less fireworks! Give them proper funding!",
		["ja_kyushu"] = "More firefighters, less fireworks! Give them proper funding!",
		["ja_hokkaido"] = "More firefighters, less fireworks! Give them proper funding!",
		["ja_okinawa"] = "More firefighters, less fireworks! Give them proper funding!",
	},

	["Response times are slow lately. Maybe they need more stations."] = {
		["_default"] = "Response times are slow lately. Maybe they need more stations.",
		["ja_kanto"] = "Response times are slow lately. Maybe they need more stations.",
		["ja_kansai"] = "Response times are slow lately. Maybe they need more stations.",
		["ja_tohoku"] = "Response times are slow lately. Maybe they need more stations.",
		["ja_kyushu"] = "Response times are slow lately. Maybe they need more stations.",
		["ja_hokkaido"] = "Response times are slow lately. Maybe they need more stations.",
		["ja_okinawa"] = "Response times are slow lately. Maybe they need more stations.",
	},

	["If the Fire Precinct had more funding, maybe insurance wouldn’t be this high."] = {
		["_default"] = "If the Fire Precinct had more funding, maybe insurance wouldn’t be this high.",
		["ja_kanto"] = "If the Fire Precinct had more funding, maybe insurance wouldn’t be this high.",
		["ja_kansai"] = "If the Fire Precinct had more funding, maybe insurance wouldn’t be this high.",
		["ja_tohoku"] = "If the Fire Precinct had more funding, maybe insurance wouldn’t be this high.",
		["ja_kyushu"] = "If the Fire Precinct had more funding, maybe insurance wouldn’t be this high.",
		["ja_hokkaido"] = "If the Fire Precinct had more funding, maybe insurance wouldn’t be this high.",
		["ja_okinawa"] = "If the Fire Precinct had more funding, maybe insurance wouldn’t be this high.",
	},

	["Firefighters are doing their best, but the city’s growing faster than their budget."] = {
		["_default"] = "Firefighters are doing their best, but the city’s growing faster than their budget.",
		["ja_kanto"] = "Firefighters are doing their best, but the city’s growing faster than their budget.",
		["ja_kansai"] = "Firefighters are doing their best, but the city’s growing faster than their budget.",
		["ja_tohoku"] = "Firefighters are doing their best, but the city’s growing faster than their budget.",
		["ja_kyushu"] = "Firefighters are doing their best, but the city’s growing faster than their budget.",
		["ja_hokkaido"] = "Firefighters are doing their best, but the city’s growing faster than their budget.",
		["ja_okinawa"] = "Firefighters are doing their best, but the city’s growing faster than their budget.",
	},

	["Someone left their toast on again. I heard the sirens before the smoke alarm."] = {
		["_default"] = "Someone left their toast on again. I heard the sirens before the smoke alarm.",
		["ja_kanto"] = "Someone left their toast on again. I heard the sirens before the smoke alarm.",
		["ja_kansai"] = "Someone left their toast on again. I heard the sirens before the smoke alarm.",
		["ja_tohoku"] = "Someone left their toast on again. I heard the sirens before the smoke alarm.",
		["ja_kyushu"] = "Someone left their toast on again. I heard the sirens before the smoke alarm.",
		["ja_hokkaido"] = "Someone left their toast on again. I heard the sirens before the smoke alarm.",
		["ja_okinawa"] = "Someone left their toast on again. I heard the sirens before the smoke alarm.",
	},

	["If the Fire Station had a café, I’d stop by just to say thanks."] = {
		["_default"] = "If the Fire Station had a café, I’d stop by just to say thanks.",
		["ja_kanto"] = "If the Fire Station had a café, I’d stop by just to say thanks.",
		["ja_kansai"] = "If the Fire Station had a café, I’d stop by just to say thanks.",
		["ja_tohoku"] = "If the Fire Station had a café, I’d stop by just to say thanks.",
		["ja_kyushu"] = "If the Fire Station had a café, I’d stop by just to say thanks.",
		["ja_hokkaido"] = "If the Fire Station had a café, I’d stop by just to say thanks.",
		["ja_okinawa"] = "If the Fire Station had a café, I’d stop by just to say thanks.",
	},

	["Shoutout to the Fire Dept! They’re faster than my internet."] = {
		["_default"] = "Shoutout to the Fire Dept! They’re faster than my internet.",
		["ja_kanto"] = "Shoutout to the Fire Dept! They’re faster than my internet.",
		["ja_kansai"] = "Shoutout to the Fire Dept! They’re faster than my internet.",
		["ja_tohoku"] = "Shoutout to the Fire Dept! They’re faster than my internet.",
		["ja_kyushu"] = "Shoutout to the Fire Dept! They’re faster than my internet.",
		["ja_hokkaido"] = "Shoutout to the Fire Dept! They’re faster than my internet.",
		["ja_okinawa"] = "Shoutout to the Fire Dept! They’re faster than my internet.",
	},

	["Got sick again and there’s still no clinic in this district."] = {
		["_default"] = "Got sick again and there’s still no clinic in this district.",
		["ja_kanto"] = "Got sick again and there’s still no clinic in this district.",
		["ja_kansai"] = "Got sick again and there’s still no clinic in this district.",
		["ja_tohoku"] = "Got sick again and there’s still no clinic in this district.",
		["ja_kyushu"] = "Got sick again and there’s still no clinic in this district.",
		["ja_hokkaido"] = "Got sick again and there’s still no clinic in this district.",
		["ja_okinawa"] = "Got sick again and there’s still no clinic in this district.",
	},

	["The nearest hospital is two bus rides away. Hope I survive the trip."] = {
		["_default"] = "The nearest hospital is two bus rides away. Hope I survive the trip.",
		["ja_kanto"] = "The nearest hospital is two bus rides away. Hope I survive the trip.",
		["ja_kansai"] = "The nearest hospital is two bus rides away. Hope I survive the trip.",
		["ja_tohoku"] = "The nearest hospital is two bus rides away. Hope I survive the trip.",
		["ja_kyushu"] = "The nearest hospital is two bus rides away. Hope I survive the trip.",
		["ja_hokkaido"] = "The nearest hospital is two bus rides away. Hope I survive the trip.",
		["ja_okinawa"] = "The nearest hospital is two bus rides away. Hope I survive the trip.",
	},

	["Can’t even get an appointment. We need more doctors, not more paperwork."] = {
		["_default"] = "Can’t even get an appointment. We need more doctors, not more paperwork.",
		["ja_kanto"] = "Can’t even get an appointment. We need more doctors, not more paperwork.",
		["ja_kansai"] = "Can’t even get an appointment. We need more doctors, not more paperwork.",
		["ja_tohoku"] = "Can’t even get an appointment. We need more doctors, not more paperwork.",
		["ja_kyushu"] = "Can’t even get an appointment. We need more doctors, not more paperwork.",
		["ja_hokkaido"] = "Can’t even get an appointment. We need more doctors, not more paperwork.",
		["ja_okinawa"] = "Can’t even get an appointment. We need more doctors, not more paperwork.",
	},

	["Small Clinic is closed again. Guess I’ll just tough it out."] = {
		["_default"] = "Small Clinic is closed again. Guess I’ll just tough it out.",
		["ja_kanto"] = "Small Clinic is closed again. Guess I’ll just tough it out.",
		["ja_kansai"] = "Small Clinic is closed again. Guess I’ll just tough it out.",
		["ja_tohoku"] = "Small Clinic is closed again. Guess I’ll just tough it out.",
		["ja_kyushu"] = "Small Clinic is closed again. Guess I’ll just tough it out.",
		["ja_hokkaido"] = "Small Clinic is closed again. Guess I’ll just tough it out.",
		["ja_okinawa"] = "Small Clinic is closed again. Guess I’ll just tough it out.",
	},

	["No emergency care nearby. If you get hurt here, good luck."] = {
		["_default"] = "No emergency care nearby. If you get hurt here, good luck.",
		["ja_kanto"] = "No emergency care nearby. If you get hurt here, good luck.",
		["ja_kansai"] = "No emergency care nearby. If you get hurt here, good luck.",
		["ja_tohoku"] = "No emergency care nearby. If you get hurt here, good luck.",
		["ja_kyushu"] = "No emergency care nearby. If you get hurt here, good luck.",
		["ja_hokkaido"] = "No emergency care nearby. If you get hurt here, good luck.",
		["ja_okinawa"] = "No emergency care nearby. If you get hurt here, good luck.",
	},

	["The new City Hospital looks amazing! Finally, real healthcare in town."] = {
		["_default"] = "The new City Hospital looks amazing! Finally, real healthcare in town.",
		["ja_kanto"] = "The new City Hospital looks amazing! Finally, real healthcare in town.",
		["ja_kansai"] = "The new City Hospital looks amazing! Finally, real healthcare in town.",
		["ja_tohoku"] = "The new City Hospital looks amazing! Finally, real healthcare in town.",
		["ja_kyushu"] = "The new City Hospital looks amazing! Finally, real healthcare in town.",
		["ja_hokkaido"] = "The new City Hospital looks amazing! Finally, real healthcare in town.",
		["ja_okinawa"] = "The new City Hospital looks amazing! Finally, real healthcare in town.",
	},

	["Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup."] = {
		["_default"] = "Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup.",
		["ja_kanto"] = "Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup.",
		["ja_kansai"] = "Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup.",
		["ja_tohoku"] = "Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup.",
		["ja_kyushu"] = "Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup.",
		["ja_hokkaido"] = "Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup.",
		["ja_okinawa"] = "Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup.",
	},

	["Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!"] = {
		["_default"] = "Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!",
		["ja_kanto"] = "Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!",
		["ja_kansai"] = "Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!",
		["ja_tohoku"] = "Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!",
		["ja_kyushu"] = "Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!",
		["ja_hokkaido"] = "Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!",
		["ja_okinawa"] = "Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!",
	},

	["The Major Hospital opened and it’s already saving lives. Great job, city!"] = {
		["_default"] = "The Major Hospital opened and it’s already saving lives. Great job, city!",
		["ja_kanto"] = "The Major Hospital opened and it’s already saving lives. Great job, city!",
		["ja_kansai"] = "The Major Hospital opened and it’s already saving lives. Great job, city!",
		["ja_tohoku"] = "The Major Hospital opened and it’s already saving lives. Great job, city!",
		["ja_kyushu"] = "The Major Hospital opened and it’s already saving lives. Great job, city!",
		["ja_hokkaido"] = "The Major Hospital opened and it’s already saving lives. Great job, city!",
		["ja_okinawa"] = "The Major Hospital opened and it’s already saving lives. Great job, city!",
	},

	["Feeling safer just knowing there’s a functioning hospital nearby."] = {
		["_default"] = "Feeling safer just knowing there’s a functioning hospital nearby.",
		["ja_kanto"] = "Feeling safer just knowing there’s a functioning hospital nearby.",
		["ja_kansai"] = "Feeling safer just knowing there’s a functioning hospital nearby.",
		["ja_tohoku"] = "Feeling safer just knowing there’s a functioning hospital nearby.",
		["ja_kyushu"] = "Feeling safer just knowing there’s a functioning hospital nearby.",
		["ja_hokkaido"] = "Feeling safer just knowing there’s a functioning hospital nearby.",
		["ja_okinawa"] = "Feeling safer just knowing there’s a functioning hospital nearby.",
	},

	["Doctors are overworked and patients keep piling in! Build another hospital!"] = {
		["_default"] = "Doctors are overworked and patients keep piling in! Build another hospital!",
		["ja_kanto"] = "Doctors are overworked and patients keep piling in! Build another hospital!",
		["ja_kansai"] = "Doctors are overworked and patients keep piling in! Build another hospital!",
		["ja_tohoku"] = "Doctors are overworked and patients keep piling in! Build another hospital!",
		["ja_kyushu"] = "Doctors are overworked and patients keep piling in! Build another hospital!",
		["ja_hokkaido"] = "Doctors are overworked and patients keep piling in! Build another hospital!",
		["ja_okinawa"] = "Doctors are overworked and patients keep piling in! Build another hospital!",
	},

	["Clinic’s great, but they could use more nurses. Everyone’s exhausted."] = {
		["_default"] = "Clinic’s great, but they could use more nurses. Everyone’s exhausted.",
		["ja_kanto"] = "Clinic’s great, but they could use more nurses. Everyone’s exhausted.",
		["ja_kansai"] = "Clinic’s great, but they could use more nurses. Everyone’s exhausted.",
		["ja_tohoku"] = "Clinic’s great, but they could use more nurses. Everyone’s exhausted.",
		["ja_kyushu"] = "Clinic’s great, but they could use more nurses. Everyone’s exhausted.",
		["ja_hokkaido"] = "Clinic’s great, but they could use more nurses. Everyone’s exhausted.",
		["ja_okinawa"] = "Clinic’s great, but they could use more nurses. Everyone’s exhausted.",
	},

	["The ER waiting room looks like a concert lineup. Fund the health system already!"] = {
		["_default"] = "The ER waiting room looks like a concert lineup. Fund the health system already!",
		["ja_kanto"] = "The ER waiting room looks like a concert lineup. Fund the health system already!",
		["ja_kansai"] = "The ER waiting room looks like a concert lineup. Fund the health system already!",
		["ja_tohoku"] = "The ER waiting room looks like a concert lineup. Fund the health system already!",
		["ja_kyushu"] = "The ER waiting room looks like a concert lineup. Fund the health system already!",
		["ja_hokkaido"] = "The ER waiting room looks like a concert lineup. Fund the health system already!",
		["ja_okinawa"] = "The ER waiting room looks like a concert lineup. Fund the health system already!",
	},

	["Healthcare’s stretched too thin! Patients in hallways again."] = {
		["_default"] = "Healthcare’s stretched too thin! Patients in hallways again.",
		["ja_kanto"] = "Healthcare’s stretched too thin! Patients in hallways again.",
		["ja_kansai"] = "Healthcare’s stretched too thin! Patients in hallways again.",
		["ja_tohoku"] = "Healthcare’s stretched too thin! Patients in hallways again.",
		["ja_kyushu"] = "Healthcare’s stretched too thin! Patients in hallways again.",
		["ja_hokkaido"] = "Healthcare’s stretched too thin! Patients in hallways again.",
		["ja_okinawa"] = "Healthcare’s stretched too thin! Patients in hallways again.",
	},

	["If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits."] = {
		["_default"] = "If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits.",
		["ja_kanto"] = "If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits.",
		["ja_kansai"] = "If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits.",
		["ja_tohoku"] = "If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits.",
		["ja_kyushu"] = "If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits.",
		["ja_hokkaido"] = "If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits.",
		["ja_okinawa"] = "If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits.",
	},

	["Big thanks to the clinic nurse who still smiles after twelve-hour shifts."] = {
		["_default"] = "Big thanks to the clinic nurse who still smiles after twelve-hour shifts.",
		["ja_kanto"] = "Big thanks to the clinic nurse who still smiles after twelve-hour shifts.",
		["ja_kansai"] = "Big thanks to the clinic nurse who still smiles after twelve-hour shifts.",
		["ja_tohoku"] = "Big thanks to the clinic nurse who still smiles after twelve-hour shifts.",
		["ja_kyushu"] = "Big thanks to the clinic nurse who still smiles after twelve-hour shifts.",
		["ja_hokkaido"] = "Big thanks to the clinic nurse who still smiles after twelve-hour shifts.",
		["ja_okinawa"] = "Big thanks to the clinic nurse who still smiles after twelve-hour shifts.",
	},

	["Someone coughed on the bus and ten people panicked. We really need better hospitals."] = {
		["_default"] = "Someone coughed on the bus and ten people panicked. We really need better hospitals.",
		["ja_kanto"] = "Someone coughed on the bus and ten people panicked. We really need better hospitals.",
		["ja_kansai"] = "Someone coughed on the bus and ten people panicked. We really need better hospitals.",
		["ja_tohoku"] = "Someone coughed on the bus and ten people panicked. We really need better hospitals.",
		["ja_kyushu"] = "Someone coughed on the bus and ten people panicked. We really need better hospitals.",
		["ja_hokkaido"] = "Someone coughed on the bus and ten people panicked. We really need better hospitals.",
		["ja_okinawa"] = "Someone coughed on the bus and ten people panicked. We really need better hospitals.",
	},

	["They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?"] = {
		["_default"] = "They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?",
		["ja_kanto"] = "They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?",
		["ja_kansai"] = "They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?",
		["ja_tohoku"] = "They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?",
		["ja_kyushu"] = "They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?",
		["ja_hokkaido"] = "They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?",
		["ja_okinawa"] = "They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?",
	},

	["My kid said the clinic lollipops taste like medicine. Honestly, same."] = {
		["_default"] = "My kid said the clinic lollipops taste like medicine. Honestly, same.",
		["ja_kanto"] = "My kid said the clinic lollipops taste like medicine. Honestly, same.",
		["ja_kansai"] = "My kid said the clinic lollipops taste like medicine. Honestly, same.",
		["ja_tohoku"] = "My kid said the clinic lollipops taste like medicine. Honestly, same.",
		["ja_kyushu"] = "My kid said the clinic lollipops taste like medicine. Honestly, same.",
		["ja_hokkaido"] = "My kid said the clinic lollipops taste like medicine. Honestly, same.",
		["ja_okinawa"] = "My kid said the clinic lollipops taste like medicine. Honestly, same.",
	},

	["Doctors and firefighters should get statues before politicians do."] = {
		["_default"] = "Doctors and firefighters should get statues before politicians do.",
		["ja_kanto"] = "Doctors and firefighters should get statues before politicians do.",
		["ja_kansai"] = "Doctors and firefighters should get statues before politicians do.",
		["ja_tohoku"] = "Doctors and firefighters should get statues before politicians do.",
		["ja_kyushu"] = "Doctors and firefighters should get statues before politicians do.",
		["ja_hokkaido"] = "Doctors and firefighters should get statues before politicians do.",
		["ja_okinawa"] = "Doctors and firefighters should get statues before politicians do.",
	},

	["Our kids deserve real classrooms, not overflow in hallways. Build more schools!"] = {
		["_default"] = "Our kids deserve real classrooms, not overflow in hallways. Build more schools!",
		["ja_kanto"] = "Our kids deserve real classrooms, not overflow in hallways. Build more schools!",
		["ja_kansai"] = "Our kids deserve real classrooms, not overflow in hallways. Build more schools!",
		["ja_tohoku"] = "Our kids deserve real classrooms, not overflow in hallways. Build more schools!",
		["ja_kyushu"] = "Our kids deserve real classrooms, not overflow in hallways. Build more schools!",
		["ja_hokkaido"] = "Our kids deserve real classrooms, not overflow in hallways. Build more schools!",
		["ja_okinawa"] = "Our kids deserve real classrooms, not overflow in hallways. Build more schools!",
	},

	["Buses are shipping students across town again. We need a local school now."] = {
		["_default"] = "Buses are shipping students across town again. We need a local school now.",
		["ja_kanto"] = "Buses are shipping students across town again. We need a local school now.",
		["ja_kansai"] = "Buses are shipping students across town again. We need a local school now.",
		["ja_tohoku"] = "Buses are shipping students across town again. We need a local school now.",
		["ja_kyushu"] = "Buses are shipping students across town again. We need a local school now.",
		["ja_hokkaido"] = "Buses are shipping students across town again. We need a local school now.",
		["ja_okinawa"] = "Buses are shipping students across town again. We need a local school now.",
	},

	["Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?"] = {
		["_default"] = "Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?",
		["ja_kanto"] = "Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?",
		["ja_kansai"] = "Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?",
		["ja_tohoku"] = "Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?",
		["ja_kyushu"] = "Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?",
		["ja_hokkaido"] = "Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?",
		["ja_okinawa"] = "Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?",
	},

	["Smaller class sizes would fix half our problems. Build one more school, please."] = {
		["_default"] = "Smaller class sizes would fix half our problems. Build one more school, please.",
		["ja_kanto"] = "Smaller class sizes would fix half our problems. Build one more school, please.",
		["ja_kansai"] = "Smaller class sizes would fix half our problems. Build one more school, please.",
		["ja_tohoku"] = "Smaller class sizes would fix half our problems. Build one more school, please.",
		["ja_kyushu"] = "Smaller class sizes would fix half our problems. Build one more school, please.",
		["ja_hokkaido"] = "Smaller class sizes would fix half our problems. Build one more school, please.",
		["ja_okinawa"] = "Smaller class sizes would fix half our problems. Build one more school, please.",
	},

	["Proud day for the city! Our kids finally have places to learn close to home."] = {
		["_default"] = "Proud day for the city! Our kids finally have places to learn close to home.",
		["ja_kanto"] = "Proud day for the city! Our kids finally have places to learn close to home.",
		["ja_kansai"] = "Proud day for the city! Our kids finally have places to learn close to home.",
		["ja_tohoku"] = "Proud day for the city! Our kids finally have places to learn close to home.",
		["ja_kyushu"] = "Proud day for the city! Our kids finally have places to learn close to home.",
		["ja_hokkaido"] = "Proud day for the city! Our kids finally have places to learn close to home.",
		["ja_okinawa"] = "Proud day for the city! Our kids finally have places to learn close to home.",
	},

	["The new Middle School looks amazing! Our kids won’t have to commute forever anymore."] = {
		["_default"] = "The new Middle School looks amazing! Our kids won’t have to commute forever anymore.",
		["ja_kanto"] = "The new Middle School looks amazing! Our kids won’t have to commute forever anymore.",
		["ja_kansai"] = "The new Middle School looks amazing! Our kids won’t have to commute forever anymore.",
		["ja_tohoku"] = "The new Middle School looks amazing! Our kids won’t have to commute forever anymore.",
		["ja_kyushu"] = "The new Middle School looks amazing! Our kids won’t have to commute forever anymore.",
		["ja_hokkaido"] = "The new Middle School looks amazing! Our kids won’t have to commute forever anymore.",
		["ja_okinawa"] = "The new Middle School looks amazing! Our kids won’t have to commute forever anymore.",
	},

	["Middle School is packed already. Guess we should’ve built two."] = {
		["_default"] = "Middle School is packed already. Guess we should’ve built two.",
		["ja_kanto"] = "Middle School is packed already. Guess we should’ve built two.",
		["ja_kansai"] = "Middle School is packed already. Guess we should’ve built two.",
		["ja_tohoku"] = "Middle School is packed already. Guess we should’ve built two.",
		["ja_kyushu"] = "Middle School is packed already. Guess we should’ve built two.",
		["ja_hokkaido"] = "Middle School is packed already. Guess we should’ve built two.",
		["ja_okinawa"] = "Middle School is packed already. Guess we should’ve built two.",
	},

	["Clubs, sports, and science fairs? Middle School is finally a real hub for families."] = {
		["_default"] = "Clubs, sports, and science fairs? Middle School is finally a real hub for families.",
		["ja_kanto"] = "Clubs, sports, and science fairs? Middle School is finally a real hub for families.",
		["ja_kansai"] = "Clubs, sports, and science fairs? Middle School is finally a real hub for families.",
		["ja_tohoku"] = "Clubs, sports, and science fairs? Middle School is finally a real hub for families.",
		["ja_kyushu"] = "Clubs, sports, and science fairs? Middle School is finally a real hub for families.",
		["ja_hokkaido"] = "Clubs, sports, and science fairs? Middle School is finally a real hub for families.",
		["ja_okinawa"] = "Clubs, sports, and science fairs? Middle School is finally a real hub for families.",
	},

	["Heard the Middle School library got new computers. That’s how you build futures."] = {
		["_default"] = "Heard the Middle School library got new computers. That’s how you build futures.",
		["ja_kanto"] = "Heard the Middle School library got new computers. That’s how you build futures.",
		["ja_kansai"] = "Heard the Middle School library got new computers. That’s how you build futures.",
		["ja_tohoku"] = "Heard the Middle School library got new computers. That’s how you build futures.",
		["ja_kyushu"] = "Heard the Middle School library got new computers. That’s how you build futures.",
		["ja_hokkaido"] = "Heard the Middle School library got new computers. That’s how you build futures.",
		["ja_okinawa"] = "Heard the Middle School library got new computers. That’s how you build futures.",
	},

	["Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!"] = {
		["_default"] = "Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!",
		["ja_kanto"] = "Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!",
		["ja_kansai"] = "Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!",
		["ja_tohoku"] = "Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!",
		["ja_kyushu"] = "Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!",
		["ja_hokkaido"] = "Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!",
		["ja_okinawa"] = "Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!",
	},

	["Private School opened its doors and suddenly uniforms are in fashion."] = {
		["_default"] = "Private School opened its doors and suddenly uniforms are in fashion.",
		["ja_kanto"] = "Private School opened its doors and suddenly uniforms are in fashion.",
		["ja_kansai"] = "Private School opened its doors and suddenly uniforms are in fashion.",
		["ja_tohoku"] = "Private School opened its doors and suddenly uniforms are in fashion.",
		["ja_kyushu"] = "Private School opened its doors and suddenly uniforms are in fashion.",
		["ja_hokkaido"] = "Private School opened its doors and suddenly uniforms are in fashion.",
		["ja_okinawa"] = "Private School opened its doors and suddenly uniforms are in fashion.",
	},

	["Private School scholarships would go a long way! Talent shouldn’t depend on wallets."] = {
		["_default"] = "Private School scholarships would go a long way! Talent shouldn’t depend on wallets.",
		["ja_kanto"] = "Private School scholarships would go a long way! Talent shouldn’t depend on wallets.",
		["ja_kansai"] = "Private School scholarships would go a long way! Talent shouldn’t depend on wallets.",
		["ja_tohoku"] = "Private School scholarships would go a long way! Talent shouldn’t depend on wallets.",
		["ja_kyushu"] = "Private School scholarships would go a long way! Talent shouldn’t depend on wallets.",
		["ja_hokkaido"] = "Private School scholarships would go a long way! Talent shouldn’t depend on wallets.",
		["ja_okinawa"] = "Private School scholarships would go a long way! Talent shouldn’t depend on wallets.",
	},

	["Heard Private School has small classes and serious teachers. Sounds like results incoming."] = {
		["_default"] = "Heard Private School has small classes and serious teachers. Sounds like results incoming.",
		["ja_kanto"] = "Heard Private School has small classes and serious teachers. Sounds like results incoming.",
		["ja_kansai"] = "Heard Private School has small classes and serious teachers. Sounds like results incoming.",
		["ja_tohoku"] = "Heard Private School has small classes and serious teachers. Sounds like results incoming.",
		["ja_kyushu"] = "Heard Private School has small classes and serious teachers. Sounds like results incoming.",
		["ja_hokkaido"] = "Heard Private School has small classes and serious teachers. Sounds like results incoming.",
		["ja_okinawa"] = "Heard Private School has small classes and serious teachers. Sounds like results incoming.",
	},

	["Not my budget, but I’m glad Private School takes pressure off the public system."] = {
		["_default"] = "Not my budget, but I’m glad Private School takes pressure off the public system.",
		["ja_kanto"] = "Not my budget, but I’m glad Private School takes pressure off the public system.",
		["ja_kansai"] = "Not my budget, but I’m glad Private School takes pressure off the public system.",
		["ja_tohoku"] = "Not my budget, but I’m glad Private School takes pressure off the public system.",
		["ja_kyushu"] = "Not my budget, but I’m glad Private School takes pressure off the public system.",
		["ja_hokkaido"] = "Not my budget, but I’m glad Private School takes pressure off the public system.",
		["ja_okinawa"] = "Not my budget, but I’m glad Private School takes pressure off the public system.",
	},

	["Private School debate team is sweeping tournaments. City pride, fancy blazers edition."] = {
		["_default"] = "Private School debate team is sweeping tournaments. City pride, fancy blazers edition.",
		["ja_kanto"] = "Private School debate team is sweeping tournaments. City pride, fancy blazers edition.",
		["ja_kansai"] = "Private School debate team is sweeping tournaments. City pride, fancy blazers edition.",
		["ja_tohoku"] = "Private School debate team is sweeping tournaments. City pride, fancy blazers edition.",
		["ja_kyushu"] = "Private School debate team is sweeping tournaments. City pride, fancy blazers edition.",
		["ja_hokkaido"] = "Private School debate team is sweeping tournaments. City pride, fancy blazers edition.",
		["ja_okinawa"] = "Private School debate team is sweeping tournaments. City pride, fancy blazers edition.",
	},

	["Museum’s finally open! Weekend plans solved!"] = {
		["_default"] = "Museum’s finally open! Weekend plans solved!",
		["ja_kanto"] = "Museum’s finally open! Weekend plans solved!",
		["ja_kansai"] = "Museum’s finally open! Weekend plans solved!",
		["ja_tohoku"] = "Museum’s finally open! Weekend plans solved!",
		["ja_kyushu"] = "Museum’s finally open! Weekend plans solved!",
		["ja_hokkaido"] = "Museum’s finally open! Weekend plans solved!",
		["ja_okinawa"] = "Museum’s finally open! Weekend plans solved!",
	},

	["Field trips to the Museum beat worksheets every time. Thank you, city!"] = {
		["_default"] = "Field trips to the Museum beat worksheets every time. Thank you, city!",
		["ja_kanto"] = "Field trips to the Museum beat worksheets every time. Thank you, city!",
		["ja_kansai"] = "Field trips to the Museum beat worksheets every time. Thank you, city!",
		["ja_tohoku"] = "Field trips to the Museum beat worksheets every time. Thank you, city!",
		["ja_kyushu"] = "Field trips to the Museum beat worksheets every time. Thank you, city!",
		["ja_hokkaido"] = "Field trips to the Museum beat worksheets every time. Thank you, city!",
		["ja_okinawa"] = "Field trips to the Museum beat worksheets every time. Thank you, city!",
	},

	["Rotating exhibits at the Museum keep downtown lively and local businesses busy."] = {
		["_default"] = "Rotating exhibits at the Museum keep downtown lively and local businesses busy.",
		["ja_kanto"] = "Rotating exhibits at the Museum keep downtown lively and local businesses busy.",
		["ja_kansai"] = "Rotating exhibits at the Museum keep downtown lively and local businesses busy.",
		["ja_tohoku"] = "Rotating exhibits at the Museum keep downtown lively and local businesses busy.",
		["ja_kyushu"] = "Rotating exhibits at the Museum keep downtown lively and local businesses busy.",
		["ja_hokkaido"] = "Rotating exhibits at the Museum keep downtown lively and local businesses busy.",
		["ja_okinawa"] = "Rotating exhibits at the Museum keep downtown lively and local businesses busy.",
	},

	["More late-night hours at the Museum, please some of us work days!"] = {
		["_default"] = "More late-night hours at the Museum, please some of us work days!",
		["ja_kanto"] = "More late-night hours at the Museum, please some of us work days!",
		["ja_kansai"] = "More late-night hours at the Museum, please some of us work days!",
		["ja_tohoku"] = "More late-night hours at the Museum, please some of us work days!",
		["ja_kyushu"] = "More late-night hours at the Museum, please some of us work days!",
		["ja_hokkaido"] = "More late-night hours at the Museum, please some of us work days!",
		["ja_okinawa"] = "More late-night hours at the Museum, please some of us work days!",
	},

	["The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win."] = {
		["_default"] = "The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win.",
		["ja_kanto"] = "The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win.",
		["ja_kansai"] = "The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win.",
		["ja_tohoku"] = "The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win.",
		["ja_kyushu"] = "The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win.",
		["ja_hokkaido"] = "The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win.",
		["ja_okinawa"] = "The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win.",
	},

	["Local News Station is live finally! City updates that aren’t rumors."] = {
		["_default"] = "Local News Station is live finally! City updates that aren’t rumors.",
		["ja_kanto"] = "Local News Station is live finally! City updates that aren’t rumors.",
		["ja_kansai"] = "Local News Station is live finally! City updates that aren’t rumors.",
		["ja_tohoku"] = "Local News Station is live finally! City updates that aren’t rumors.",
		["ja_kyushu"] = "Local News Station is live finally! City updates that aren’t rumors.",
		["ja_hokkaido"] = "Local News Station is live finally! City updates that aren’t rumors.",
		["ja_okinawa"] = "Local News Station is live finally! City updates that aren’t rumors.",
	},

	["News Station covering school board meetings means less drama, more facts. Love it."] = {
		["_default"] = "News Station covering school board meetings means less drama, more facts. Love it.",
		["ja_kanto"] = "News Station covering school board meetings means less drama, more facts. Love it.",
		["ja_kansai"] = "News Station covering school board meetings means less drama, more facts. Love it.",
		["ja_tohoku"] = "News Station covering school board meetings means less drama, more facts. Love it.",
		["ja_kyushu"] = "News Station covering school board meetings means less drama, more facts. Love it.",
		["ja_hokkaido"] = "News Station covering school board meetings means less drama, more facts. Love it.",
		["ja_okinawa"] = "News Station covering school board meetings means less drama, more facts. Love it.",
	},

	["Traffic and weather from the News Station actually saved me time today. Journalism works!"] = {
		["_default"] = "Traffic and weather from the News Station actually saved me time today. Journalism works!",
		["ja_kanto"] = "Traffic and weather from the News Station actually saved me time today. Journalism works!",
		["ja_kansai"] = "Traffic and weather from the News Station actually saved me time today. Journalism works!",
		["ja_tohoku"] = "Traffic and weather from the News Station actually saved me time today. Journalism works!",
		["ja_kyushu"] = "Traffic and weather from the News Station actually saved me time today. Journalism works!",
		["ja_hokkaido"] = "Traffic and weather from the News Station actually saved me time today. Journalism works!",
		["ja_okinawa"] = "Traffic and weather from the News Station actually saved me time today. Journalism works!",
	},

	["If the News Station keeps highlighting achievements, more families will move here. Smart play, city."] = {
		["_default"] = "If the News Station keeps highlighting achievements, more families will move here. Smart play, city.",
		["ja_kanto"] = "If the News Station keeps highlighting achievements, more families will move here. Smart play, city.",
		["ja_kansai"] = "If the News Station keeps highlighting achievements, more families will move here. Smart play, city.",
		["ja_tohoku"] = "If the News Station keeps highlighting achievements, more families will move here. Smart play, city.",
		["ja_kyushu"] = "If the News Station keeps highlighting achievements, more families will move here. Smart play, city.",
		["ja_hokkaido"] = "If the News Station keeps highlighting achievements, more families will move here. Smart play, city.",
		["ja_okinawa"] = "If the News Station keeps highlighting achievements, more families will move here. Smart play, city.",
	},

	["Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed."] = {
		["_default"] = "Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed.",
		["ja_kanto"] = "Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed.",
		["ja_kansai"] = "Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed.",
		["ja_tohoku"] = "Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed.",
		["ja_kyushu"] = "Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed.",
		["ja_hokkaido"] = "Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed.",
		["ja_okinawa"] = "Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed.",
	},

	["This city needs more places to unwind before we all burn out."] = {
		["_default"] = "This city needs more places to unwind before we all burn out.",
		["ja_kanto"] = "This city needs more places to unwind before we all burn out.",
		["ja_kansai"] = "This city needs more places to unwind before we all burn out.",
		["ja_tohoku"] = "This city needs more places to unwind before we all burn out.",
		["ja_kyushu"] = "This city needs more places to unwind before we all burn out.",
		["ja_hokkaido"] = "This city needs more places to unwind before we all burn out.",
		["ja_okinawa"] = "This city needs more places to unwind before we all burn out.",
	},

	["Weekends feel better when there’s somewhere calm to go and clear your head."] = {
		["_default"] = "Weekends feel better when there’s somewhere calm to go and clear your head.",
		["ja_kanto"] = "Weekends feel better when there’s somewhere calm to go and clear your head.",
		["ja_kansai"] = "Weekends feel better when there’s somewhere calm to go and clear your head.",
		["ja_tohoku"] = "Weekends feel better when there’s somewhere calm to go and clear your head.",
		["ja_kyushu"] = "Weekends feel better when there’s somewhere calm to go and clear your head.",
		["ja_hokkaido"] = "Weekends feel better when there’s somewhere calm to go and clear your head.",
		["ja_okinawa"] = "Weekends feel better when there’s somewhere calm to go and clear your head.",
	},

	["Public spaces pay for themselves in community spirit. Build more, argue less."] = {
		["_default"] = "Public spaces pay for themselves in community spirit. Build more, argue less.",
		["ja_kanto"] = "Public spaces pay for themselves in community spirit. Build more, argue less.",
		["ja_kansai"] = "Public spaces pay for themselves in community spirit. Build more, argue less.",
		["ja_tohoku"] = "Public spaces pay for themselves in community spirit. Build more, argue less.",
		["ja_kyushu"] = "Public spaces pay for themselves in community spirit. Build more, argue less.",
		["ja_hokkaido"] = "Public spaces pay for themselves in community spirit. Build more, argue less.",
		["ja_okinawa"] = "Public spaces pay for themselves in community spirit. Build more, argue less.",
	},

	["Hotel just opened downtown! Tourists incoming and local shops smiling already."] = {
		["_default"] = "Hotel just opened downtown! Tourists incoming and local shops smiling already.",
		["ja_kanto"] = "Hotel just opened downtown! Tourists incoming and local shops smiling already.",
		["ja_kansai"] = "Hotel just opened downtown! Tourists incoming and local shops smiling already.",
		["ja_tohoku"] = "Hotel just opened downtown! Tourists incoming and local shops smiling already.",
		["ja_kyushu"] = "Hotel just opened downtown! Tourists incoming and local shops smiling already.",
		["ja_hokkaido"] = "Hotel just opened downtown! Tourists incoming and local shops smiling already.",
		["ja_okinawa"] = "Hotel just opened downtown! Tourists incoming and local shops smiling already.",
	},

	["Conference space at the Hotel means real business travel now! Good for the whole city."] = {
		["_default"] = "Conference space at the Hotel means real business travel now! Good for the whole city.",
		["ja_kanto"] = "Conference space at the Hotel means real business travel now! Good for the whole city.",
		["ja_kansai"] = "Conference space at the Hotel means real business travel now! Good for the whole city.",
		["ja_tohoku"] = "Conference space at the Hotel means real business travel now! Good for the whole city.",
		["ja_kyushu"] = "Conference space at the Hotel means real business travel now! Good for the whole city.",
		["ja_hokkaido"] = "Conference space at the Hotel means real business travel now! Good for the whole city.",
		["ja_okinawa"] = "Conference space at the Hotel means real business travel now! Good for the whole city.",
	},

	["If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win."] = {
		["_default"] = "If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win.",
		["ja_kanto"] = "If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win.",
		["ja_kansai"] = "If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win.",
		["ja_tohoku"] = "If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win.",
		["ja_kyushu"] = "If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win.",
		["ja_hokkaido"] = "If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win.",
		["ja_okinawa"] = "If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win.",
	},

	["Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike."] = {
		["_default"] = "Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike.",
		["ja_kanto"] = "Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike.",
		["ja_kansai"] = "Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike.",
		["ja_tohoku"] = "Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike.",
		["ja_kyushu"] = "Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike.",
		["ja_hokkaido"] = "Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike.",
		["ja_okinawa"] = "Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike.",
	},

	["Nice to see the Hotel hiring locally! Puts money right back into the neighborhood."] = {
		["_default"] = "Nice to see the Hotel hiring locally! Puts money right back into the neighborhood.",
		["ja_kanto"] = "Nice to see the Hotel hiring locally! Puts money right back into the neighborhood.",
		["ja_kansai"] = "Nice to see the Hotel hiring locally! Puts money right back into the neighborhood.",
		["ja_tohoku"] = "Nice to see the Hotel hiring locally! Puts money right back into the neighborhood.",
		["ja_kyushu"] = "Nice to see the Hotel hiring locally! Puts money right back into the neighborhood.",
		["ja_hokkaido"] = "Nice to see the Hotel hiring locally! Puts money right back into the neighborhood.",
		["ja_okinawa"] = "Nice to see the Hotel hiring locally! Puts money right back into the neighborhood.",
	},

	["The new movie theater revived date night. Popcorn economy booming!"] = {
		["_default"] = "The new movie theater revived date night. Popcorn economy booming!",
		["ja_kanto"] = "The new movie theater revived date night. Popcorn economy booming!",
		["ja_kansai"] = "The new movie theater revived date night. Popcorn economy booming!",
		["ja_tohoku"] = "The new movie theater revived date night. Popcorn economy booming!",
		["ja_kyushu"] = "The new movie theater revived date night. Popcorn economy booming!",
		["ja_hokkaido"] = "The new movie theater revived date night. Popcorn economy booming!",
		["ja_okinawa"] = "The new movie theater revived date night. Popcorn economy booming!",
	},

	["Festival screenings at the theater are drawing crowds! Downtown feels alive again."] = {
		["_default"] = "Festival screenings at the theater are drawing crowds! Downtown feels alive again.",
		["ja_kanto"] = "Festival screenings at the theater are drawing crowds! Downtown feels alive again.",
		["ja_kansai"] = "Festival screenings at the theater are drawing crowds! Downtown feels alive again.",
		["ja_tohoku"] = "Festival screenings at the theater are drawing crowds! Downtown feels alive again.",
		["ja_kyushu"] = "Festival screenings at the theater are drawing crowds! Downtown feels alive again.",
		["ja_hokkaido"] = "Festival screenings at the theater are drawing crowds! Downtown feels alive again.",
		["ja_okinawa"] = "Festival screenings at the theater are drawing crowds! Downtown feels alive again.",
	},

	["Free popcorn would help families! Any chance the theater can make that happen?"] = {
		["_default"] = "Free popcorn would help families! Any chance the theater can make that happen?",
		["ja_kanto"] = "Free popcorn would help families! Any chance the theater can make that happen?",
		["ja_kansai"] = "Free popcorn would help families! Any chance the theater can make that happen?",
		["ja_tohoku"] = "Free popcorn would help families! Any chance the theater can make that happen?",
		["ja_kyushu"] = "Free popcorn would help families! Any chance the theater can make that happen?",
		["ja_hokkaido"] = "Free popcorn would help families! Any chance the theater can make that happen?",
		["ja_okinawa"] = "Free popcorn would help families! Any chance the theater can make that happen?",
	},

	["Love the theater, but staggering showtimes could ease the parking crunch by a lot."] = {
		["_default"] = "Love the theater, but staggering showtimes could ease the parking crunch by a lot.",
		["ja_kanto"] = "Love the theater, but staggering showtimes could ease the parking crunch by a lot.",
		["ja_kansai"] = "Love the theater, but staggering showtimes could ease the parking crunch by a lot.",
		["ja_tohoku"] = "Love the theater, but staggering showtimes could ease the parking crunch by a lot.",
		["ja_kyushu"] = "Love the theater, but staggering showtimes could ease the parking crunch by a lot.",
		["ja_hokkaido"] = "Love the theater, but staggering showtimes could ease the parking crunch by a lot.",
		["ja_okinawa"] = "Love the theater, but staggering showtimes could ease the parking crunch by a lot.",
	},

	["Community film nights at the theater? Local shorts before the feature would be awesome."] = {
		["_default"] = "Community film nights at the theater? Local shorts before the feature would be awesome.",
		["ja_kanto"] = "Community film nights at the theater? Local shorts before the feature would be awesome.",
		["ja_kansai"] = "Community film nights at the theater? Local shorts before the feature would be awesome.",
		["ja_tohoku"] = "Community film nights at the theater? Local shorts before the feature would be awesome.",
		["ja_kyushu"] = "Community film nights at the theater? Local shorts before the feature would be awesome.",
		["ja_hokkaido"] = "Community film nights at the theater? Local shorts before the feature would be awesome.",
		["ja_okinawa"] = "Community film nights at the theater? Local shorts before the feature would be awesome.",
	},

	["The Church feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "The Church feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kanto"] = "The Church feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kansai"] = "The Church feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_tohoku"] = "The Church feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kyushu"] = "The Church feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_hokkaido"] = "The Church feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_okinawa"] = "The Church feels like a real community hub: quiet mornings, helpful people, open doors.",
	},

	["The Mosque feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "The Mosque feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kanto"] = "The Mosque feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kansai"] = "The Mosque feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_tohoku"] = "The Mosque feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kyushu"] = "The Mosque feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_hokkaido"] = "The Mosque feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_okinawa"] = "The Mosque feels like a real community hub: quiet mornings, helpful people, open doors.",
	},

	["The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kanto"] = "The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kansai"] = "The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_tohoku"] = "The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kyushu"] = "The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_hokkaido"] = "The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_okinawa"] = "The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
	},

	["The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kanto"] = "The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kansai"] = "The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_tohoku"] = "The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kyushu"] = "The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_hokkaido"] = "The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_okinawa"] = "The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors.",
	},

	["The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kanto"] = "The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kansai"] = "The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_tohoku"] = "The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_kyushu"] = "The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_hokkaido"] = "The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors.",
		["ja_okinawa"] = "The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors.",
	},

	["Could the Church extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "Could the Church extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kanto"] = "Could the Church extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kansai"] = "Could the Church extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_tohoku"] = "Could the Church extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kyushu"] = "Could the Church extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_hokkaido"] = "Could the Church extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_okinawa"] = "Could the Church extend weekend hours? Lots of families would appreciate evening programs.",
	},

	["Could the Mosque extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "Could the Mosque extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kanto"] = "Could the Mosque extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kansai"] = "Could the Mosque extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_tohoku"] = "Could the Mosque extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kyushu"] = "Could the Mosque extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_hokkaido"] = "Could the Mosque extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_okinawa"] = "Could the Mosque extend weekend hours? Lots of families would appreciate evening programs.",
	},

	["Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kanto"] = "Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kansai"] = "Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_tohoku"] = "Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kyushu"] = "Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_hokkaido"] = "Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_okinawa"] = "Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs.",
	},

	["Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kanto"] = "Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kansai"] = "Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_tohoku"] = "Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kyushu"] = "Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_hokkaido"] = "Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_okinawa"] = "Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs.",
	},

	["Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kanto"] = "Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kansai"] = "Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_tohoku"] = "Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_kyushu"] = "Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_hokkaido"] = "Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs.",
		["ja_okinawa"] = "Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs.",
	},

	["An interfaith open house at the Church would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "An interfaith open house at the Church would be great! Meet neighbors, share food, build trust.",
		["ja_kanto"] = "An interfaith open house at the Church would be great! Meet neighbors, share food, build trust.",
		["ja_kansai"] = "An interfaith open house at the Church would be great! Meet neighbors, share food, build trust.",
		["ja_tohoku"] = "An interfaith open house at the Church would be great! Meet neighbors, share food, build trust.",
		["ja_kyushu"] = "An interfaith open house at the Church would be great! Meet neighbors, share food, build trust.",
		["ja_hokkaido"] = "An interfaith open house at the Church would be great! Meet neighbors, share food, build trust.",
		["ja_okinawa"] = "An interfaith open house at the Church would be great! Meet neighbors, share food, build trust.",
	},

	["An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust.",
		["ja_kanto"] = "An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust.",
		["ja_kansai"] = "An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust.",
		["ja_tohoku"] = "An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust.",
		["ja_kyushu"] = "An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust.",
		["ja_hokkaido"] = "An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust.",
		["ja_okinawa"] = "An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust.",
	},

	["An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust.",
		["ja_kanto"] = "An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust.",
		["ja_kansai"] = "An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust.",
		["ja_tohoku"] = "An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust.",
		["ja_kyushu"] = "An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust.",
		["ja_hokkaido"] = "An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust.",
		["ja_okinawa"] = "An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust.",
	},

	["An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust.",
		["ja_kanto"] = "An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust.",
		["ja_kansai"] = "An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust.",
		["ja_tohoku"] = "An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust.",
		["ja_kyushu"] = "An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust.",
		["ja_hokkaido"] = "An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust.",
		["ja_okinawa"] = "An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust.",
	},

	["An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust.",
		["ja_kanto"] = "An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust.",
		["ja_kansai"] = "An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust.",
		["ja_tohoku"] = "An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust.",
		["ja_kyushu"] = "An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust.",
		["ja_hokkaido"] = "An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust.",
		["ja_okinawa"] = "An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust.",
	},

	["Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes."] = {
		["_default"] = "Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kanto"] = "Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kansai"] = "Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_tohoku"] = "Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kyushu"] = "Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_hokkaido"] = "Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_okinawa"] = "Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes.",
	},

	["Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes."] = {
		["_default"] = "Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kanto"] = "Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kansai"] = "Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_tohoku"] = "Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kyushu"] = "Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_hokkaido"] = "Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_okinawa"] = "Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes.",
	},

	["Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes."] = {
		["_default"] = "Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kanto"] = "Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kansai"] = "Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_tohoku"] = "Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kyushu"] = "Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_hokkaido"] = "Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_okinawa"] = "Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
	},

	["Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes."] = {
		["_default"] = "Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kanto"] = "Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kansai"] = "Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_tohoku"] = "Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_kyushu"] = "Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_hokkaido"] = "Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
		["ja_okinawa"] = "Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes.",
	},

	["Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes."] = {
		["_default"] = "Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes.",
		["ja_kanto"] = "Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes.",
		["ja_kansai"] = "Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes.",
		["ja_tohoku"] = "Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes.",
		["ja_kyushu"] = "Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes.",
		["ja_hokkaido"] = "Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes.",
		["ja_okinawa"] = "Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes.",
	},

	["Still no Bus Depot in this district; half the routes end in the middle of nowhere."] = {
		["_default"] = "Still no Bus Depot in this district; half the routes end in the middle of nowhere.",
		["ja_kanto"] = "Still no Bus Depot in this district; half the routes end in the middle of nowhere.",
		["ja_kansai"] = "Still no Bus Depot in this district; half the routes end in the middle of nowhere.",
		["ja_tohoku"] = "Still no Bus Depot in this district; half the routes end in the middle of nowhere.",
		["ja_kyushu"] = "Still no Bus Depot in this district; half the routes end in the middle of nowhere.",
		["ja_hokkaido"] = "Still no Bus Depot in this district; half the routes end in the middle of nowhere.",
		["ja_okinawa"] = "Still no Bus Depot in this district; half the routes end in the middle of nowhere.",
	},

	["No depot means buses break down on the street. Maybe build one before the fleet collapses?"] = {
		["_default"] = "No depot means buses break down on the street. Maybe build one before the fleet collapses?",
		["ja_kanto"] = "No depot means buses break down on the street. Maybe build one before the fleet collapses?",
		["ja_kansai"] = "No depot means buses break down on the street. Maybe build one before the fleet collapses?",
		["ja_tohoku"] = "No depot means buses break down on the street. Maybe build one before the fleet collapses?",
		["ja_kyushu"] = "No depot means buses break down on the street. Maybe build one before the fleet collapses?",
		["ja_hokkaido"] = "No depot means buses break down on the street. Maybe build one before the fleet collapses?",
		["ja_okinawa"] = "No depot means buses break down on the street. Maybe build one before the fleet collapses?",
	},

	["Waiting for a bus that never comes. This neighborhood needs proper service."] = {
		["_default"] = "Waiting for a bus that never comes. This neighborhood needs proper service.",
		["ja_kanto"] = "Waiting for a bus that never comes. This neighborhood needs proper service.",
		["ja_kansai"] = "Waiting for a bus that never comes. This neighborhood needs proper service.",
		["ja_tohoku"] = "Waiting for a bus that never comes. This neighborhood needs proper service.",
		["ja_kyushu"] = "Waiting for a bus that never comes. This neighborhood needs proper service.",
		["ja_hokkaido"] = "Waiting for a bus that never comes. This neighborhood needs proper service.",
		["ja_okinawa"] = "Waiting for a bus that never comes. This neighborhood needs proper service.",
	},

	["The new Bus Depot changed everything. Buses actually arrive on time now!"] = {
		["_default"] = "The new Bus Depot changed everything. Buses actually arrive on time now!",
		["ja_kanto"] = "The new Bus Depot changed everything. Buses actually arrive on time now!",
		["ja_kansai"] = "The new Bus Depot changed everything. Buses actually arrive on time now!",
		["ja_tohoku"] = "The new Bus Depot changed everything. Buses actually arrive on time now!",
		["ja_kyushu"] = "The new Bus Depot changed everything. Buses actually arrive on time now!",
		["ja_hokkaido"] = "The new Bus Depot changed everything. Buses actually arrive on time now!",
		["ja_okinawa"] = "The new Bus Depot changed everything. Buses actually arrive on time now!",
	},

	["Depot is open, routes are smooth, and commuting finally feels civilized."] = {
		["_default"] = "Depot is open, routes are smooth, and commuting finally feels civilized.",
		["ja_kanto"] = "Depot is open, routes are smooth, and commuting finally feels civilized.",
		["ja_kansai"] = "Depot is open, routes are smooth, and commuting finally feels civilized.",
		["ja_tohoku"] = "Depot is open, routes are smooth, and commuting finally feels civilized.",
		["ja_kyushu"] = "Depot is open, routes are smooth, and commuting finally feels civilized.",
		["ja_hokkaido"] = "Depot is open, routes are smooth, and commuting finally feels civilized.",
		["ja_okinawa"] = "Depot is open, routes are smooth, and commuting finally feels civilized.",
	},

	["Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do."] = {
		["_default"] = "Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do.",
		["ja_kanto"] = "Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do.",
		["ja_kansai"] = "Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do.",
		["ja_tohoku"] = "Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do.",
		["ja_kyushu"] = "Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do.",
		["ja_hokkaido"] = "Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do.",
		["ja_okinawa"] = "Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do.",
	},

	["Bus Depot is working overtime. Time to expand before rush hour destroys it."] = {
		["_default"] = "Bus Depot is working overtime. Time to expand before rush hour destroys it.",
		["ja_kanto"] = "Bus Depot is working overtime. Time to expand before rush hour destroys it.",
		["ja_kansai"] = "Bus Depot is working overtime. Time to expand before rush hour destroys it.",
		["ja_tohoku"] = "Bus Depot is working overtime. Time to expand before rush hour destroys it.",
		["ja_kyushu"] = "Bus Depot is working overtime. Time to expand before rush hour destroys it.",
		["ja_hokkaido"] = "Bus Depot is working overtime. Time to expand before rush hour destroys it.",
		["ja_okinawa"] = "Bus Depot is working overtime. Time to expand before rush hour destroys it.",
	},

	["We need more electric buses. The depot could lead the way in going green."] = {
		["_default"] = "We need more electric buses. The depot could lead the way in going green.",
		["ja_kanto"] = "We need more electric buses. The depot could lead the way in going green.",
		["ja_kansai"] = "We need more electric buses. The depot could lead the way in going green.",
		["ja_tohoku"] = "We need more electric buses. The depot could lead the way in going green.",
		["ja_kyushu"] = "We need more electric buses. The depot could lead the way in going green.",
		["ja_hokkaido"] = "We need more electric buses. The depot could lead the way in going green.",
		["ja_okinawa"] = "We need more electric buses. The depot could lead the way in going green.",
	},

	["Depot is too small for a growing city. Fund upgrades before delays return."] = {
		["_default"] = "Depot is too small for a growing city. Fund upgrades before delays return.",
		["ja_kanto"] = "Depot is too small for a growing city. Fund upgrades before delays return.",
		["ja_kansai"] = "Depot is too small for a growing city. Fund upgrades before delays return.",
		["ja_tohoku"] = "Depot is too small for a growing city. Fund upgrades before delays return.",
		["ja_kyushu"] = "Depot is too small for a growing city. Fund upgrades before delays return.",
		["ja_hokkaido"] = "Depot is too small for a growing city. Fund upgrades before delays return.",
		["ja_okinawa"] = "Depot is too small for a growing city. Fund upgrades before delays return.",
	},

	["Drivers deserve better facilities too. Fund the depot break rooms and workshops."] = {
		["_default"] = "Drivers deserve better facilities too. Fund the depot break rooms and workshops.",
		["ja_kanto"] = "Drivers deserve better facilities too. Fund the depot break rooms and workshops.",
		["ja_kansai"] = "Drivers deserve better facilities too. Fund the depot break rooms and workshops.",
		["ja_tohoku"] = "Drivers deserve better facilities too. Fund the depot break rooms and workshops.",
		["ja_kyushu"] = "Drivers deserve better facilities too. Fund the depot break rooms and workshops.",
		["ja_hokkaido"] = "Drivers deserve better facilities too. Fund the depot break rooms and workshops.",
		["ja_okinawa"] = "Drivers deserve better facilities too. Fund the depot break rooms and workshops.",
	},

	["No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground."] = {
		["_default"] = "No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground.",
		["ja_kanto"] = "No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground.",
		["ja_kansai"] = "No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground.",
		["ja_tohoku"] = "No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground.",
		["ja_kyushu"] = "No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground.",
		["ja_hokkaido"] = "No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground.",
		["ja_okinawa"] = "No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground.",
	},

	["We have skyscrapers but no Airport. How do people even visit this place?"] = {
		["_default"] = "We have skyscrapers but no Airport. How do people even visit this place?",
		["ja_kanto"] = "We have skyscrapers but no Airport. How do people even visit this place?",
		["ja_kansai"] = "We have skyscrapers but no Airport. How do people even visit this place?",
		["ja_tohoku"] = "We have skyscrapers but no Airport. How do people even visit this place?",
		["ja_kyushu"] = "We have skyscrapers but no Airport. How do people even visit this place?",
		["ja_hokkaido"] = "We have skyscrapers but no Airport. How do people even visit this place?",
		["ja_okinawa"] = "We have skyscrapers but no Airport. How do people even visit this place?",
	},

	["Driving to another city just to fly is ridiculous. Build an Airport already!"] = {
		["_default"] = "Driving to another city just to fly is ridiculous. Build an Airport already!",
		["ja_kanto"] = "Driving to another city just to fly is ridiculous. Build an Airport already!",
		["ja_kansai"] = "Driving to another city just to fly is ridiculous. Build an Airport already!",
		["ja_tohoku"] = "Driving to another city just to fly is ridiculous. Build an Airport already!",
		["ja_kyushu"] = "Driving to another city just to fly is ridiculous. Build an Airport already!",
		["ja_hokkaido"] = "Driving to another city just to fly is ridiculous. Build an Airport already!",
		["ja_okinawa"] = "Driving to another city just to fly is ridiculous. Build an Airport already!",
	},

	["Finally, flights are running and the Airport looks incredible."] = {
		["_default"] = "Finally, flights are running and the Airport looks incredible.",
		["ja_kanto"] = "Finally, flights are running and the Airport looks incredible.",
		["ja_kansai"] = "Finally, flights are running and the Airport looks incredible.",
		["ja_tohoku"] = "Finally, flights are running and the Airport looks incredible.",
		["ja_kyushu"] = "Finally, flights are running and the Airport looks incredible.",
		["ja_hokkaido"] = "Finally, flights are running and the Airport looks incredible.",
		["ja_okinawa"] = "Finally, flights are running and the Airport looks incredible.",
	},

	["Airport security is smooth, shops are open, and it actually feels world class."] = {
		["_default"] = "Airport security is smooth, shops are open, and it actually feels world class.",
		["ja_kanto"] = "Airport security is smooth, shops are open, and it actually feels world class.",
		["ja_kansai"] = "Airport security is smooth, shops are open, and it actually feels world class.",
		["ja_tohoku"] = "Airport security is smooth, shops are open, and it actually feels world class.",
		["ja_kyushu"] = "Airport security is smooth, shops are open, and it actually feels world class.",
		["ja_hokkaido"] = "Airport security is smooth, shops are open, and it actually feels world class.",
		["ja_okinawa"] = "Airport security is smooth, shops are open, and it actually feels world class.",
	},

	["Seeing planes overhead again feels like the city is truly connected to the world."] = {
		["_default"] = "Seeing planes overhead again feels like the city is truly connected to the world.",
		["ja_kanto"] = "Seeing planes overhead again feels like the city is truly connected to the world.",
		["ja_kansai"] = "Seeing planes overhead again feels like the city is truly connected to the world.",
		["ja_tohoku"] = "Seeing planes overhead again feels like the city is truly connected to the world.",
		["ja_kyushu"] = "Seeing planes overhead again feels like the city is truly connected to the world.",
		["ja_hokkaido"] = "Seeing planes overhead again feels like the city is truly connected to the world.",
		["ja_okinawa"] = "Seeing planes overhead again feels like the city is truly connected to the world.",
	},

	["The Airport has boosted local hotels and restaurants overnight. Smart investment!"] = {
		["_default"] = "The Airport has boosted local hotels and restaurants overnight. Smart investment!",
		["ja_kanto"] = "The Airport has boosted local hotels and restaurants overnight. Smart investment!",
		["ja_kansai"] = "The Airport has boosted local hotels and restaurants overnight. Smart investment!",
		["ja_tohoku"] = "The Airport has boosted local hotels and restaurants overnight. Smart investment!",
		["ja_kyushu"] = "The Airport has boosted local hotels and restaurants overnight. Smart investment!",
		["ja_hokkaido"] = "The Airport has boosted local hotels and restaurants overnight. Smart investment!",
		["ja_okinawa"] = "The Airport has boosted local hotels and restaurants overnight. Smart investment!",
	},

	["Airport is great, but we need a second terminal before travelers start camping on the floor."] = {
		["_default"] = "Airport is great, but we need a second terminal before travelers start camping on the floor.",
		["ja_kanto"] = "Airport is great, but we need a second terminal before travelers start camping on the floor.",
		["ja_kansai"] = "Airport is great, but we need a second terminal before travelers start camping on the floor.",
		["ja_tohoku"] = "Airport is great, but we need a second terminal before travelers start camping on the floor.",
		["ja_kyushu"] = "Airport is great, but we need a second terminal before travelers start camping on the floor.",
		["ja_hokkaido"] = "Airport is great, but we need a second terminal before travelers start camping on the floor.",
		["ja_okinawa"] = "Airport is great, but we need a second terminal before travelers start camping on the floor.",
	},

	["Customs lines are brutal. Time for more staff and faster systems."] = {
		["_default"] = "Customs lines are brutal. Time for more staff and faster systems.",
		["ja_kanto"] = "Customs lines are brutal. Time for more staff and faster systems.",
		["ja_kansai"] = "Customs lines are brutal. Time for more staff and faster systems.",
		["ja_tohoku"] = "Customs lines are brutal. Time for more staff and faster systems.",
		["ja_kyushu"] = "Customs lines are brutal. Time for more staff and faster systems.",
		["ja_hokkaido"] = "Customs lines are brutal. Time for more staff and faster systems.",
		["ja_okinawa"] = "Customs lines are brutal. Time for more staff and faster systems.",
	},

	["Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it."] = {
		["_default"] = "Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it.",
		["ja_kanto"] = "Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it.",
		["ja_kansai"] = "Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it.",
		["ja_tohoku"] = "Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it.",
		["ja_kyushu"] = "Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it.",
		["ja_hokkaido"] = "Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it.",
		["ja_okinawa"] = "Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it.",
	},

	["The cargo side of the Airport could use more funding too. Exports keep the city running."] = {
		["_default"] = "The cargo side of the Airport could use more funding too. Exports keep the city running.",
		["ja_kanto"] = "The cargo side of the Airport could use more funding too. Exports keep the city running.",
		["ja_kansai"] = "The cargo side of the Airport could use more funding too. Exports keep the city running.",
		["ja_tohoku"] = "The cargo side of the Airport could use more funding too. Exports keep the city running.",
		["ja_kyushu"] = "The cargo side of the Airport could use more funding too. Exports keep the city running.",
		["ja_hokkaido"] = "The cargo side of the Airport could use more funding too. Exports keep the city running.",
		["ja_okinawa"] = "The cargo side of the Airport could use more funding too. Exports keep the city running.",
	},

	["We need a Metro system already. The buses can only do so much."] = {
		["_default"] = "We need a Metro system already. The buses can only do so much.",
		["ja_kanto"] = "We need a Metro system already. The buses can only do so much.",
		["ja_kansai"] = "We need a Metro system already. The buses can only do so much.",
		["ja_tohoku"] = "We need a Metro system already. The buses can only do so much.",
		["ja_kyushu"] = "We need a Metro system already. The buses can only do so much.",
		["ja_hokkaido"] = "We need a Metro system already. The buses can only do so much.",
		["ja_okinawa"] = "We need a Metro system already. The buses can only do so much.",
	},

	["Traffic is a nightmare. Please, just build a Metro before I lose my mind."] = {
		["_default"] = "Traffic is a nightmare. Please, just build a Metro before I lose my mind.",
		["ja_kanto"] = "Traffic is a nightmare. Please, just build a Metro before I lose my mind.",
		["ja_kansai"] = "Traffic is a nightmare. Please, just build a Metro before I lose my mind.",
		["ja_tohoku"] = "Traffic is a nightmare. Please, just build a Metro before I lose my mind.",
		["ja_kyushu"] = "Traffic is a nightmare. Please, just build a Metro before I lose my mind.",
		["ja_hokkaido"] = "Traffic is a nightmare. Please, just build a Metro before I lose my mind.",
		["ja_okinawa"] = "Traffic is a nightmare. Please, just build a Metro before I lose my mind.",
	},

	["A Metro would connect the city like nothing else. No more two-hour commutes."] = {
		["_default"] = "A Metro would connect the city like nothing else. No more two-hour commutes.",
		["ja_kanto"] = "A Metro would connect the city like nothing else. No more two-hour commutes.",
		["ja_kansai"] = "A Metro would connect the city like nothing else. No more two-hour commutes.",
		["ja_tohoku"] = "A Metro would connect the city like nothing else. No more two-hour commutes.",
		["ja_kyushu"] = "A Metro would connect the city like nothing else. No more two-hour commutes.",
		["ja_hokkaido"] = "A Metro would connect the city like nothing else. No more two-hour commutes.",
		["ja_okinawa"] = "A Metro would connect the city like nothing else. No more two-hour commutes.",
	},

	["The Metro opened this week and it already feels like the city leveled up."] = {
		["_default"] = "The Metro opened this week and it already feels like the city leveled up.",
		["ja_kanto"] = "The Metro opened this week and it already feels like the city leveled up.",
		["ja_kansai"] = "The Metro opened this week and it already feels like the city leveled up.",
		["ja_tohoku"] = "The Metro opened this week and it already feels like the city leveled up.",
		["ja_kyushu"] = "The Metro opened this week and it already feels like the city leveled up.",
		["ja_hokkaido"] = "The Metro opened this week and it already feels like the city leveled up.",
		["ja_okinawa"] = "The Metro opened this week and it already feels like the city leveled up.",
	},

	["Fast, clean, quiet. I cannot believe I am saying this about public transport."] = {
		["_default"] = "Fast, clean, quiet. I cannot believe I am saying this about public transport.",
		["ja_kanto"] = "Fast, clean, quiet. I cannot believe I am saying this about public transport.",
		["ja_kansai"] = "Fast, clean, quiet. I cannot believe I am saying this about public transport.",
		["ja_tohoku"] = "Fast, clean, quiet. I cannot believe I am saying this about public transport.",
		["ja_kyushu"] = "Fast, clean, quiet. I cannot believe I am saying this about public transport.",
		["ja_hokkaido"] = "Fast, clean, quiet. I cannot believe I am saying this about public transport.",
		["ja_okinawa"] = "Fast, clean, quiet. I cannot believe I am saying this about public transport.",
	},

	["Took the Metro today and got to work early for the first time in years."] = {
		["_default"] = "Took the Metro today and got to work early for the first time in years.",
		["ja_kanto"] = "Took the Metro today and got to work early for the first time in years.",
		["ja_kansai"] = "Took the Metro today and got to work early for the first time in years.",
		["ja_tohoku"] = "Took the Metro today and got to work early for the first time in years.",
		["ja_kyushu"] = "Took the Metro today and got to work early for the first time in years.",
		["ja_hokkaido"] = "Took the Metro today and got to work early for the first time in years.",
		["ja_okinawa"] = "Took the Metro today and got to work early for the first time in years.",
	},

	["Finally, a Metro that makes us feel like a real city. Worth every tax dollar."] = {
		["_default"] = "Finally, a Metro that makes us feel like a real city. Worth every tax dollar.",
		["ja_kanto"] = "Finally, a Metro that makes us feel like a real city. Worth every tax dollar.",
		["ja_kansai"] = "Finally, a Metro that makes us feel like a real city. Worth every tax dollar.",
		["ja_tohoku"] = "Finally, a Metro that makes us feel like a real city. Worth every tax dollar.",
		["ja_kyushu"] = "Finally, a Metro that makes us feel like a real city. Worth every tax dollar.",
		["ja_hokkaido"] = "Finally, a Metro that makes us feel like a real city. Worth every tax dollar.",
		["ja_okinawa"] = "Finally, a Metro that makes us feel like a real city. Worth every tax dollar.",
	},

	["Rode the Metro at night and swear I saw someone staring back from an empty tunnel."] = {
		["_default"] = "Rode the Metro at night and swear I saw someone staring back from an empty tunnel.",
		["ja_kanto"] = "Rode the Metro at night and swear I saw someone staring back from an empty tunnel.",
		["ja_kansai"] = "Rode the Metro at night and swear I saw someone staring back from an empty tunnel.",
		["ja_tohoku"] = "Rode the Metro at night and swear I saw someone staring back from an empty tunnel.",
		["ja_kyushu"] = "Rode the Metro at night and swear I saw someone staring back from an empty tunnel.",
		["ja_hokkaido"] = "Rode the Metro at night and swear I saw someone staring back from an empty tunnel.",
		["ja_okinawa"] = "Rode the Metro at night and swear I saw someone staring back from an empty tunnel.",
	},

	["Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?"] = {
		["_default"] = "Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?",
		["ja_kanto"] = "Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?",
		["ja_kansai"] = "Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?",
		["ja_tohoku"] = "Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?",
		["ja_kyushu"] = "Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?",
		["ja_hokkaido"] = "Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?",
		["ja_okinawa"] = "Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?",
	},

	["People say the Metro hums even when the power is off. I am not checking to find out."] = {
		["_default"] = "People say the Metro hums even when the power is off. I am not checking to find out.",
		["ja_kanto"] = "People say the Metro hums even when the power is off. I am not checking to find out.",
		["ja_kansai"] = "People say the Metro hums even when the power is off. I am not checking to find out.",
		["ja_tohoku"] = "People say the Metro hums even when the power is off. I am not checking to find out.",
		["ja_kyushu"] = "People say the Metro hums even when the power is off. I am not checking to find out.",
		["ja_hokkaido"] = "People say the Metro hums even when the power is off. I am not checking to find out.",
		["ja_okinawa"] = "People say the Metro hums even when the power is off. I am not checking to find out.",
	},

	["Metro maintenance crews keep finding toys down there. No one knows where they come from."] = {
		["_default"] = "Metro maintenance crews keep finding toys down there. No one knows where they come from.",
		["ja_kanto"] = "Metro maintenance crews keep finding toys down there. No one knows where they come from.",
		["ja_kansai"] = "Metro maintenance crews keep finding toys down there. No one knows where they come from.",
		["ja_tohoku"] = "Metro maintenance crews keep finding toys down there. No one knows where they come from.",
		["ja_kyushu"] = "Metro maintenance crews keep finding toys down there. No one knows where they come from.",
		["ja_hokkaido"] = "Metro maintenance crews keep finding toys down there. No one knows where they come from.",
		["ja_okinawa"] = "Metro maintenance crews keep finding toys down there. No one knows where they come from.",
	},

	["Urban legend says Marvin used to live down there before the Metro opened. Now he just waits."] = {
		["_default"] = "Urban legend says Marvin used to live down there before the Metro opened. Now he just waits.",
		["ja_kanto"] = "Urban legend says Marvin used to live down there before the Metro opened. Now he just waits.",
		["ja_kansai"] = "Urban legend says Marvin used to live down there before the Metro opened. Now he just waits.",
		["ja_tohoku"] = "Urban legend says Marvin used to live down there before the Metro opened. Now he just waits.",
		["ja_kyushu"] = "Urban legend says Marvin used to live down there before the Metro opened. Now he just waits.",
		["ja_hokkaido"] = "Urban legend says Marvin used to live down there before the Metro opened. Now he just waits.",
		["ja_okinawa"] = "Urban legend says Marvin used to live down there before the Metro opened. Now he just waits.",
	},

	["Heard the Metro has a hidden station that is not on any map. If you see it, do not get off."] = {
		["_default"] = "Heard the Metro has a hidden station that is not on any map. If you see it, do not get off.",
		["ja_kanto"] = "Heard the Metro has a hidden station that is not on any map. If you see it, do not get off.",
		["ja_kansai"] = "Heard the Metro has a hidden station that is not on any map. If you see it, do not get off.",
		["ja_tohoku"] = "Heard the Metro has a hidden station that is not on any map. If you see it, do not get off.",
		["ja_kyushu"] = "Heard the Metro has a hidden station that is not on any map. If you see it, do not get off.",
		["ja_hokkaido"] = "Heard the Metro has a hidden station that is not on any map. If you see it, do not get off.",
		["ja_okinawa"] = "Heard the Metro has a hidden station that is not on any map. If you see it, do not get off.",
	},

	["Metro construction is noisy but worth it. The city finally feels alive again."] = {
		["_default"] = "Metro construction is noisy but worth it. The city finally feels alive again.",
		["ja_kanto"] = "Metro construction is noisy but worth it. The city finally feels alive again.",
		["ja_kansai"] = "Metro construction is noisy but worth it. The city finally feels alive again.",
		["ja_tohoku"] = "Metro construction is noisy but worth it. The city finally feels alive again.",
		["ja_kyushu"] = "Metro construction is noisy but worth it. The city finally feels alive again.",
		["ja_hokkaido"] = "Metro construction is noisy but worth it. The city finally feels alive again.",
		["ja_okinawa"] = "Metro construction is noisy but worth it. The city finally feels alive again.",
	},

	["They say the Metro went over budget again. Still better than sitting in traffic for half my life."] = {
		["_default"] = "They say the Metro went over budget again. Still better than sitting in traffic for half my life.",
		["ja_kanto"] = "They say the Metro went over budget again. Still better than sitting in traffic for half my life.",
		["ja_kansai"] = "They say the Metro went over budget again. Still better than sitting in traffic for half my life.",
		["ja_tohoku"] = "They say the Metro went over budget again. Still better than sitting in traffic for half my life.",
		["ja_kyushu"] = "They say the Metro went over budget again. Still better than sitting in traffic for half my life.",
		["ja_hokkaido"] = "They say the Metro went over budget again. Still better than sitting in traffic for half my life.",
		["ja_okinawa"] = "They say the Metro went over budget again. Still better than sitting in traffic for half my life.",
	},

	["Metro delays again, but at least it is progress. Better late than never."] = {
		["_default"] = "Metro delays again, but at least it is progress. Better late than never.",
		["ja_kanto"] = "Metro delays again, but at least it is progress. Better late than never.",
		["ja_kansai"] = "Metro delays again, but at least it is progress. Better late than never.",
		["ja_tohoku"] = "Metro delays again, but at least it is progress. Better late than never.",
		["ja_kyushu"] = "Metro delays again, but at least it is progress. Better late than never.",
		["ja_hokkaido"] = "Metro delays again, but at least it is progress. Better late than never.",
		["ja_okinawa"] = "Metro delays again, but at least it is progress. Better late than never.",
	},

	["Would love an Archery Range out here. Beats staring at empty lots all weekend."] = {
		["_default"] = "Would love an Archery Range out here. Beats staring at empty lots all weekend.",
		["ja_kanto"] = "Would love an Archery Range out here. Beats staring at empty lots all weekend.",
		["ja_kansai"] = "Would love an Archery Range out here. Beats staring at empty lots all weekend.",
		["ja_tohoku"] = "Would love an Archery Range out here. Beats staring at empty lots all weekend.",
		["ja_kyushu"] = "Would love an Archery Range out here. Beats staring at empty lots all weekend.",
		["ja_hokkaido"] = "Would love an Archery Range out here. Beats staring at empty lots all weekend.",
		["ja_okinawa"] = "Would love an Archery Range out here. Beats staring at empty lots all weekend.",
	},

	["Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city."] = {
		["_default"] = "Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city.",
		["ja_kanto"] = "Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city.",
		["ja_kansai"] = "Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city.",
		["ja_tohoku"] = "Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city.",
		["ja_kyushu"] = "Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city.",
		["ja_hokkaido"] = "Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city.",
		["ja_okinawa"] = "Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city.",
	},

	["Archery Range is way better than another mall. Focus over shopping any day."] = {
		["_default"] = "Archery Range is way better than another mall. Focus over shopping any day.",
		["ja_kanto"] = "Archery Range is way better than another mall. Focus over shopping any day.",
		["ja_kansai"] = "Archery Range is way better than another mall. Focus over shopping any day.",
		["ja_tohoku"] = "Archery Range is way better than another mall. Focus over shopping any day.",
		["ja_kyushu"] = "Archery Range is way better than another mall. Focus over shopping any day.",
		["ja_hokkaido"] = "Archery Range is way better than another mall. Focus over shopping any day.",
		["ja_okinawa"] = "Archery Range is way better than another mall. Focus over shopping any day.",
	},

	["The Basketball Court is packed every afternoon. Easily the best community spot around."] = {
		["_default"] = "The Basketball Court is packed every afternoon. Easily the best community spot around.",
		["ja_kanto"] = "The Basketball Court is packed every afternoon. Easily the best community spot around.",
		["ja_kansai"] = "The Basketball Court is packed every afternoon. Easily the best community spot around.",
		["ja_tohoku"] = "The Basketball Court is packed every afternoon. Easily the best community spot around.",
		["ja_kyushu"] = "The Basketball Court is packed every afternoon. Easily the best community spot around.",
		["ja_hokkaido"] = "The Basketball Court is packed every afternoon. Easily the best community spot around.",
		["ja_okinawa"] = "The Basketball Court is packed every afternoon. Easily the best community spot around.",
	},

	["Wish we had a Basketball Court nearby. It would keep the kids busy and happy."] = {
		["_default"] = "Wish we had a Basketball Court nearby. It would keep the kids busy and happy.",
		["ja_kanto"] = "Wish we had a Basketball Court nearby. It would keep the kids busy and happy.",
		["ja_kansai"] = "Wish we had a Basketball Court nearby. It would keep the kids busy and happy.",
		["ja_tohoku"] = "Wish we had a Basketball Court nearby. It would keep the kids busy and happy.",
		["ja_kyushu"] = "Wish we had a Basketball Court nearby. It would keep the kids busy and happy.",
		["ja_hokkaido"] = "Wish we had a Basketball Court nearby. It would keep the kids busy and happy.",
		["ja_okinawa"] = "Wish we had a Basketball Court nearby. It would keep the kids busy and happy.",
	},

	["Basketball Court beats any gym membership. Free, fun, and friendly."] = {
		["_default"] = "Basketball Court beats any gym membership. Free, fun, and friendly.",
		["ja_kanto"] = "Basketball Court beats any gym membership. Free, fun, and friendly.",
		["ja_kansai"] = "Basketball Court beats any gym membership. Free, fun, and friendly.",
		["ja_tohoku"] = "Basketball Court beats any gym membership. Free, fun, and friendly.",
		["ja_kyushu"] = "Basketball Court beats any gym membership. Free, fun, and friendly.",
		["ja_hokkaido"] = "Basketball Court beats any gym membership. Free, fun, and friendly.",
		["ja_okinawa"] = "Basketball Court beats any gym membership. Free, fun, and friendly.",
	},

	["Basketball Stadium days are the loudest, happiest days this city gets."] = {
		["_default"] = "Basketball Stadium days are the loudest, happiest days this city gets.",
		["ja_kanto"] = "Basketball Stadium days are the loudest, happiest days this city gets.",
		["ja_kansai"] = "Basketball Stadium days are the loudest, happiest days this city gets.",
		["ja_tohoku"] = "Basketball Stadium days are the loudest, happiest days this city gets.",
		["ja_kyushu"] = "Basketball Stadium days are the loudest, happiest days this city gets.",
		["ja_hokkaido"] = "Basketball Stadium days are the loudest, happiest days this city gets.",
		["ja_okinawa"] = "Basketball Stadium days are the loudest, happiest days this city gets.",
	},

	["We need a real Basketball Stadium so the team stops borrowing arenas."] = {
		["_default"] = "We need a real Basketball Stadium so the team stops borrowing arenas.",
		["ja_kanto"] = "We need a real Basketball Stadium so the team stops borrowing arenas.",
		["ja_kansai"] = "We need a real Basketball Stadium so the team stops borrowing arenas.",
		["ja_tohoku"] = "We need a real Basketball Stadium so the team stops borrowing arenas.",
		["ja_kyushu"] = "We need a real Basketball Stadium so the team stops borrowing arenas.",
		["ja_hokkaido"] = "We need a real Basketball Stadium so the team stops borrowing arenas.",
		["ja_okinawa"] = "We need a real Basketball Stadium so the team stops borrowing arenas.",
	},

	["The new Basketball Stadium is incredible. Feels like a major city now."] = {
		["_default"] = "The new Basketball Stadium is incredible. Feels like a major city now.",
		["ja_kanto"] = "The new Basketball Stadium is incredible. Feels like a major city now.",
		["ja_kansai"] = "The new Basketball Stadium is incredible. Feels like a major city now.",
		["ja_tohoku"] = "The new Basketball Stadium is incredible. Feels like a major city now.",
		["ja_kyushu"] = "The new Basketball Stadium is incredible. Feels like a major city now.",
		["ja_hokkaido"] = "The new Basketball Stadium is incredible. Feels like a major city now.",
		["ja_okinawa"] = "The new Basketball Stadium is incredible. Feels like a major city now.",
	},

	["Football Stadium crowds are massive. Local economy is loving game days."] = {
		["_default"] = "Football Stadium crowds are massive. Local economy is loving game days.",
		["ja_kanto"] = "Football Stadium crowds are massive. Local economy is loving game days.",
		["ja_kansai"] = "Football Stadium crowds are massive. Local economy is loving game days.",
		["ja_tohoku"] = "Football Stadium crowds are massive. Local economy is loving game days.",
		["ja_kyushu"] = "Football Stadium crowds are massive. Local economy is loving game days.",
		["ja_hokkaido"] = "Football Stadium crowds are massive. Local economy is loving game days.",
		["ja_okinawa"] = "Football Stadium crowds are massive. Local economy is loving game days.",
	},

	["Still waiting on a Football Stadium here. Everyone keeps driving to the next city."] = {
		["_default"] = "Still waiting on a Football Stadium here. Everyone keeps driving to the next city.",
		["ja_kanto"] = "Still waiting on a Football Stadium here. Everyone keeps driving to the next city.",
		["ja_kansai"] = "Still waiting on a Football Stadium here. Everyone keeps driving to the next city.",
		["ja_tohoku"] = "Still waiting on a Football Stadium here. Everyone keeps driving to the next city.",
		["ja_kyushu"] = "Still waiting on a Football Stadium here. Everyone keeps driving to the next city.",
		["ja_hokkaido"] = "Still waiting on a Football Stadium here. Everyone keeps driving to the next city.",
		["ja_okinawa"] = "Still waiting on a Football Stadium here. Everyone keeps driving to the next city.",
	},

	["The new Football Stadium puts our city on the map."] = {
		["_default"] = "The new Football Stadium puts our city on the map.",
		["ja_kanto"] = "The new Football Stadium puts our city on the map.",
		["ja_kansai"] = "The new Football Stadium puts our city on the map.",
		["ja_tohoku"] = "The new Football Stadium puts our city on the map.",
		["ja_kyushu"] = "The new Football Stadium puts our city on the map.",
		["ja_hokkaido"] = "The new Football Stadium puts our city on the map.",
		["ja_okinawa"] = "The new Football Stadium puts our city on the map.",
	},

	["Golf Course opened this week. Finally a reason for business meetings outdoors."] = {
		["_default"] = "Golf Course opened this week. Finally a reason for business meetings outdoors.",
		["ja_kanto"] = "Golf Course opened this week. Finally a reason for business meetings outdoors.",
		["ja_kansai"] = "Golf Course opened this week. Finally a reason for business meetings outdoors.",
		["ja_tohoku"] = "Golf Course opened this week. Finally a reason for business meetings outdoors.",
		["ja_kyushu"] = "Golf Course opened this week. Finally a reason for business meetings outdoors.",
		["ja_hokkaido"] = "Golf Course opened this week. Finally a reason for business meetings outdoors.",
		["ja_okinawa"] = "Golf Course opened this week. Finally a reason for business meetings outdoors.",
	},

	["A Golf Course would look great here. Better than another office park."] = {
		["_default"] = "A Golf Course would look great here. Better than another office park.",
		["ja_kanto"] = "A Golf Course would look great here. Better than another office park.",
		["ja_kansai"] = "A Golf Course would look great here. Better than another office park.",
		["ja_tohoku"] = "A Golf Course would look great here. Better than another office park.",
		["ja_kyushu"] = "A Golf Course would look great here. Better than another office park.",
		["ja_hokkaido"] = "A Golf Course would look great here. Better than another office park.",
		["ja_okinawa"] = "A Golf Course would look great here. Better than another office park.",
	},

	["Golf Course greens make this part of town look alive. Best landscaping in the city."] = {
		["_default"] = "Golf Course greens make this part of town look alive. Best landscaping in the city.",
		["ja_kanto"] = "Golf Course greens make this part of town look alive. Best landscaping in the city.",
		["ja_kansai"] = "Golf Course greens make this part of town look alive. Best landscaping in the city.",
		["ja_tohoku"] = "Golf Course greens make this part of town look alive. Best landscaping in the city.",
		["ja_kyushu"] = "Golf Course greens make this part of town look alive. Best landscaping in the city.",
		["ja_hokkaido"] = "Golf Course greens make this part of town look alive. Best landscaping in the city.",
		["ja_okinawa"] = "Golf Course greens make this part of town look alive. Best landscaping in the city.",
	},

	["Public Pool is open and the whole neighborhood showed up. Best summer in years."] = {
		["_default"] = "Public Pool is open and the whole neighborhood showed up. Best summer in years.",
		["ja_kanto"] = "Public Pool is open and the whole neighborhood showed up. Best summer in years.",
		["ja_kansai"] = "Public Pool is open and the whole neighborhood showed up. Best summer in years.",
		["ja_tohoku"] = "Public Pool is open and the whole neighborhood showed up. Best summer in years.",
		["ja_kyushu"] = "Public Pool is open and the whole neighborhood showed up. Best summer in years.",
		["ja_hokkaido"] = "Public Pool is open and the whole neighborhood showed up. Best summer in years.",
		["ja_okinawa"] = "Public Pool is open and the whole neighborhood showed up. Best summer in years.",
	},

	["We could use a Public Pool. The kids are melting out here."] = {
		["_default"] = "We could use a Public Pool. The kids are melting out here.",
		["ja_kanto"] = "We could use a Public Pool. The kids are melting out here.",
		["ja_kansai"] = "We could use a Public Pool. The kids are melting out here.",
		["ja_tohoku"] = "We could use a Public Pool. The kids are melting out here.",
		["ja_kyushu"] = "We could use a Public Pool. The kids are melting out here.",
		["ja_hokkaido"] = "We could use a Public Pool. The kids are melting out here.",
		["ja_okinawa"] = "We could use a Public Pool. The kids are melting out here.",
	},

	["The Public Pool beats every private gym. Cheap, clean, and fun."] = {
		["_default"] = "The Public Pool beats every private gym. Cheap, clean, and fun.",
		["ja_kanto"] = "The Public Pool beats every private gym. Cheap, clean, and fun.",
		["ja_kansai"] = "The Public Pool beats every private gym. Cheap, clean, and fun.",
		["ja_tohoku"] = "The Public Pool beats every private gym. Cheap, clean, and fun.",
		["ja_kyushu"] = "The Public Pool beats every private gym. Cheap, clean, and fun.",
		["ja_hokkaido"] = "The Public Pool beats every private gym. Cheap, clean, and fun.",
		["ja_okinawa"] = "The Public Pool beats every private gym. Cheap, clean, and fun.",
	},

	["The Skate Park finally opened. Now we can stop getting yelled at downtown."] = {
		["_default"] = "The Skate Park finally opened. Now we can stop getting yelled at downtown.",
		["ja_kanto"] = "The Skate Park finally opened. Now we can stop getting yelled at downtown.",
		["ja_kansai"] = "The Skate Park finally opened. Now we can stop getting yelled at downtown.",
		["ja_tohoku"] = "The Skate Park finally opened. Now we can stop getting yelled at downtown.",
		["ja_kyushu"] = "The Skate Park finally opened. Now we can stop getting yelled at downtown.",
		["ja_hokkaido"] = "The Skate Park finally opened. Now we can stop getting yelled at downtown.",
		["ja_okinawa"] = "The Skate Park finally opened. Now we can stop getting yelled at downtown.",
	},

	["Still no Skate Park here. Guess the stairs will have to do."] = {
		["_default"] = "Still no Skate Park here. Guess the stairs will have to do.",
		["ja_kanto"] = "Still no Skate Park here. Guess the stairs will have to do.",
		["ja_kansai"] = "Still no Skate Park here. Guess the stairs will have to do.",
		["ja_tohoku"] = "Still no Skate Park here. Guess the stairs will have to do.",
		["ja_kyushu"] = "Still no Skate Park here. Guess the stairs will have to do.",
		["ja_hokkaido"] = "Still no Skate Park here. Guess the stairs will have to do.",
		["ja_okinawa"] = "Still no Skate Park here. Guess the stairs will have to do.",
	},

	["Skate Park brings life to this area. Better than another parking lot any day."] = {
		["_default"] = "Skate Park brings life to this area. Better than another parking lot any day.",
		["ja_kanto"] = "Skate Park brings life to this area. Better than another parking lot any day.",
		["ja_kansai"] = "Skate Park brings life to this area. Better than another parking lot any day.",
		["ja_tohoku"] = "Skate Park brings life to this area. Better than another parking lot any day.",
		["ja_kyushu"] = "Skate Park brings life to this area. Better than another parking lot any day.",
		["ja_hokkaido"] = "Skate Park brings life to this area. Better than another parking lot any day.",
		["ja_okinawa"] = "Skate Park brings life to this area. Better than another parking lot any day.",
	},

	["Soccer Stadium is packed and electric. Nothing beats game day energy."] = {
		["_default"] = "Soccer Stadium is packed and electric. Nothing beats game day energy.",
		["ja_kanto"] = "Soccer Stadium is packed and electric. Nothing beats game day energy.",
		["ja_kansai"] = "Soccer Stadium is packed and electric. Nothing beats game day energy.",
		["ja_tohoku"] = "Soccer Stadium is packed and electric. Nothing beats game day energy.",
		["ja_kyushu"] = "Soccer Stadium is packed and electric. Nothing beats game day energy.",
		["ja_hokkaido"] = "Soccer Stadium is packed and electric. Nothing beats game day energy.",
		["ja_okinawa"] = "Soccer Stadium is packed and electric. Nothing beats game day energy.",
	},

	["Still no Soccer Stadium. Players keep practicing on empty fields."] = {
		["_default"] = "Still no Soccer Stadium. Players keep practicing on empty fields.",
		["ja_kanto"] = "Still no Soccer Stadium. Players keep practicing on empty fields.",
		["ja_kansai"] = "Still no Soccer Stadium. Players keep practicing on empty fields.",
		["ja_tohoku"] = "Still no Soccer Stadium. Players keep practicing on empty fields.",
		["ja_kyushu"] = "Still no Soccer Stadium. Players keep practicing on empty fields.",
		["ja_hokkaido"] = "Still no Soccer Stadium. Players keep practicing on empty fields.",
		["ja_okinawa"] = "Still no Soccer Stadium. Players keep practicing on empty fields.",
	},

	["Our Soccer Stadium puts the whole city in a good mood."] = {
		["_default"] = "Our Soccer Stadium puts the whole city in a good mood.",
		["ja_kanto"] = "Our Soccer Stadium puts the whole city in a good mood.",
		["ja_kansai"] = "Our Soccer Stadium puts the whole city in a good mood.",
		["ja_tohoku"] = "Our Soccer Stadium puts the whole city in a good mood.",
		["ja_kyushu"] = "Our Soccer Stadium puts the whole city in a good mood.",
		["ja_hokkaido"] = "Our Soccer Stadium puts the whole city in a good mood.",
		["ja_okinawa"] = "Our Soccer Stadium puts the whole city in a good mood.",
	},

	["The Tennis Court is spotless and full every morning. Great addition to the neighborhood."] = {
		["_default"] = "The Tennis Court is spotless and full every morning. Great addition to the neighborhood.",
		["ja_kanto"] = "The Tennis Court is spotless and full every morning. Great addition to the neighborhood.",
		["ja_kansai"] = "The Tennis Court is spotless and full every morning. Great addition to the neighborhood.",
		["ja_tohoku"] = "The Tennis Court is spotless and full every morning. Great addition to the neighborhood.",
		["ja_kyushu"] = "The Tennis Court is spotless and full every morning. Great addition to the neighborhood.",
		["ja_hokkaido"] = "The Tennis Court is spotless and full every morning. Great addition to the neighborhood.",
		["ja_okinawa"] = "The Tennis Court is spotless and full every morning. Great addition to the neighborhood.",
	},

	["Still no Tennis Court nearby. Guess we will keep using the parking lot lines."] = {
		["_default"] = "Still no Tennis Court nearby. Guess we will keep using the parking lot lines.",
		["ja_kanto"] = "Still no Tennis Court nearby. Guess we will keep using the parking lot lines.",
		["ja_kansai"] = "Still no Tennis Court nearby. Guess we will keep using the parking lot lines.",
		["ja_tohoku"] = "Still no Tennis Court nearby. Guess we will keep using the parking lot lines.",
		["ja_kyushu"] = "Still no Tennis Court nearby. Guess we will keep using the parking lot lines.",
		["ja_hokkaido"] = "Still no Tennis Court nearby. Guess we will keep using the parking lot lines.",
		["ja_okinawa"] = "Still no Tennis Court nearby. Guess we will keep using the parking lot lines.",
	},

	["The Tennis Court looks great next to the park. Makes the area feel upscale."] = {
		["_default"] = "The Tennis Court looks great next to the park. Makes the area feel upscale.",
		["ja_kanto"] = "The Tennis Court looks great next to the park. Makes the area feel upscale.",
		["ja_kansai"] = "The Tennis Court looks great next to the park. Makes the area feel upscale.",
		["ja_tohoku"] = "The Tennis Court looks great next to the park. Makes the area feel upscale.",
		["ja_kyushu"] = "The Tennis Court looks great next to the park. Makes the area feel upscale.",
		["ja_hokkaido"] = "The Tennis Court looks great next to the park. Makes the area feel upscale.",
		["ja_okinawa"] = "The Tennis Court looks great next to the park. Makes the area feel upscale.",
	},

	["You Need to Build A Water Source"] = {
		["_default"] = "You Need to Build A Water Source",
		["ja_kanto"] = "You Need to Build A Water Source",
	},

	["You Need to Build Water Pipes"] = {
		["_default"] = "You Need to Build Water Pipes",
		["ja_kanto"] = "You Need to Build Water Pipes",
	},

	["You Need to Build A Power Source"] = {
		["_default"] = "You Need to Build A Power Source",
		["ja_kanto"] = "You Need to Build A Power Source",
	},

	["You Need to Build Power Lines"] = {
		["_default"] = "You Need to Build Power Lines",
		["ja_kanto"] = "You Need to Build Power Lines",
	},

	["You Need to Build Roads"] = {
		["_default"] = "You Need to Build Roads",
		["ja_kanto"] = "You Need to Build Roads",
	},

	["Roads must connect back to the highway or citizens cant travel to your city!"] = {
		["_default"] = "Roads must connect back to the highway or citizens cant travel to your city!",
		["ja_kanto"] = "Roads must connect back to the highway or citizens cant travel to your city!",
	},

	["Flag Afghanistan"] = {
		["_default"] = "Flag Afghanistan",
		["ja_kanto"] = "Flag Afghanistan",
	},

	["Flag Albania"] = {
		["_default"] = "Flag Albania",
		["ja_kanto"] = "Flag Albania",
	},

	["Flag Algeria"] = {
		["_default"] = "Flag Algeria",
		["ja_kanto"] = "Flag Algeria",
	},

	["Flag America"] = {
		["_default"] = "Flag America",
		["ja_kanto"] = "Flag America",
	},

	["Flag Angola"] = {
		["_default"] = "Flag Angola",
		["ja_kanto"] = "Flag Angola",
	},

	["Flag Argentina"] = {
		["_default"] = "Flag Argentina",
		["ja_kanto"] = "Flag Argentina",
	},

	["Flag Armenia"] = {
		["_default"] = "Flag Armenia",
		["ja_kanto"] = "Flag Armenia",
	},

	["Flag Australia"] = {
		["_default"] = "Flag Australia",
		["ja_kanto"] = "Flag Australia",
	},

	["Flag Austria"] = {
		["_default"] = "Flag Austria",
		["ja_kanto"] = "Flag Austria",
	},

	["Flag Azerbaijan"] = {
		["_default"] = "Flag Azerbaijan",
		["ja_kanto"] = "Flag Azerbaijan",
	},

	["Flag Bahrain"] = {
		["_default"] = "Flag Bahrain",
		["ja_kanto"] = "Flag Bahrain",
	},

	["Flag Bangladesh"] = {
		["_default"] = "Flag Bangladesh",
		["ja_kanto"] = "Flag Bangladesh",
	},

	["Flag Belarus"] = {
		["_default"] = "Flag Belarus",
		["ja_kanto"] = "Flag Belarus",
	},

	["Flag Belgium"] = {
		["_default"] = "Flag Belgium",
		["ja_kanto"] = "Flag Belgium",
	},

	["Flag Belize"] = {
		["_default"] = "Flag Belize",
		["ja_kanto"] = "Flag Belize",
	},

	["Flag Benin"] = {
		["_default"] = "Flag Benin",
		["ja_kanto"] = "Flag Benin",
	},

	["Flag Bhutanica"] = {
		["_default"] = "Flag Bhutanica",
		["ja_kanto"] = "Flag Bhutanica",
	},

	["Flag Bolivia"] = {
		["_default"] = "Flag Bolivia",
		["ja_kanto"] = "Flag Bolivia",
	},

	["Flag Bosnia"] = {
		["_default"] = "Flag Bosnia",
		["ja_kanto"] = "Flag Bosnia",
	},

	["Flag Botswana"] = {
		["_default"] = "Flag Botswana",
		["ja_kanto"] = "Flag Botswana",
	},

	["Flag Brazil"] = {
		["_default"] = "Flag Brazil",
		["ja_kanto"] = "Flag Brazil",
	},

	["Flag Bulgaria"] = {
		["_default"] = "Flag Bulgaria",
		["ja_kanto"] = "Flag Bulgaria",
	},

	["Flag Burkina Faso"] = {
		["_default"] = "Flag Burkina Faso",
		["ja_kanto"] = "Flag Burkina Faso",
	},

	["Flag Burundi"] = {
		["_default"] = "Flag Burundi",
		["ja_kanto"] = "Flag Burundi",
	},

	["Flag Cambodia"] = {
		["_default"] = "Flag Cambodia",
		["ja_kanto"] = "Flag Cambodia",
	},

	["Flag Cameroon"] = {
		["_default"] = "Flag Cameroon",
		["ja_kanto"] = "Flag Cameroon",
	},

	["Flag Canada"] = {
		["_default"] = "Flag Canada",
		["ja_kanto"] = "Flag Canada",
	},

	["Flag Chad"] = {
		["_default"] = "Flag Chad",
		["ja_kanto"] = "Flag Chad",
	},

	["Flag Chile"] = {
		["_default"] = "Flag Chile",
		["ja_kanto"] = "Flag Chile",
	},

	["Flag China"] = {
		["_default"] = "Flag China",
		["ja_kanto"] = "Flag China",
	},

	["Flag Colombia"] = {
		["_default"] = "Flag Colombia",
		["ja_kanto"] = "Flag Colombia",
	},

	["Flag Congo"] = {
		["_default"] = "Flag Congo",
		["ja_kanto"] = "Flag Congo",
	},

	["Flag Costa Rica"] = {
		["_default"] = "Flag Costa Rica",
		["ja_kanto"] = "Flag Costa Rica",
	},

	["Flag Croatia"] = {
		["_default"] = "Flag Croatia",
		["ja_kanto"] = "Flag Croatia",
	},

	["Flag Cuba"] = {
		["_default"] = "Flag Cuba",
		["ja_kanto"] = "Flag Cuba",
	},

	["Flag Czech"] = {
		["_default"] = "Flag Czech",
		["ja_kanto"] = "Flag Czech",
	},

	["Flag DR Congo"] = {
		["_default"] = "Flag DR Congo",
		["ja_kanto"] = "Flag DR Congo",
	},

	["Flag Denmark"] = {
		["_default"] = "Flag Denmark",
		["ja_kanto"] = "Flag Denmark",
	},

	["Flag Dominican Republic"] = {
		["_default"] = "Flag Dominican Republic",
		["ja_kanto"] = "Flag Dominican Republic",
	},

	["Flag Ecuador"] = {
		["_default"] = "Flag Ecuador",
		["ja_kanto"] = "Flag Ecuador",
	},

	["Flag Egypt"] = {
		["_default"] = "Flag Egypt",
		["ja_kanto"] = "Flag Egypt",
	},

	["Flag El Salvador"] = {
		["_default"] = "Flag El Salvador",
		["ja_kanto"] = "Flag El Salvador",
	},

	["Flag Eritrea"] = {
		["_default"] = "Flag Eritrea",
		["ja_kanto"] = "Flag Eritrea",
	},

	["Flag Estonia"] = {
		["_default"] = "Flag Estonia",
		["ja_kanto"] = "Flag Estonia",
	},

	["Flag Ethiopia"] = {
		["_default"] = "Flag Ethiopia",
		["ja_kanto"] = "Flag Ethiopia",
	},

	["Flag Finland"] = {
		["_default"] = "Flag Finland",
		["ja_kanto"] = "Flag Finland",
	},

	["Flag France"] = {
		["_default"] = "Flag France",
		["ja_kanto"] = "Flag France",
	},

	["Flag Gabon"] = {
		["_default"] = "Flag Gabon",
		["ja_kanto"] = "Flag Gabon",
	},

	["Flag Gambia"] = {
		["_default"] = "Flag Gambia",
		["ja_kanto"] = "Flag Gambia",
	},

	["Flag Georgia"] = {
		["_default"] = "Flag Georgia",
		["ja_kanto"] = "Flag Georgia",
	},

	["Flag Germany"] = {
		["_default"] = "Flag Germany",
		["ja_kanto"] = "Flag Germany",
	},

	["Flag Ghana"] = {
		["_default"] = "Flag Ghana",
		["ja_kanto"] = "Flag Ghana",
	},

	["Flag Greece"] = {
		["_default"] = "Flag Greece",
		["ja_kanto"] = "Flag Greece",
	},

	["Flag Guatemala"] = {
		["_default"] = "Flag Guatemala",
		["ja_kanto"] = "Flag Guatemala",
	},

	["Flag Guinea"] = {
		["_default"] = "Flag Guinea",
		["ja_kanto"] = "Flag Guinea",
	},

	["Flag Honduras"] = {
		["_default"] = "Flag Honduras",
		["ja_kanto"] = "Flag Honduras",
	},

	["Flag Hungary"] = {
		["_default"] = "Flag Hungary",
		["ja_kanto"] = "Flag Hungary",
	},

	["Flag Iceland"] = {
		["_default"] = "Flag Iceland",
		["ja_kanto"] = "Flag Iceland",
	},

	["Flag India"] = {
		["_default"] = "Flag India",
		["ja_kanto"] = "Flag India",
	},

	["Flag Indonesia"] = {
		["_default"] = "Flag Indonesia",
		["ja_kanto"] = "Flag Indonesia",
	},

	["Flag Iran"] = {
		["_default"] = "Flag Iran",
		["ja_kanto"] = "Flag Iran",
	},

	["Flag Iraq"] = {
		["_default"] = "Flag Iraq",
		["ja_kanto"] = "Flag Iraq",
	},

	["Flag Ireland"] = {
		["_default"] = "Flag Ireland",
		["ja_kanto"] = "Flag Ireland",
	},

	["Flag Italy"] = {
		["_default"] = "Flag Italy",
		["ja_kanto"] = "Flag Italy",
	},

	["Flag Ivory Coast"] = {
		["_default"] = "Flag Ivory Coast",
		["ja_kanto"] = "Flag Ivory Coast",
	},

	["Flag Jamaica"] = {
		["_default"] = "Flag Jamaica",
		["ja_kanto"] = "Flag Jamaica",
	},

	["Flag Japan"] = {
		["_default"] = "Flag Japan",
		["ja_kanto"] = "Flag Japan",
	},

	["Flag Jordan"] = {
		["_default"] = "Flag Jordan",
		["ja_kanto"] = "Flag Jordan",
	},

	["Flag Kazakhstan"] = {
		["_default"] = "Flag Kazakhstan",
		["ja_kanto"] = "Flag Kazakhstan",
	},

	["Flag Kenya"] = {
		["_default"] = "Flag Kenya",
		["ja_kanto"] = "Flag Kenya",
	},

	["Flag Kyrgyzstan"] = {
		["_default"] = "Flag Kyrgyzstan",
		["ja_kanto"] = "Flag Kyrgyzstan",
	},

	["Flag Laos"] = {
		["_default"] = "Flag Laos",
		["ja_kanto"] = "Flag Laos",
	},

	["Flag Latvia"] = {
		["_default"] = "Flag Latvia",
		["ja_kanto"] = "Flag Latvia",
	},

	["Flag Lebanon"] = {
		["_default"] = "Flag Lebanon",
		["ja_kanto"] = "Flag Lebanon",
	},

	["Flag Liberia"] = {
		["_default"] = "Flag Liberia",
		["ja_kanto"] = "Flag Liberia",
	},

	["Flag Libya"] = {
		["_default"] = "Flag Libya",
		["ja_kanto"] = "Flag Libya",
	},

	["Flag Lithuania"] = {
		["_default"] = "Flag Lithuania",
		["ja_kanto"] = "Flag Lithuania",
	},

	["Flag Malawi"] = {
		["_default"] = "Flag Malawi",
		["ja_kanto"] = "Flag Malawi",
	},

	["Flag Malaysia"] = {
		["_default"] = "Flag Malaysia",
		["ja_kanto"] = "Flag Malaysia",
	},

	["Flag Maldova"] = {
		["_default"] = "Flag Maldova",
		["ja_kanto"] = "Flag Maldova",
	},

	["Flag Mali"] = {
		["_default"] = "Flag Mali",
		["ja_kanto"] = "Flag Mali",
	},

	["Flag Mauritania"] = {
		["_default"] = "Flag Mauritania",
		["ja_kanto"] = "Flag Mauritania",
	},

	["Flag Mexico"] = {
		["_default"] = "Flag Mexico",
		["ja_kanto"] = "Flag Mexico",
	},

	["Flag Mongolia"] = {
		["_default"] = "Flag Mongolia",
		["ja_kanto"] = "Flag Mongolia",
	},

	["Flag Montenegro"] = {
		["_default"] = "Flag Montenegro",
		["ja_kanto"] = "Flag Montenegro",
	},

	["Flag Morocco"] = {
		["_default"] = "Flag Morocco",
		["ja_kanto"] = "Flag Morocco",
	},

	["Flag Mozambique"] = {
		["_default"] = "Flag Mozambique",
		["ja_kanto"] = "Flag Mozambique",
	},

	["Flag Myanmar"] = {
		["_default"] = "Flag Myanmar",
		["ja_kanto"] = "Flag Myanmar",
	},

	["Flag Namibia"] = {
		["_default"] = "Flag Namibia",
		["ja_kanto"] = "Flag Namibia",
	},

	["Flag Netherlands"] = {
		["_default"] = "Flag Netherlands",
		["ja_kanto"] = "Flag Netherlands",
	},

	["Flag New Zealand"] = {
		["_default"] = "Flag New Zealand",
		["ja_kanto"] = "Flag New Zealand",
	},

	["Flag Nicaragua"] = {
		["_default"] = "Flag Nicaragua",
		["ja_kanto"] = "Flag Nicaragua",
	},

	["Flag Nigeria"] = {
		["_default"] = "Flag Nigeria",
		["ja_kanto"] = "Flag Nigeria",
	},

	["Flag Norway"] = {
		["_default"] = "Flag Norway",
		["ja_kanto"] = "Flag Norway",
	},

	["Flag Oman"] = {
		["_default"] = "Flag Oman",
		["ja_kanto"] = "Flag Oman",
	},

	["Flag Pakistan"] = {
		["_default"] = "Flag Pakistan",
		["ja_kanto"] = "Flag Pakistan",
	},

	["Flag Palestine"] = {
		["_default"] = "Flag Palestine",
		["ja_kanto"] = "Flag Palestine",
	},

	["Flag Panama"] = {
		["_default"] = "Flag Panama",
		["ja_kanto"] = "Flag Panama",
	},

	["Flag Papua New Guinea"] = {
		["_default"] = "Flag Papua New Guinea",
		["ja_kanto"] = "Flag Papua New Guinea",
	},

	["Flag Paraguay"] = {
		["_default"] = "Flag Paraguay",
		["ja_kanto"] = "Flag Paraguay",
	},

	["Flag Peru"] = {
		["_default"] = "Flag Peru",
		["ja_kanto"] = "Flag Peru",
	},

	["Flag Philippines"] = {
		["_default"] = "Flag Philippines",
		["ja_kanto"] = "Flag Philippines",
	},

	["Flag Poland"] = {
		["_default"] = "Flag Poland",
		["ja_kanto"] = "Flag Poland",
	},

	["Flag Qatar"] = {
		["_default"] = "Flag Qatar",
		["ja_kanto"] = "Flag Qatar",
	},

	["Flag Romania"] = {
		["_default"] = "Flag Romania",
		["ja_kanto"] = "Flag Romania",
	},

	["Flag Russia"] = {
		["_default"] = "Flag Russia",
		["ja_kanto"] = "Flag Russia",
	},

	["Flag Rwanda"] = {
		["_default"] = "Flag Rwanda",
		["ja_kanto"] = "Flag Rwanda",
	},

	["Flag Saudi Arabia"] = {
		["_default"] = "Flag Saudi Arabia",
		["ja_kanto"] = "Flag Saudi Arabia",
	},

	["Flag Senegal"] = {
		["_default"] = "Flag Senegal",
		["ja_kanto"] = "Flag Senegal",
	},

	["Flag Serbia"] = {
		["_default"] = "Flag Serbia",
		["ja_kanto"] = "Flag Serbia",
	},

	["Flag Sierra Leone"] = {
		["_default"] = "Flag Sierra Leone",
		["ja_kanto"] = "Flag Sierra Leone",
	},

	["Flag Singapore"] = {
		["_default"] = "Flag Singapore",
		["ja_kanto"] = "Flag Singapore",
	},

	["Flag Slovakia"] = {
		["_default"] = "Flag Slovakia",
		["ja_kanto"] = "Flag Slovakia",
	},

	["Flag Somalia"] = {
		["_default"] = "Flag Somalia",
		["ja_kanto"] = "Flag Somalia",
	},

	["Flag South Africa"] = {
		["_default"] = "Flag South Africa",
		["ja_kanto"] = "Flag South Africa",
	},

	["Flag South Korea"] = {
		["_default"] = "Flag South Korea",
		["ja_kanto"] = "Flag South Korea",
	},

	["Flag South Sudan"] = {
		["_default"] = "Flag South Sudan",
		["ja_kanto"] = "Flag South Sudan",
	},

	["Flag Spain"] = {
		["_default"] = "Flag Spain",
		["ja_kanto"] = "Flag Spain",
	},

	["Flag Sri Lanka"] = {
		["_default"] = "Flag Sri Lanka",
		["ja_kanto"] = "Flag Sri Lanka",
	},

	["Flag Sudan"] = {
		["_default"] = "Flag Sudan",
		["ja_kanto"] = "Flag Sudan",
	},

	["Flag Sweden"] = {
		["_default"] = "Flag Sweden",
		["ja_kanto"] = "Flag Sweden",
	},

	["Flag Switzerland"] = {
		["_default"] = "Flag Switzerland",
		["ja_kanto"] = "Flag Switzerland",
	},

	["Flag Syria"] = {
		["_default"] = "Flag Syria",
		["ja_kanto"] = "Flag Syria",
	},

	["Flag Taiwan"] = {
		["_default"] = "Flag Taiwan",
		["ja_kanto"] = "Flag Taiwan",
	},

	["Flag Tajikistan"] = {
		["_default"] = "Flag Tajikistan",
		["ja_kanto"] = "Flag Tajikistan",
	},

	["Flag Tanzania"] = {
		["_default"] = "Flag Tanzania",
		["ja_kanto"] = "Flag Tanzania",
	},

	["Flag Thailand"] = {
		["_default"] = "Flag Thailand",
		["ja_kanto"] = "Flag Thailand",
	},

	["Flag Togo"] = {
		["_default"] = "Flag Togo",
		["ja_kanto"] = "Flag Togo",
	},

	["Flag Tunisia"] = {
		["_default"] = "Flag Tunisia",
		["ja_kanto"] = "Flag Tunisia",
	},

	["Flag Turkmenistan"] = {
		["_default"] = "Flag Turkmenistan",
		["ja_kanto"] = "Flag Turkmenistan",
	},

	["Flag Türkiye"] = {
		["_default"] = "Flag Türkiye",
		["ja_kanto"] = "Flag Türkiye",
	},

	["Flag Uganda"] = {
		["_default"] = "Flag Uganda",
		["ja_kanto"] = "Flag Uganda",
	},

	["Flag Ukraine"] = {
		["_default"] = "Flag Ukraine",
		["ja_kanto"] = "Flag Ukraine",
	},

	["Flag United Kingdom"] = {
		["_default"] = "Flag United Kingdom",
		["ja_kanto"] = "Flag United Kingdom",
	},

	["Flag United Nations"] = {
		["_default"] = "Flag United Nations",
		["ja_kanto"] = "Flag United Nations",
	},

	["Flag Uruguay"] = {
		["_default"] = "Flag Uruguay",
		["ja_kanto"] = "Flag Uruguay",
	},

	["Flag Uzbekistan"] = {
		["_default"] = "Flag Uzbekistan",
		["ja_kanto"] = "Flag Uzbekistan",
	},

	["Flag Venezuela"] = {
		["_default"] = "Flag Venezuela",
		["ja_kanto"] = "Flag Venezuela",
	},

	["Flag Vietnam"] = {
		["_default"] = "Flag Vietnam",
		["ja_kanto"] = "Flag Vietnam",
	},

	["Flag Yemen"] = {
		["_default"] = "Flag Yemen",
		["ja_kanto"] = "Flag Yemen",
	},

	["Flag Zambia"] = {
		["_default"] = "Flag Zambia",
		["ja_kanto"] = "Flag Zambia",
	},

	["Flag Zimbabwe"] = {
		["_default"] = "Flag Zimbabwe",
		["ja_kanto"] = "Flag Zimbabwe",
	},

	["LOAD_BuildingRoads"] = {
		["_default"] = "LOAD_BuildingRoads",
		["ja_kanto"] = "LOAD_BuildingRoads",
	},

	["LOAD_DeletingSave"] = {
		["_default"] = "LOAD_DeletingSave",
		["ja_kanto"] = "LOAD_DeletingSave",
	},

	["LOAD_Finalizing"] = {
		["_default"] = "LOAD_Finalizing",
		["ja_kanto"] = "LOAD_Finalizing",
	},

	["LOAD_LayingUtilities"] = {
		["_default"] = "LOAD_LayingUtilities",
		["ja_kanto"] = "LOAD_LayingUtilities",
	},

	["LOAD_LoadingCity"] = {
		["_default"] = "LOAD_LoadingCity",
		["ja_kanto"] = "LOAD_LoadingCity",
	},

	["LOAD_LoadingSave"] = {
		["_default"] = "LOAD_LoadingSave",
		["ja_kanto"] = "LOAD_LoadingSave",
	},

	["LOAD_PlacingBuildings"] = {
		["_default"] = "LOAD_PlacingBuildings",
		["ja_kanto"] = "LOAD_PlacingBuildings",
	},

	["LOAD_Preparing"] = {
		["_default"] = "LOAD_Preparing",
		["ja_kanto"] = "LOAD_Preparing",
	},

	["LOAD_SettingUpZones"] = {
		["_default"] = "LOAD_SettingUpZones",
		["ja_kanto"] = "LOAD_SettingUpZones",
	},

	["LOAD_SwitchingSave"] = {
		["_default"] = "LOAD_SwitchingSave",
		["ja_kanto"] = "LOAD_SwitchingSave",
	},

	["ZoneNeedsRoad"] = {
		["_default"] = "A zone needs a road connection.",
	},
	["ZoneNeedsWater"] = {
		["_default"] = "A zone needs water service.",
	},
	["ZoneNeedsPower"] = {
		["_default"] = "A zone needs power.",
	},
	["ZoneHasRoad"] = {
		["_default"] = "A zone is now connected to a road.",
	},
	["ZoneLostRoad"] = {
		["_default"] = "A zone lost its road connection.",
	},
	["ZoneHasWater"] = {
		["_default"] = "A zone now has water.",
	},
	["ZoneLostWater"] = {
		["_default"] = "A zone lost water service.",
	},
	["ZoneHasPower"] = {
		["_default"] = "A zone now has power.",
	},
	["ZoneLostPower"] = {
		["_default"] = "A zone lost power.",
	},
	["ZonePollutedByIndustry"] = {
		["_default"] = "A zone is being polluted by a nearby industrial zone.",
	},
}
