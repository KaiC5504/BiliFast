// Made-up answers in the shapes the official app's own-space and skin endpoints return (field names from its
// models): every id, name, title, number, colour and picture is invented, and none carries a `uri`.
abstract final class OwnSpaceFixtures {
  static const space = r'''
{"code":0,"message":"OK","ttl":1,"data":{"relation":-999,"guest_relation":-999,"default_tab":"home",
"setting":{"fav_video":0,"bangumi":true,"coins_video":1,"likes_video":false,"dress_up":1,"charge_video":1},
"card":{"mid":"20000001","name":"测试本人","face":"http://i0.hdslb.com/bfs/face/made-up/own.jpg","fans":12,"attention":34,
"sign":"编的签名","level_info":{"current_level":5,"current_min":10800,"current_exp":14805,"next_exp":28800,"identity":1},
"pendant":{"pid":1,"name":"测试头像框","image":"http://i0.hdslb.com/bfs/garb/made-up/pendant.png","expire":0},
"vip":{"vipType":2,"vipStatus":1,"avatar_subscript":1,"label":{"image":""}}},
"images":{"imgUrl":"http://i0.hdslb.com/bfs/space/made-up/plain-banner.png",
"collection_top_simple":{"max":1,"top":{"result":[
{"biz_type":"garb","biz_id":1,"item_id":"1","cover":"http://i0.hdslb.com/bfs/garb/made-up/top-cover.png",
"item":{"item_type":1,"image":{"default_image":"http://i0.hdslb.com/bfs/garb/made-up/top.png","width":1125,"height":1600}},
"title":{"title":"测试星座 金牛座","sub_title":"NO.000067","sub_title_color_format":{"colors":["#FFFFFFFF","#80F5D4A6"]}}},
{"cover":"http://i0.hdslb.com/bfs/garb/made-up/second.png","title":{"title":"第二个"}}]}}},
"favourite2":{"count":3,"item":[
{"media_id":3000001,"id":30000,"title":"默认收藏夹","cover":"http://i0.hdslb.com/bfs/archive/made-up/fav1.jpg","count":25,
"is_public":0},
{"media_id":"3000002","title":"私密收藏夹","cover":"","count":"2","is_public":1},
{"title":"没有编号的收藏夹","count":1}]},
"season":{"count":6,"item":[
{"param":"40001","title":"完结番","cover":"//i0.hdslb.com/bfs/bangumi/made-up/s1.jpg","finish":true,"is_started":1,
"newest_ep_index":"12","total_count":"12"},
{"param":"40002","title":"连载番","cover":"http://i0.hdslb.com/bfs/bangumi/made-up/s2.jpg","finish":false,
"is_started":1,"newest_ep_index":"7","total_count":"-1"},
{"param":40003,"title":"特别篇","finish":0,"is_started":1,"newest_ep_index":"SP","total_count":"-1"},
{"param":"40004","title":"刚开播","finish":false,"is_started":1,"newest_ep_index":"-1"},
{"param":"40005","title":"未开播","finish":false,"is_started":0,"newest_ep_index":""},
{"title":"没有编号的番"}]},
"coin_archive":{"count":8,"item":[
{"title":"投币视频","cover":"http://i0.hdslb.com/bfs/archive/made-up/coin1.jpg","param":"100000000000501","goto":"av",
"bvid":"BV1madeup0501","duration":95,"play":1000,"danmaku":3,"ctime":1700000000,"publish_time_text":"11月15日"},
{"title":"投币课程","param":"100000000000502","goto":"cheese","bvid":"BV1madeup0502"}]},
"like_archive":{"count":20,"item":[
{"title":"点赞视频一","cover":"http://i0.hdslb.com/bfs/archive/made-up/like1.jpg","param":"100000000000601",
"bvid":"BV1madeup0601","duration":30},
{"title":"点赞视频二","cover":"http://i0.hdslb.com/bfs/archive/made-up/like2.jpg","param":100000000000602,
"bvid":"BV1madeup0602","duration":31}]},
"fans_dress":{"count":4,"total":7779,"more_url":"https://www.bilibili.com/h5/mall/made-up","item":[
{"image":"http://i0.hdslb.com/bfs/garb/made-up/dress1.png","garb_title":"测试装扮一","fans_number":"000067",
"fan_bg_color":"#FFB0A07A","suit_bg_color":"#5A4632","garb_id":1},
{"image":"https://i0.hdslb.com/bfs/garb/made-up/dress2.png","garb_title":"测试装扮二","fans_number":12,
"fan_bg_color":"","suit_bg_color":"not a colour"},
{"garb_title":"没有图的装扮"},
{"image":"https://i0.hdslb.com/bfs/garb/made-up/dress3.png","garb_title":"测试装扮三"},
{"image":"https://i0.hdslb.com/bfs/garb/made-up/dress4.png","garb_title":"测试装扮四"}]},
"tab2":[{"title":"主页","param":"home"},{"title":"投稿","param":"contribute","items":[{"title":"视频","param":"video"}]},
{"title":"追番","param":"bangumi"}]}}''';

