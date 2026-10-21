// Made-up search answers in the shapes the live endpoints return: every id, name, title and URL is invented.
abstract final class SearchFixtures {
  static const defaultWord = r'''
{"code":0,"message":"0","ttl":1,"data":{"seid":"1000000000000000001","id":1000000000000000002,"type":0,"show_name":"测试默认词","name":"测试默认词全名","goto_type":0,"goto_value":"","url":"https://search.bilibili.com/all?keyword=测试默认词"}}''';

  static const defaultWordNameOnly = r'''
{"code":0,"message":"0","ttl":1,"data":{"seid":"1000000000000000003","id":1000000000000000004,"type":0,"show_name":"","name":"只有名字","goto_type":0,"goto_value":"","url":""}}''';

  static const defaultWordEmpty = r'''
{"code":0,"message":"0","ttl":1,"data":{"seid":"1000000000000000005","id":0,"type":0,"show_name":"","name":"","goto_type":0,"goto_value":"","url":""}}''';

  // The last good row is the eleventh, past the ten asked for; the row without a keyword fails to decode.
  static const trending = r'''
{"code":0,"message":"0","ttl":1,"data":{"trackid":"2000000000000000001","exp_str":"_","hotword_egg_info":"0",
"list":[
{"position":1,"keyword":"热搜词一","show_name":"热搜词一","word_type":8,"hot_id":300001,"is_commercial":"0"},
{"position":2,"keyword":"热搜词二","show_name":"热搜词二","word_type":5,"icon":"http://i0.hdslb.com/bfs/activity-plat/static/made-up/hot-badge.png","hot_id":300002,"is_commercial":"0"},
{"position":3,"keyword":"热搜词三","show_name":"热搜词三展示","word_type":4,"icon":"//i0.hdslb.com/bfs/activity-plat/static/made-up/new-badge.png","hot_id":300003,"is_commercial":"0"},
{"position":4,"keyword":"热搜词四","word_type":4,"icon":"","hot_id":300004,"is_commercial":"0"},
{"position":5,"show_name":"没有关键词","word_type":4,"hot_id":300005,"is_commercial":"0"},
{"position":6,"keyword":"热搜词六","show_name":"","word_type":4,"hot_id":300006,"is_commercial":"0","show_live_icon":true,"resource_id":0},
{"position":7,"keyword":"热搜词七","show_name":"热搜词七","word_type":4,"hot_id":300007,"is_commercial":"0"},
{"position":8,"keyword":"热搜词八","show_name":"热搜词八","word_type":4,"icon":"https://i0.hdslb.com/bfs/activity-plat/static/made-up/hot-badge.png","hot_id":300008,"is_commercial":"0"},
{"position":9,"keyword":"热搜词九","show_name":"热搜词九","word_type":4,"hot_id":300009,"is_commercial":"0"},
{"position":10,"keyword":"热搜词十","show_name":"热搜词十","word_type":4,"hot_id":300010,"is_commercial":"0"},
{"position":11,"keyword":"热搜词十一","show_name":"热搜词十一","word_type":4,"hot_id":300011,"is_commercial":"0"},
{"position":12,"keyword":"热搜词十二","show_name":"热搜词十二","word_type":4,"hot_id":300012,"is_commercial":"0"}],
"top_list":[{"hot_id":300000,"keyword":"置顶词","show_name":"置顶词","score":0.0,"word_type":1,"goto_type":0,"goto_value":"","icon":"","live_id":[],"call_reason":4,"heat_layer":"B","pos":0,"id":0,"status":"","name_type":"","resource_id":0,"set_gray":0}]}}''';

