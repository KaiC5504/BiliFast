// Made-up space answers in the shapes the official app's endpoints return: every id, name, title and picture is
// invented. None carries a `uri`; the tests that need one add a made-up one themselves.
abstract final class SpaceFixtures {
  static const profile = r'''
{"code":0,"message":"OK","ttl":1,"data":{"relation":-999,"guest_relation":-999,"medal":1,"default_tab":"video",
"setting":{"channel":1,"fav_video":0,"charge_video":1},
"tab":{"archive":true,"dynamic":true,"shop":false,"mall":true,"series":true,"opus":true},
"card":{"mid":"10000001","name":"测试UP主","face":"http://i0.hdslb.com/bfs/face/made-up/face.jpg","fans":7037,"friend":0,
"attention":2,"sign":"这是编的简介","level_info":{"current_level":6,"current_min":0,"current_exp":0,"identity":2},
"official_verify":{"type":0,"desc":"测试认证","role":7,"title":"测试认证","icon":"","splice_title":"bilibili UP主认证：测试认证"},
"vip":{"vipType":2,"vipDueDate":0,"vipStatus":1,"label":{"path":"","text":"年度大会员","label_theme":"annual_vip","image":"http://i0.hdslb.com/bfs/vip/made-up/label.png"}},
"likes":{"like_num":174000,"skr_tip":"视频、专栏、动态累计获赞"},
"space_tag":[
{"type":"location","title":"IP属地：测试省","text_color":"#9499A0","icon":"http://i0.hdslb.com/bfs/space/made-up/ip.png"},
{"type":"school","title":"测试大学","text_color":"#9499A0","icon":"//i0.hdslb.com/bfs/space/made-up/school.png"},
{"type":"location","title":"","icon":""}]},
"images":{"imgUrl":"http://i0.hdslb.com/bfs/space/made-up/banner.jpg","night_imgurl":"","goods_available":true},
"elec":{"show":true,"total":5,"count":5,"list":[]},
"archive":{"order":[{"title":"最新发布","value":"pubdate"},{"title":"最多播放","value":"click"}],"count":45,"item":[]},
"series":{"item":[{"series_id":3001,"name":"测试系列"}],"count":1},
"tab2":[
{"title":"主页","param":"home","icon":""},
{"title":"动态","param":"dynamic","icon":""},
{"title":"投稿","param":"contribute","icon":"","items":[
{"title":"视频","param":"video","icon":""},
{"title":"图文","param":"opus","filter":[{"text":"全部图文","meta":"all","tab_name":"图文"}],"icon":""},
{"title":"专栏","param":"article","icon":""},
{"title":"音频","param":"audio","icon":""},
{"title":"测试合集","param":"season_video","season_id":2001,"icon":""},
{"title":"没有编号的合集","param":"season_video","icon":""},
{"title":"测试系列","param":"series","series_id":3001,"icon":""},
{"title":"充电专属","param":"charging_video","icon":""},
{"param":"video","icon":""}]},
{"title":"小店","param":"shop","icon":""},
{"title":"收藏","param":"favorite","icon":""},
{"title":"追番","param":"bangumi","icon":""},
{"title":"","param":"home","icon":""}],
"space_button_list":[
{"icon":"https://i0.hdslb.com/bfs/space/made-up/shop.png","title":"小店","sub_title":"1件商品","module_type":"goods","style":0},
{"icon":"https://i0.hdslb.com/bfs/space/made-up/charge.png","title":"充电","sub_title":"5人充电","module_type":"charge","style":0},
{"icon":"https://i0.hdslb.com/bfs/space/made-up/guard.png","title":"大航海","sub_title":"2人加入大航海","module_type":"navigation","style":0}]}}''';

  // Only what a space can't do without; everything else is missing, empty or of an odd type.
  static const profileBare = r'''
{"code":0,"message":"OK","ttl":1,"data":{"default_tab":"home",
"card":{"mid":10000002,"name":"空空UP主","face":"","fans":"--","level_info":{"current_level":2,"identity":"1"},
"official_verify":{"type":-1,"desc":"","splice_title":""},"vip":{"vipStatus":0,"label":{"image":""}},"space_tag":null},
"images":{"imgUrl":""},"elec":{"show":false},"archive":{"order":[{"title":"别的","value":"stow"}]},"tab2":"none"}}''';

  static const profileOrganisation = r'''
{"code":0,"message":"OK","ttl":1,"data":{"default_tab":"dynamic",
"card":{"mid":"10000003","name":"测试机构","official_verify":{"type":1,"splice_title":"bilibili 机构认证：测试机构"}},
"tab2":[{"title":"投稿","param":"contribute"}]}}''';

