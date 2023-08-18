extends Node

# oauth-dev.seyacat.com client_id integration
var client_id = "qhndxilvmmnsb8xq5jfmbvqk544opx"
var ws = WebSocketPeer.new() 
var is_connected = false;
signal new_message(data);
signal channel_loaded(channel);
signal connected;
var temp_id
var auth
var auth_connected = false
var annonimous_connected = false
var annonimousChannel = ""

# Called when the node enters the scene tree for the first time.
func _ready():
	var _timer = Timer.new()
	add_child(_timer)
	_timer.connect("timeout", _tic)
	_timer.set_wait_time(1.0)
	_timer.set_one_shot(false) # Make sure it loops
	_timer.start()
	_load_channel()
	_load_session()
	if(auth):
		_ws_connect()
		pass
	else:
		if(annonimousChannel != ''):
			_anon_connection()

func _tic(): 
	
	if auth:
		annonimous_connected = false
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			auth_connected = true
		else:
			auth_connected = false
	else:
		auth_connected = false
		if ws.get_ready_state() ==  WebSocketPeer.STATE_OPEN:
			annonimous_connected = true
		else:
			annonimous_connected = false
			
func setAnnonimousChannel(txt):
	annonimousChannel = txt
	_save_channel()
			
func _authenticate():
	auth = null
	temp_id =  str(RandomNumberGenerator.new().randf_range(0,100))+str(RandomNumberGenerator.new().randf_range(0,100));
	OS.shell_open("https://oauth-dev.seyacat.com/twitch/login?&scope=user:read:email+channel:manage:vips+moderator:manage:banned_users+chat:read&temp_id="+temp_id);

func _anon_connection():
	auth = null
	_ws_connect()
	
func _disconnect():
	auth = null
	_delete_session()
	ws.close()
	set_process(true)

func _ws_connect():
	set_process(true)
	#ws = WebSocketPeer.new()
	#ws.connect("data_received", _on_data)
	#ws.connect("connection_established" ,_connected)
	#ws.connect("connection_closed", _closed)
	var err = ws.connect_to_url("wss://irc-ws.chat.twitch.tv:443");
	
	#var err = ws.connect_to_url("ws://irc-ws.chat.twitch.tv:80");
	
	if err != 0:
		print("Unable to connect")
		set_process(false)

func _connected(proto = ""):
	print("Connected with protocol: ", proto)
	is_connected = true;
	emit_signal('connected')
	#await get_tree().create_timer(1000).timeout
	
	ws.send_text("CAP REQ :twitch.tv/membership twitch.tv/tags twitch.tv/commands")
	if auth && auth.has("accessToken"):
		print(auth.twitchUser.login)
		ws.send_text(("PASS oauth:" + auth.accessToken))
		ws.send_text(("NICK "+auth.twitchUser.login))
		ws.send_text(("JOIN #"+auth.twitchUser.login))
	else:
		ws.send_text("NICK justinfan12345")
		ws.send_text("PASS kappa")
		ws.send_text("JOIN #"+annonimousChannel)
	
func _on_data(msg):
	
	if(msg.find("PING") == 0):
		ws.send_text("PONG")
	
	var data = {}
	var dataPairs = msg.split(";");
	for pair in dataPairs:
		var d = pair.split("=");
		if d.size() == 2:
			data[d[0]]=d[1]
	
	
	var regex = RegEx.new()
	regex.compile("(?:(([a-zA-Z0-9_]*?)!([a-zA-Z0-9_]*?)@[a-zA-Z0-9_]*?.tmi.twitch.tv)|tmi.twitch.tv)\\s([A-Z]*?)?\\s#([^\\s]*)\\s{0,}:?(.*?)?$")
	var result = regex.search(msg)
	if result:
		data["username"] = result.get_string(2)
		data["cmd"] = result.get_string(4)
		data["channel"] = result.get_string(5)
		data["msg"] = result.get_string(6).strip_edges(false,true);
	
	emit_signal("new_message",data)
	#Regex regex = new Regex(@"(.*?):(?:(([a-zA-Z0-9_]*?)!([a-zA-Z0-9_]*?)@[a-zA-Z0-9_]*?.tmi.twitch.tv)|tmi.twitch.tv)\s([A-Z]*?)?\s#([^\s]*)\s{0,}:?(.*?)?$", RegexOptions.IgnoreCase);
	