  static const recommend = r'''
{"code":0,"message":"0","ttl":1,"data":{"trackid":"3000000000000000001","title":"搜索推荐","pages":0,
"list":[
{"position":1,"title":"发现词一","param":"4000000000000000001","author_prefix":"","type":"guess","id":4000000000000000001,"pub_time":"","keyword":"发现词一","is_sug_style_exp":0,"more_search_type":0,"share_from":"","auto_expand":false,"bubbles":null,"business":"","message_id":0,"like_state":0,"like_number":0,"show_name":"发现词一","card_style":0,"show_follow_button":0,"aspect_ratio":0,"pedia_card_ui":null,"cover_type":0,"up_uri":"","row":0,"reply_text":"","is_more":false,"user_card_desc":"","inline_title_style":0,"cover_badge":null,"ShortOGVInfo":{"AppId":"","SeasonId":0,"EpisodeId":0}},
{"position":2,"title":"发现词二","param":"4000000000000000002","type":"guess","id":4000000000000000002,"keyword":"发现词二","show_name":"发现词二展示","recommend_reason":"·昨天更新","card_style":0},
{"position":3,"title":"没有关键词","param":"4000000000000000003","type":"guess","id":4000000000000000003,"keyword":"","show_name":"没有关键词"},
{"position":4,"title":"发现词四","param":"4000000000000000004","type":"guess","id":4000000000000000004,"keyword":"发现词四","pub_time":"3天前","card_style":0}],
"negative_feedback":{"display_feedback":true,"toast_time":3,"feedback_list":[]},"board_expand_time_milli":100,"board_close_time_milli":100}}''';

  // The real answer: the rows sit beside `code`, in `result`, with no `data`.
  static const suggest = r'''
{"exp_str":"10000000_20000000","code":0,"result":{"tag":[
{"value":"kiwijam联动","term":"kiwijam联动","ref":0,"name":"kiwijam联动","spid":5,"type":""},
{"value":"测试KIWI大全","term":"测试KIWI大全","ref":0,"name":"测试KIWI大全","spid":5,"type":""},
{"value":"无关测试","term":"无关测试","ref":0,"name":"无关测试","spid":5,"type":""},
{"value":"","term":"","ref":0,"name":"","spid":5,"type":""},
{"value":"kiwi标记","term":"kiwi标记","ref":0,"name":"<em class=\"suggest_high_light\">kiwi</em>标记","spid":5,"type":""}]},
"stoken":"5000000000000000001","total_count":5}''';

  // The shape PiliPlus reads.
  static const suggestUnderData = r'''
{"code":0,"message":"0","ttl":1,"data":{"result":{"tag":[{"value":"kiwi测试","term":"kiwi测试","ref":0,"name":"kiwi测试","spid":5,"type":""}]},"stoken":"5000000000000000002"}}''';

  static const suggestEmpty = r'''
{"exp_str":"10000000_20000000","code":0,"result":[],"stoken":"5000000000000000003","total_count":0}''';

  static const suggestNoResult = r'''
{"exp_str":"10000000_20000000","code":0,"stoken":"5000000000000000004","total_count":0}''';