  static const profileWithoutCard = r'''
{"code":0,"message":"OK","ttl":1,"data":{"default_tab":"video","images":{"imgUrl":""}}}''';

  // A 课堂 course is not a video, and the last row has no bvid: both are dropped, but the cursor still moves past
  // the last.
  static const archiveFirst = r'''
{"code":0,"message":"OK","ttl":1,"data":{"episodic_button":{"text":"播放全部"},
"order":[{"title":"最新发布","value":"pubdate"},{"title":"最多播放","value":"click"}],"count":45,"has_next":true,
"has_prev":false,"last_watched_locator":{"display_threshold":10,"insert_ranking":6,"text":"定位至上次观看"},"item":[
{"title":"测试视频一","subtitle":"","tname":"测试","cover":"http://i0.hdslb.com/bfs/archive/made-up/cover1.jpg",
"param":"100000000000001","goto":"av","length":"","duration":1235,"is_cooperation":true,"play":121,"danmaku":7,
"ctime":1702200000,"badges":[{"text":"合作","bg_color":"#FB7299"},{"text":""},{"bg_color":"#FB7299"}],
"author":"测试UP主","bvid":"BV1madeup0001","videos":1,"first_cid":200000001,"view_content":"121",
"publish_time_text":"15小时前","three_point":[{"type":"addtoview","text":"添加至稍后再看"}]},
{"title":"测试课程","cover":"http://i0.hdslb.com/bfs/archive/made-up/course.jpg","param":"100000000000009",
"goto":"cheese","duration":0,"bvid":"BV1madeup0009","publish_time_text":"3天前"},
{"param":100000000000002,"bvid":"BV1madeup0002","cover":"//i0.hdslb.com/bfs/archive/made-up/cover2.jpg",
"duration":"--","play":"--","badges":null},
{"title":"没有bvid","param":"100000000000003","goto":"av","duration":60}]}}''';

  static const archiveLast = r'''
{"code":0,"message":"OK","ttl":1,"data":{"count":45,"has_next":false,"has_prev":true,"item":[
{"title":"测试视频四十五","cover":"https://i0.hdslb.com/bfs/archive/made-up/cover45.jpg","param":"100000000000045",
"bvid":"BV1madeup0045","duration":59,"play":3,"danmaku":0,"ctime":1600000000,"publish_time_text":"2020年9月13日"}]}}''';

  static const archiveEmptyButMore = r'''
{"code":0,"message":"OK","ttl":1,"data":{"count":45,"has_next":true,"has_prev":true,"item":[]}}''';

  // A 合集 comes whole: no next, no total.
  static const season = r'''
{"code":0,"message":"OK","ttl":1,"data":{"item":[
{"title":"合集视频一","cover":"http://i0.hdslb.com/bfs/archive/made-up/season1.jpg","param":"100000000000101",
"bvid":"BV1madeup0101","duration":198,"play":3956,"danmaku":67,"ctime":1694556126,"publish_time_text":"2023年9月13日"},
{"title":"合集视频二","cover":"http://i0.hdslb.com/bfs/archive/made-up/season2.jpg","param":"100000000000102",
"bvid":"BV1madeup0102","duration":200,"play":12,"danmaku":0,"ctime":1694600000,"publish_time_text":"2023年9月14日"}],
"episodic_button":{"text":"播放全部"},"order":[{"title":"默认","value":"desc"},{"title":"倒序","value":"asc"}]}}''';

  static const series = r'''
{"code":0,"message":"OK","ttl":1,"data":{"next":97,"total":115,"item":[
{"title":"系列视频一","cover":"http://i0.hdslb.com/bfs/archive/made-up/series1.jpg","param":"100000000000201",
"bvid":"BV1madeup0201","duration":336,"play":21528,"danmaku":77,"ctime":1700000000,"publish_time_text":"11月15日"},
{"title":"系列视频二","cover":"http://i0.hdslb.com/bfs/archive/made-up/series2.jpg","param":"100000000000202",
"bvid":"BV1madeup0202","duration":120,"play":5,"danmaku":1,"ctime":1699000000,"publish_time_text":"11月3日"}],
"episodic_button":{"text":"播放全部"},"order":[{"title":"默认","value":"desc"},{"title":"倒序","value":"asc"}]}}''';

  static const seriesEnd = r'''
{"code":0,"message":"OK","ttl":1,"data":{"next":0,"total":115,"item":[
{"title":"系列视频末","cover":"http://i0.hdslb.com/bfs/archive/made-up/series115.jpg","param":"100000000000315",
"bvid":"BV1madeup0315","duration":61,"play":1,"danmaku":0,"ctime":1500000000,"publish_time_text":"2017年7月14日"}]}}''';

  static const notFound = r'''{"code":-404,"message":"啥都木有","ttl":1}''';
}