func _closed(was_clean = false):
	print("Closed, clean: ", was_clean)
	_ws_connect()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if !is_connected:
			print(state == WebSocketPeer.STATE_OPEN)
			is_connected = true
			_connected()
		while ws.get_available_packet_count():
			_on_data( ws.get_packet().get_string_from_utf8() )
	elif state == WebSocketPeer.STATE_CLOSING:
		# Keep polling to achieve proper close.
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		is_connected = false
		var code = ws.get_close_code()
		var reason = ws.get_close_reason()
		print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
		set_process(false) # Stop processing.
		
func _requestCredentials():
	if(temp_id && !auth):
		#var httr = _newTemporalHttpRequest()
		$HTTPRequest.connect("request_completed", _processCredentials)
		$HTTPRequest.request("https://oauth-dev.seyacat.com/twitch/tempid?temp_id="+temp_id)
		
func _processCredentials(_result, _response_code, _headers, body):
	var json = JSON.parse_string(body.get_string_from_utf8())
	if(json):
		auth = json
	_save_session()
	_ws_connect()
	
#TODO: ADD TIMER RETRIEVE ACCESS TOKEN
func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_requestCredentials()
	
			
func _delete_session():
	if FileAccess.file_exists("user://session.dat"):
		DirAccess.remove_absolute("user://session.dat")
	
func _save_session():
	var file = FileAccess.open("user://session.dat", FileAccess.WRITE)
	if(auth):
		file.store_line(JSON.stringify(auth))
	
func _load_session():
	if FileAccess.file_exists("user://session.dat"):
		var file = FileAccess.open("user://session.dat", FileAccess.READ)
		var content = file.get_line()
		var temp_auth = JSON.parse_string(content)
		if(temp_auth):
			auth = temp_auth

func _save_channel():
	print("save channel")
	var file = FileAccess.open("user://channel.dat", FileAccess.WRITE)
	file.store_line(annonimousChannel)

func _load_channel():
	if FileAccess.file_exists("user://channel.dat"):
		
		var file = FileAccess.open("user://channel.dat", FileAccess.READ)
		annonimousChannel = file.get_line()	
		print("load channel")
		print(annonimousChannel)
		channel_loaded.emit(annonimousChannel);
		
func _ban(data,duration,reason="no reason"):
	if !auth || !data.has("room-id") || !data.has("user-id"):
		return
	var headers = ["Content-Type: application/json", 
		'Client-Id: '+client_id, 
		'Authorization: Bearer '+auth.accessToken]
	var json = JSON.stringify({"data": {"user_id":data["user-id"],"duration":duration,"reason":reason}})
	var httr = _newTemporalHttpRequest()
	httr.request(
		"https://api.twitch.tv/helix/moderation/bans?broadcaster_id="+str(data["room-id"])+"&moderator_id="+str(auth.twitchUser.id),
		headers,
		HTTPClient.METHOD_POST, json)
		
func _vip(data):
	if !auth || !data.has("room-id") || !data.has("user-id"):
		return
	var headers = [
		'Client-Id: '+client_id, 
		'Authorization: Bearer '+auth.accessToken]
	var httr = _newTemporalHttpRequest()
	httr.request(
		"https://api.twitch.tv/helix/channels/vips?broadcaster_id="+str(data["room-id"])+"&user_id="+str(data["user-id"]),
		headers,
		HTTPClient.METHOD_POST)
func _unvip(data):
	if !auth || !data.has("room-id") || !data.has("user-id"):
		return
	var headers = [ 
		'Client-Id: '+client_id, 
		'Authorization: Bearer '+auth.accessToken]
	var httr = _newTemporalHttpRequest()
	httr.request(
		"https://api.twitch.tv/helix/channels/vips?broadcaster_id="+str(data["room-id"])+"&user_id="+str(data["user-id"]),
		headers,
		HTTPClient.METHOD_DELETE)

func _newTemporalHttpRequest():
	var httr = HTTPRequest.new();
	httr.connect('request_completed',_delTemporalHttpRequest.bind(httr))
	add_child(httr)
	return httr
	
func _delTemporalHttpRequest(_result, _response_code, _headers, _body, httr):
	httr.queue_free()
	
	