  // The video group carries a live room (no bvid) and a row that fails to decode beside the three videos.
  static const all = r'''
{"code":0,"message":"0","ttl":1,"data":{"seid":"6000000000000000001","page":1,"pagesize":20,"next":2,"numResults":1000,"numPages":50,"suggest_keyword":"","rqt_type":"search","exp_list":{"100099":true},"is_hit_web_inf":false,"egg_hit":0,
"pageinfo":{"tv":{"numResults":0,"pages":0,"total":0},"live_room":{"numResults":19,"pages":2,"total":19},"video":{"numResults":1000,"pages":50,"total":1000},"bili_user":{"numResults":1000,"pages":50,"total":1000}},
"top_tlist":{"video":1000,"bili_user":1000,"live_room":19},"show_column":0,"show_module_list":["tips","bili_user","user","video"],"app_display_option":{"is_search_page_grayed":0},"in_black_key":0,"in_white_key":0,
"result":[
{"result_type":"tips","data":[]},
{"result_type":"bili_user","data":[]},
{"result_type":"user","data":[]},
{"result_type":"video","data":[
{"type":"video","id":113000000000101,"author":"测试UP甲","mid":7000001,"typeid":"999","typename":"测试分区","arcurl":"http://www.bilibili.com/video/av113000000000101","aid":113000000000101,"bvid":"BV1Te4y1s7aA","title":"【测试】<em class=\"keyword\">星星</em>的视频 &amp; 更多<em class=\"keyword\">星星</em>","description":"简介","pic":"//i1.hdslb.com/bfs/archive/made-up-cover-0101.jpg","play":12345,"video_review":67,"favorites":89,"tag":"测试,标签","review":45,"pubdate":1760000000,"senddate":1760000500,"duration":"3:7","badgepay":false,"hit_columns":["title","tag"],"view_type":"","is_pay":0,"is_union_video":0,"rec_tags":null,"new_rec_tags":[],"like":678,"upic":"https://i1.hdslb.com/bfs/face/made-up-face-0101.jpg","corner":"","cover":"","desc":"","url":"","rec_reason":"","danmaku":67,"biz_data":null,"is_charge_video":0,"vt":0,"enable_vt":0,"vt_display":"","subtitle":"","episode_count_text":"","release_status":0,"is_intervene":0,"area":0,"style":0,"cate_name":"","is_live_room_inline":0,"live_status":0,"live_time":"","online":0,"rank_index":1,"rank_offset":1,"roomid":0,"short_id":0,"spread_id":0,"tags":"","uface":"","uid":0,"uname":"","user_cover":"","parent_area_id":0,"parent_area_name":"","watched_show":null,"cny_flag":0,"card_status":0},
{"type":"live_room","id":8000001,"author":"测试主播","mid":7000002,"title":"直播中","pic":"//i0.hdslb.com/bfs/live-key-frame/made-up-keyframe.jpg","cover":"//i0.hdslb.com/bfs/live-key-frame/made-up-keyframe.jpg","bvid":"","aid":0,"duration":"","play":null,"video_review":0,"danmaku":0,"pubdate":0,"live_status":1,"online":321,"rank_index":2,"rank_offset":1,"roomid":8000001,"uface":"//i2.hdslb.com/bfs/face/made-up-face-0102.jpg","uid":7000002,"uname":"测试主播","card_status":1},
{"type":"video","id":113000000000103,"author":"测试UP乙","mid":7000003,"aid":113000000000103,"bvid":"BV1Te4y1s7aC","title":"无高亮的标题","pic":"http://i2.hdslb.com/bfs/archive/made-up-cover-0103.jpg","play":"4321","video_review":"21","pubdate":1760100000,"duration":"13:14","danmaku":21},
{"type":"video","id":113000000000104,"author":"坏行","mid":7000004,"aid":113000000000104,"bvid":12345,"title":"bvid 是数字","pic":"","play":1,"video_review":0,"pubdate":0,"duration":"0:01"},
{"type":"video","id":113000000000105,"author":"测试UP丙","mid":7000005,"aid":113000000000105,"bvid":"BV1Te4y1s7aE","title":"长视频","pic":"https://i0.hdslb.com/bfs/archive/made-up-cover-0105.jpg","play":0,"danmaku":5,"pubdate":0,"duration":"1:02:03"}]}],
"is_search_page_grayed":0}}''';

  static const video = r'''
{"code":0,"message":"0","ttl":1,"data":{"seid":"6000000000000000002","page":2,"pagesize":20,"numResults":1000,"numPages":50,"suggest_keyword":"","rqt_type":"search","exp_list":{"100099":true},"is_hit_web_inf":false,"egg_hit":0,"show_column":0,"in_black_key":0,"in_white_key":0,"next":3,
"result":[
{"type":"video","id":113000000000201,"author":"测试合集UP","mid":7000011,"typeid":"999","typename":"测试分区","arcurl":"http://www.bilibili.com/video/av113000000000201","aid":113000000000201,"bvid":"BV1Te4y1s7bA","title":"测试剧情合集四期（&lt;更新&gt; &quot;主线&quot; &#39;一&#39; &#x2764;）","description":"会更新的","pic":"//i1.hdslb.com/bfs/archive/made-up-cover-0201.jpg","play":1234567,"video_review":23456,"favorites":3456,"tag":"测试","review":901,"pubdate":1750000000,"senddate":1750000100,"duration":"1234:56","badgepay":false,"hit_columns":["tag"],"is_pay":0,"is_union_video":0,"like":5678,"upic":"https://i1.hdslb.com/bfs/face/made-up-face-0201.jpg","danmaku":23456},
{"type":"video","id":113000000000202,"author":"测试UP丁","mid":7000012,"aid":113000000000202,"bvid":"BV1Te4y1s7bB","title":"整数时长","pic":"//i0.hdslb.com/bfs/archive/made-up-cover-0202.jpg","play":"--","danmaku":"12","pubdate":1750000200,"duration":125}]}}''';