  // Every extra missing, empty or of an odd type.
  static const spaceOdd = r'''
{"code":0,"message":"OK","ttl":1,"data":{"setting":"none",
"card":{"mid":20000002,"name":"奇怪本人","level_info":{"current_level":6,"current_exp":"--","next_exp":"--"},
"pendant":{"image":""},"vip":{"avatar_subscript":"1"}},
"images":{"imgUrl":"","collection_top_simple":{"top":{"result":[{"title":{"sub_title":"NO.1"}}]}}},
"favourite2":[],"season":{"count":"--","item":"none"},"coin_archive":{"count":2},"like_archive":null,
"fans_dress":{"count":1,"total":"7779","item":[{"image":"//i0.hdslb.com/bfs/garb/made-up/odd.png"}]}}}''';

  static const bangumiLast = r'''
{"code":0,"message":"0","ttl":1,"data":{"count":45,"item":[
{"param":"41041","title":"四十一","cover":"http://i0.hdslb.com/bfs/bangumi/made-up/41.jpg","finish":true,
"total_count":"24"},
{"param":"41042","title":"四十二","finish":false,"is_started":1,"newest_ep_index":"3"},
{"param":"41043","title":"四十三"},
{"param":"41044","title":"四十四"},
{"title":"没有编号"}]}}''';

  static const skin = r'''
{"code":0,"message":"0","ttl":1,"data":{
"user_equip":{"id":34001,"name":"测试装扮","ver":1700000000,
"package_url":"http://i0.hdslb.com/bfs/garb/zip/made-up-skin.zip","package_md5":"0123456789abcdef0123456789abcdef",
"conf":{"alias":"","attribute":4,"stime":0,"etime":0,"hide_dialog":false},
"data":{"color":"#FFFFFF","color_second_page":"#FF5A4632","color_mode":"light","tail_color":"#999999",
"tail_color_selected":"#fb7299","tail_icon_mode":"color","tail_icon_color":"#80999999",
"tail_icon_color_selected":"#FFFB7299","tail_icon_ani":true,"tail_icon_ani_mode":"cycle","head_myself_mp4_play":"loop",
"side_bg_color":"#000000","tail_icon_color_dark":"#FFFFFF"}},
"common_equip":{"id":1,"name":"测试活动装扮","package_url":"https://i0.hdslb.com/bfs/garb/zip/made-up-op.zip"},
"skin_colors":[{"id":8,"name":"测试粉","color_name":"pink","is_free":true}],
"load_equip":{"id":2,"name":"测试加载","loading_url":"https://i0.hdslb.com/bfs/garb/zip/made-up-load.zip","ver":1}}}''';

  // A plain colour theme: equipped, but nothing to download.
  static const skinColourTheme = r'''
{"code":0,"message":"0","ttl":1,"data":{"user_equip":{"id":8,"name":"测试粉","data":{"color":"#FB7299"}},
"common_equip":{"id":1,"name":"测试活动装扮","package_url":"https://i0.hdslb.com/bfs/garb/zip/made-up-op.zip"},
"skin_colors":[{"id":8,"name":"测试粉"}]}}''';

  static const skinNone = r'''{"code":0,"message":"0","ttl":1,"data":null}''';

  static const notLoggedIn = r'''{"code":-101,"message":"账号未登录","ttl":1}''';
}