  static const user = r'''
{"code":0,"message":"0","ttl":1,"data":{"seid":"6000000000000000003","page":1,"pagesize":20,"numResults":47,"numPages":3,"suggest_keyword":"","rqt_type":"search","exp_list":{"100099":true},"egg_hit":0,"show_column":0,"in_black_key":0,"in_white_key":0,
"result":[
{"type":"bili_user","mid":9000001,"uname":"测试用户甲","usign":"签名&符号","fans":8,"videos":0,"upic":"//i2.hdslb.com/bfs/face/made-up-face-0301.jpg","face_nft":0,"face_nft_type":0,"verify_info":"","level":2,"gender":2,"is_upuser":0,"is_live":0,"room_id":0,"res":[],"official_verify":{"type":127,"desc":""},"hit_columns":["uname"],"is_senior_member":0},
{"type":"bili_user","mid":9000002,"uname":"测试知名UP","usign":"知名UP的签名","fans":23456,"videos":87,"upic":"//i1.hdslb.com/bfs/face/made-up-face-0302.jpg","face_nft":0,"face_nft_type":0,"verify_info":"","level":6,"gender":1,"is_upuser":1,"is_live":0,"room_id":0,
"res":[{"aid":113000000000301,"bvid":"BV1Te4y1s7cA","title":"作品","pubdate":1750000300,"arcurl":"http://www.bilibili.com/video/av113000000000301","pic":"//i2.hdslb.com/bfs/archive/made-up-cover-0301.jpg","play":"4567","dm":15,"coin":71,"fav":251,"desc":"-","duration":"4:05","is_pay":0,"is_union_video":0,"is_charge_video":0,"vt":0,"enable_vt":0,"vt_display":""}],
"official_verify":{"type":0,"desc":"bilibili 测试知名UP主"},"hit_columns":["uname"],"is_senior_member":1},
{"type":"bili_user","mid":9000003,"uname":"测试机构","usign":"","fans":"2100","videos":12,"upic":"http://i0.hdslb.com/bfs/face/made-up-face-0303.jpg","level":5,"official_verify":{"type":1,"desc":"测试机构官方账号"},"is_atten":1},
{"type":"bili_user","mid":9000004,"uname":"没有认证字段","usign":"","fans":3,"videos":1,"upic":"https://i0.hdslb.com/bfs/face/made-up-face-0304.jpg","level":1},
{"type":"bili_user","mid":9000005,"uname":"认证为负一","usign":"","fans":3,"videos":1,"upic":"","level":1,"official_verify":{"type":-1,"desc":""}},
{"type":"bili_user","uname":"没有mid","usign":"","fans":0,"videos":0,"upic":"","level":0}]}}''';

  static const captcha = r'''
{"code":0,"message":"0","ttl":1,"data":{"v_voucher":"voucher_made-up-0001"}}''';

  static const captchaRefused = r'''
{"code":-352,"message":"-352","ttl":1,"data":{"v_voucher":"voucher_made-up-0002"}}''';

  static const emptySearch = r'''
{"code":0,"message":"0","ttl":1,"data":{"seid":"6000000000000000004","page":1,"pagesize":20,"numResults":0,"numPages":0,"result":[]}}''';
}
