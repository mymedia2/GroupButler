-- utilities.lua
-- Functions shared among plugins.

local misc, roles, users = {}, {}, {}

-- Escape markdown for Telegram. This function makes non-clickable usernames,
-- hashtags, commands, links and emails, if only_markup flag isn't setted.
function string:escape(only_markup)
	if not only_markup then
		-- insert word joiner
		self = self:gsub('([@#/.])(%w)', '%1\xE2\x81\xA0%2')
	end
	return self:gsub('[*_`[]', '\\%0')
end

-- Remove specified formating or all markdown. This function useful for put
-- names into message. It seems not possible send arbitrary text via markdown.
function string:escape_hard(ft)
	if ft == 'bold' then
		return self:gsub('%*', '')
	elseif ft == 'italic' then
		return self:gsub('_', '')
	elseif ft == 'fixed' then
		return self:gsub('`', '')
	elseif ft == 'link' then
		return self:gsub(']', '')
	else
		return self:gsub('[*_`[%]]', '')
	end
end

function roles.is_superadmin(user_id) --if real owner is true, the function will return true only if msg.from.id == config.admin.owner
	for i=1, #config.superadmins do
		if tonumber(user_id) == config.superadmins[i] then
			return true
		end
	end
	return false
end

function roles.bot_is_admin(chat_id)
	local status = api.getChatMember(chat_id, bot.id).result.status
	if not(status == 'administrator') then
		return false
	else
		return true
	end
end

function roles.is_admin(msg)
	local res = api.getChatMember(msg.chat.id, msg.from.id)
	if not res then
		return false, false
	end
	local status = res.result.status
	if status == 'creator' or status == 'administrator' then
		return true, true
	else
		return false, true
	end
end

-- Returns the admin status of the user. The first argument can be the message,
-- then the function checks the rights of the sender in the incoming chat.
function roles.is_admin_cached(chat_id, user_id)
	if type(chat_id) == 'table' then
		local msg = chat_id
		chat_id = msg.chat.id
		user_id = msg.from.id
	end

	local hash = 'cache:chat:'..chat_id..':admins'
	if not db:exists(hash) then
		misc.cache_adminlist(chat_id, res)
	end
	return db:sismember(hash, user_id)
end

function roles.is_admin2(chat_id, user_id)
	local res = api.getChatMember(chat_id, user_id)
	if not res then
		return false, false
	end
	local status = res.result.status
	if status == 'creator' or status == 'administrator' then
		return true, true
	else
		return false, true
	end
end

function roles.is_owner(msg)
	local status = api.getChatMember(msg.chat.id, msg.from.id).result.status
	if status == 'creator' then
		return true
	else
		return false
	end
end

function roles.is_owner_cached(chat_id, user_id)
	if type(chat_id) == 'table' then
		local msg = chat_id
		chat_id = msg.chat.id
		user_id = msg.from.id
	end
	
	local hash = 'cache:chat:'..chat_id..':owner'
	local owner_id, res = nil, true
	repeat
		owner_id = db:get(hash)
		if not owner_id then
			res = misc.cache_adminlist(chat_id)
		end
	until owner_id or not res

	if owner_id then
		if tonumber(owner_id) == tonumber(user_id) then
			return true
		end
	end
	
	return false
end	

function roles.is_owner2(chat_id, user_id)
	local status = api.getChatMember(chat_id, user_id).result.status
	if status == 'creator' then
		return true
	else
		return false
	end
end

function misc.cache_adminlist(chat_id)
	local res, code = api.getChatAdministrators(chat_id)
	if not res then
		return false, code
	end
	local hash = 'cache:chat:'..chat_id..':admins'
	for _, admin in pairs(res.result) do
		if admin.status == 'creator' then
			db:set('cache:chat:'..chat_id..':owner', admin.user.id)
		end
		db:sadd(hash, admin.user.id)
	end
	db:expire(hash, config.bot_settings.cache_time.adminlist)
	
	return true, #res.result or 0
end

function misc.is_blocked_global(id)
	if db:sismember('bot:blocked', id) then
		return true
	else
		return false
	end
end

function string:trim() -- Trims whitespace from a string.
	local s = self:gsub('^%s*(.-)%s*$', '%1')
	return s
end

function vardump(...)
	for _, value in pairs{...} do
		print(serpent.block(value, {comment=false}))
	end
end

function vtext(...)
	local lines = {}
	for _, value in pairs{...} do
		table.insert(lines, serpent.block(value, {comment=false}))
	end
	return table.concat(lines, '\n')
end

function misc.deeplink_constructor(chat_id, what)
	return 'https://telegram.me/'..bot.username..'?start='..chat_id..':'..what
end

function table.clone(t) --doing "table1 = table2" in lua = creates a pointer to table2
  local new_t = {}
  local i, v = next(t, nil)
  while i do
    new_t[i] = v
    i, v = next(t, i)
  end
  return new_t
end

function table.remove_duplicates(t)
	if type(t) ~= 'table' then
		return false, 'Table expected, got '..type(t)
	else
		local kv_table = {}
		for i, element in pairs(t) do
			if not kv_table[element] then
				kv_table[element] = true
			end
		end
		
		local k_table = {}
		for key, boolean in pairs(kv_table) do
			k_table[#k_table + 1] = key
		end
		
		return k_table
	end
end

function misc.get_date(timestamp)
	if not timestamp then
		timestamp = os.time()
	end
	return os.date('%d/%m/%y')
end

-- Resolves username. Returns ID of user if it was early stored in date base.
-- Argument username must begin with symbol @ (commercial 'at')
function misc.resolve_user(username)
	assert(username:byte(1) == string.byte('@'))

	local stored_id = tonumber(db:hget('bot:usernames', username:lower()))
	if not stored_id then return false end
	local user_obj = api.getChat(stored_id)
	if not user_obj then return stored_id end
	if not user_obj.result.username then return false end

	-- User could change his username
	if username ~= '@' .. user_obj.result.username then
		-- Update it
		db:hset('bot:usernames', user_obj.result.username:lower(), user_obj.result.id)
		-- And return false because this user not the same that asked
		return false
	end

	assert(stored_id == user_obj.result.id)
	return user_obj.result.id
end

function misc.get_sm_error_string(code)
	local descriptions = {
		[109] = _("Inline link formatted incorrectly. Check the text between brackets -> \\[]()"),
		[141] = _("Inline link formatted incorrectly. Check the text between brackets -> \\[]()"),
		[142] = _("Inline link formatted incorrectly. Check the text between brackets -> \\[]()"),
		[112] = _("This text breaks the markdown.\n"
					.. "More info about a proper use of markdown "
					.. "[here](https://telegram.me/GroupButler_ch/46)."),
		[118] = _('This message is too long. Max lenght allowed by Telegram: 4000 characters')
	}
	
	return descriptions[code] or _("Unknown markdown error")
end

function misc.write_file(path, text, mode)
	if not mode then
		mode = "w"
	end
	file = io.open(path, mode)
	if not file then
		misc.create_folder('logs')
		file = io.open(path, mode)
		if not file then
			return false
		end
	end
	file:write(text)
	file:close()
	return true
end

function misc.get_media_type(msg)
	if msg.photo then
		return 'image'
	elseif msg.video then
		return 'video'
	elseif msg.audio then
		return 'audio'
	elseif msg.voice then
		return 'voice'
	elseif msg.document then
		if msg.document.mime_type == 'video/mp4' then
			return 'gif'
		else
			return 'file'
		end
	elseif msg.sticker then
		return 'sticker'
	elseif msg.contact then
		return 'contact'
	end
	return false
end

function misc.get_media_id(msg)
	if msg.photo then
		return msg.photo[#msg.photo].file_id, 'photo'
	elseif msg.document then
		return msg.document.file_id
	elseif msg.video then
		return msg.video.file_id, 'video'
	elseif msg.audio then
		return msg.audio.file_id
	elseif msg.voice then
		return msg.voice.file_id, 'voice'
	elseif msg.sticker then
		return msg.sticker.file_id
	else
		return false, 'The message has not a media file_id'
	end
end

function misc.migrate_chat_info(old, new, on_request)
	if not old or not new then
		return false
	end
	
	for hash_name, hash_content in pairs(config.chat_settings) do
		local old_t = db:hgetall('chat:'..old..':'..hash_name)
		if next(old_t) then
			for key, val in pairs(old_t) do
				db:hset('chat:'..new..':'..hash_name, key, val)
			end
		end
	end
	
	for _, hash_name in pairs(config.chat_custom_texts) do
		local old_t = db:hgetall('chat:'..old..':'..hash_name)
		if next(old_t) then
			for key, val in pairs(old_t) do
				db:hset('chat:'..new..':'..hash_name, key, val)
			end
		end
	end
	
	if on_request then
		api.sendReply(msg, 'Should be done')
	end
end

-- Perform substitution of placeholders in the text according given the
-- message. If placeholders to replacing are specified, this function processes
-- only them, otherwise it processes all available placeholders.
function string:replaceholders(msg, ...)
	if msg.new_chat_member then
		msg.from = msg.new_chat_member
	elseif msg.left_chat_member then
		msg.from = msg.left_chat_member
	end

	local replace_map = {
		name = msg.from.first_name:escape(),
		surname = msg.from.last_name and msg.from.last_name:escape() or '',
		username = msg.from.username and '@'..msg.from.username:escape() or '-',
		id = msg.from.id,
		title = msg.chat.title:escape(),
		rules = misc.deeplink_constructor(msg.chat.id, 'rules')
	}

	local substitutions = next{...} and {} or replace_map
	for _, placeholder in pairs{...} do
		substitutions[placeholder] = replace_map[placeholder]
	end

	return self:gsub('$(%w+)', substitutions)
end

function misc.to_supergroup(msg)
	local old = msg.chat.id
	local new = msg.migrate_to_chat_id
	local done = misc.migrate_chat_info(old, new, false)
	if done then
		misc.remGroup(old, true, 'to supergroup')
		api.sendMessage(new, _("(_service notification: migration of the group executed_)"), true)
	end
end

function misc.log_error(method, code, extras, description)
	if not method or not code then return end
	
	local ignored_errors = {403, 429, 110, 111, 116, 131}
	
	for _, ignored_code in pairs(ignored_errors) do
		if tonumber(code) == tonumber(ignored_code) then return end
	end
	
	local text = 'Type: #badrequest\nMethod: #'..method..'\nCode: #n'..code
	
	if description then
		text = text..'\nDesc: '..description
	end
	
	if extras then
		if next(extras) then
			for i, extra in pairs(extras) do
				text = text..'\n#more'..i..': '..extra
			end
		else
			text = text..'\n#more: empty'
		end
	else
		text = text..'\n#more: nil'
	end
	
	api.sendLog(text)
end

-- Return user mention for output a text
function misc.getname_final(user)
	return misc.getname_link(user.first_name, user.username) or user.first_name:escape()
end

-- Return link to user profile or false, if he doesn't have login
function misc.getname_link(name, username)
	if not name or not username then return false end
	username = username:gsub('@', '')
	return '['..name:escape_hard('link')..'](https://telegram.me/'..username..')'
end

function misc.bash(str)
	local cmd = io.popen(str)
    local result = cmd:read('*all')
    cmd:close()
    return result
end

function misc.download_to_file(url, file_path)--https://github.com/yagop/telegram-bot/blob/master/bot/utils.lua
  --print("url to download: "..url)

  local respbody = {}
  local options = {
    url = url,
    sink = ltn12.sink.table(respbody),
    redirect = true
  }
  -- nil, code, headers, status
  local response = nil
    options.redirect = false
    response = {HTTPS.request(options)}
  local code = response[2]
  local headers = response[3]
  local status = response[4]
  if code ~= 200 then return false, code end

  print("Saved to: "..file_path)

  file = io.open(file_path, "w+")
  file:write(table.concat(respbody))
  file:close()
  return file_path, code
end

function misc.telegram_file_link(res)
	--res = table returned by getFile()
	return "https://api.telegram.org/file/bot"..config.bot_api_key.."/"..res.result.file_path
end

function misc.is_silentmode_on(chat_id)
	local hash = 'chat:'..chat_id..':settings'
	local res = db:hget(hash, 'Silent')
	if res and res == 'on' then
		return true
	else
		return false
	end
end

function misc.getRules(chat_id)
	local hash = 'chat:'..chat_id..':info'
	local rules = db:hget(hash, 'rules')
    if not rules then
        return _("-*empty*-")
    else
       	return rules
    end
end

-- Make mention of the user or the chat room to display. The first parameter is
-- the user object or the chat object, the second specifies how it will use the
-- result: for send in a message body (false) or for answer to a callback query
-- (true). In first case the name will be escaped, otherwise the function won't
-- escape it.
function users.full_name(chat, without_link)
	if chat.first_name == '' then
		-- if the user deleted his account, API returns an User object with id
		-- and first_name fields
		return _("Deleted account")
	end
	local result = chat.first_name or chat.title
	if chat.last_name then
		result = result .. ' ' .. chat.last_name
	end
	if without_link then
		return result
	end
	if chat.username then
		local name = result:escape_hard('link')
		if name:match('^%s*$') then
			-- this condition will be true, if name contains only right square
			-- brackets and spaces
			return '@' .. chat.username:escape()
		end
		return string.format('[%s](https://telegram.me/%s)', name, chat.username)
	end
	return result:escape()
end

function misc.getAdminlist(chat_id, user_id)
	--- ???
	local list, code = api.getChatAdministrators(chat_id)
	if not list then
		return false, code
	end

	local creator, adminlist = nil, {}
	for i, admin in pairs(list.result) do
		if admin.status == 'administrator' and admin.user.id ~= bot.id then
			table.insert(adminlist, users.full_name(admin.user))
		end
		if admin.status == 'creator' then
			creator = users.full_name(admin.user)
		end
	end

	local lines, count = {}, 1
	if creator then
		table.insert(lines, _("*Creator*:"))
		table.insert(lines, string.format('*1*. %s', creator))
		count = count + 1
	end
	if #adminlist ~= 0 then
		table.insert(lines, _("*Admins*:"))
		for i, admin in pairs(adminlist) do
			table.insert(lines, string.format('*%d*. %s', count, admin))
			count = count + 1
		end
	end

	if not roles.bot_is_admin(chat_id) then
		if roles.is_admin_cached(chat_id, user_id) then
			table.insert(lines, _("*I'm not an admin*. I can't fully perform "
					.. "my functions until group creator hasn't made me admin. "
					.. "See [this post](https://telegram.me/GroupButler_ch/104) "
					.. "for to learn how to make a bot administrator."))
		else
			table.insert(lines, _("*I'm not an admin* 😞"))
		end
	end

	return table.concat(lines, '\n')
end

function misc.getExtraList(chat_id)
	local hash = 'chat:'..chat_id..':extra'
	local commands = db:hkeys(hash)
	if not next(commands) then
		return _("No commands set")
	else
		local lines = {}
		for k, v in pairs(commands) do
			table.insert(lines, (v:escape(true)))
		end
		return _("List of *custom commands*:\n") .. table.concat(lines, '\n')
	end
end

function misc.getSettings(chat_id)
    local hash = 'chat:'..chat_id..':settings'
        
	local lang = db:get('lang:'..chat_id) or 'en' -- group language
    local message = _("Current settings for *the group*:\n\n")
			.. _("*Language*: %s\n"):format(config.available_languages[lang])
        
    --build the message
	local strings = {
		Welcome = _("Welcome message"),
		Goodbye = _("Goodbye message"),
		Extra = _("Extra"),
		Flood = _("Anti-flood"),
		Antibot = _("Ban bots"),
		Silent = _("Silent mode"),
		Rules = _("Rules"),
		Arab = _("Arab"),
		Rtl = _("RTL"),
		Reports = _("Reports"),
		Welbut = _("Welcome button"),
	}
    for key, default in pairs(config.chat_settings['settings']) do
        
        local off_icon, on_icon = '🚫', '✅'
        if misc.is_info_message_key(key) then
        	off_icon, on_icon = '👤', '👥'
        end
        
        local db_val = db:hget(hash, key)
        if not db_val then db_val = default end
        
        if db_val == 'off' then
            message = message .. string.format('%s: %s\n', strings[key], off_icon)
        else
            message = message .. string.format('%s: %s\n', strings[key], on_icon)
        end
    end
    
    --build the char settings lines
    hash = 'chat:'..chat_id..':char'
    off_icon, on_icon = '🚫', '✅'
    for key, default in pairs(config.chat_settings['char']) do
    	db_val = db:hget(hash, key)
        if not db_val then db_val = default end
    	if db_val == 'off' then
            message = message .. string.format('%s: %s\n', strings[key], off_icon)
        else
            message = message .. string.format('%s: %s\n', strings[key], on_icon)
        end
    end
    	
    --build the "welcome" line
    hash = 'chat:'..chat_id..':welcome'
    local type = db:hget(hash, 'type')
    if type == 'media' then
		message = message .. _("*Welcome type*: `GIF / sticker`\n")
	elseif type == 'custom' then
		message = message .. _("*Welcome type*: `custom message`\n")
	elseif type == 'no' then
		message = message .. _("*Welcome type*: `default message`\n")
	end
    
    local warnmax_std = (db:hget('chat:'..chat_id..':warnsettings', 'max')) or config.chat_settings['warnsettings']['max']
    local warnmax_media = (db:hget('chat:'..chat_id..':warnsettings', 'mediamax')) or config.chat_settings['warnsettings']['mediamax']
    
	return message .. _("Warns (`standard`): *%s*\n"):format(warnmax_std)
			.. _("Warns (`media`): *%s*\n\n"):format(warnmax_media)
			.. _("✅ = _enabled / allowed_\n")
			.. _("🚫 = _disabled / not allowed_\n")
			.. _("👥 = _sent in group (always for admins)_\n")
			.. _("👤 = _sent in private_")
end

function misc.changeSettingStatus(chat_id, field)
	local turned_off = {
		reports = _("@admin command disabled"),
		welcome = _("Welcome message won't be displayed from now"),
		goodbye = _("Goodbye message won't be displayed from now"),
		extra = _("#extra commands are now available only for moderator"),
		flood = _("Anti-flood is now off"),
		rules = _("/rules will reply in private (for users)"),
		antibot = _("Bots won't be kicked if added by an user"),
		silent = _("Now the bot will be answering in a group"),
		voteban = _("Now /voteban will be available for admins only"),
		welbut = _("Welcome message without a button for the rules"),
	}
	local turned_on = {
		reports = _("@admin command enabled"),
		welcome = _("Welcome message will be displayed"),
		goodbye = _("Goodbye message will be displayed"),
		extra = _("#extra commands are now available for all"),
		flood = _("Anti-flood is now on"),
		rules = _("/rules will reply in the group (with everyone)"),
		antibot = _("Bots will be kicked if added by an user"),
		silent = _("Now the bot will be answering in PM only"),
		voteban = _("Now /voteban will be available for everybody"),
		welbut = _("The welcome message will have a button for the rules"),
	}

	local hash = 'chat:'..chat_id..':settings'
	local now = db:hget(hash, field)
	if now == 'on' then
		db:hset(hash, field, 'off')
		return turned_off[field:lower()]
	else
		db:hset(hash, field, 'on')
		if field:lower() == 'goodbye' then
			local r = api.getChatMembersCount(chat_id)
			if r and r.result > 50 then
				return _("This setting is enabled, but the goodbye message won't be displayed in large groups, "
					.. "because I can't see service messages about left members"), true
			end
		end
		return turned_on[field:lower()]
	end
end

function misc.changeMediaStatus(chat_id, media, new_status)
	local old_status = db:hget('chat:'..chat_id..':media', media)
	local new_status_icon
	if new_status == 'next' then
		if not old_status then
			new_status = 'ok'
			new_status_icon = '✅'
		elseif old_status == 'ok' then
			new_status = 'notok'
			new_status_icon = '❌'
		elseif old_status == 'notok' then
			new_status = 'ok'
			new_status_icon = '✅'
		end
	end
	db:hset('chat:'..chat_id..':media', media, new_status)
	return _("New status = %s"):format(new_status_icon), true
end

function misc.sendStartMe(chat_id, text)
	local keyboard = {inline_keyboard = {{{text = _("Start me"), url = 'https://telegram.me/'..bot.username}}}}
	api.sendMessage(chat_id, text, true, keyboard)
end

function misc.initGroup(chat_id)
	
	for set, setting in pairs(config.chat_settings) do
		local hash = 'chat:'..chat_id..':'..set
		for field, value in pairs(setting) do
			db:hset(hash, field, value)
		end
	end
	
	misc.cache_adminlist(chat_id, api.getChatAdministrators(chat_id)) --init admin cache
	
	--save group id
	db:sadd('bot:groupsid', chat_id)
	--remove the group id from the list of dead groups
	db:srem('bot:groupsid:removed', chat_id)
end

function misc.remGroup(chat_id, full, call)
	--remove group id
	db:srem('bot:groupsid', chat_id)
	--add to the removed groups list
	db:sadd('bot:groupsid:removed', chat_id)
	
	for set,field in pairs(config.chat_settings) do
		db:del('chat:'..chat_id..':'..set)
	end
	
	db:del('cache:chat:'..chat_id..':admins') --delete the cache
	db:del('cache:chat:'..chat_id..':owner')
	db:hdel('bot:logchats', chat_id) --delete the associated log chat
	db:del('chat:'..chat_id..':pin') --delete the msg id of the (maybe) pinned message
	
	if full then
		for i, set in pairs(config.chat_custom_texts) do
			db:del('chat:'..chat_id..':'..set)
		end
		db:del('lang:'..chat_id)
	end
	
	--[[local msg_text = '#removed '..chat_id
	if full then
		msg_text = msg_text..'\nfull: true'
	else
		msg_text = msg_text..'\nfull: false'
	end
	if call then msg_text = msg_text..'\ncall: '..call end
	api.sendAdmin(msg_text)]]
end

function misc.getnames_complete(msg, blocks)
	local admin, kicked
	
	if msg.from.username then
		admin = misc.getname_link(msg.from.first_name, msg.from.username)
	else
		admin = '`'..msg.from.first_name:escape_hard('fixed')..'`'
	end
	
	if msg.reply then
		if msg.reply.from.username then
			kicked = misc.getname_link(msg.reply.from.first_name, msg.reply.from.username)
		else
			kicked = '`'..msg.reply.from.first_name:escape_hard('fixed')..'`'
		end
	elseif msg.text:match(config.cmd..'%w%w%w%w?%w?%s(@[%w_]+)%s?') then
		local username = msg.text:match('%s(@[%w_]+)')
		kicked = username:escape(true)
	elseif msg.mentions then
		for _, entity in pairs(msg.entities) do
			if entity.user then
				kicked = '`'..entity.user.first_name:escape_hard('fixed')..'`'
			end
		end
	elseif msg.text:match(config.cmd..'%w%w%w%w?%w?%s(%d+)') then
		local id = msg.text:match(config.cmd..'%w%w%w%w?%w?%s(%d+)')
		kicked = '`'..id..'`'
	end
	
	return admin, kicked
end

function misc.get_user_id(msg, blocks)
	--if no user id: returns false and the msg id of the translation for the problem
	if not msg.reply and not blocks[2] then
		return false, "Reply to someone"
	else
		if msg.reply then
			return msg.reply.from.id
		elseif msg.text:match(config.cmd..'%w%w%w%w?%w?%w?%s(@[%w_]+)%s?') then
			local username = msg.text:match('%s(@[%w_]+)')
			local id = misc.resolve_user(username)
			if not id then
				return false, _("I've never seen this user before.\n"
					.. "If you want to teach me who is he, forward me a message from him")
			else
				return id
			end
		elseif msg.mentions then
			return next(msg.mentions)
		elseif msg.text:match(config.cmd..'%w%w%w%w?%w?%w?%s(%d+)') then
			local id = msg.text:match(config.cmd..'%w%w%w%w?%w?%w?%s(%d+)')
			return id
		else
			return false, _("I've never seen this user before.\n"
					.. "If you want to teach me who is he, forward me a message from him")
		end
	end
end

function misc.logEvent(event, msg, blocks, extra)
	local log_id = db:hget('bot:chatlogs', msg.chat.id)
	
	if not log_id then return end
	--if not is_loggable(msg.chat.id, event) then return end
	
	local text
	if event == 'ban' then
		local admin, banned = misc.getnames_complete(msg, blocks)
		local admin_id, banned_id = msg.from.id, misc.get_user_id(msg, blocks)
		if admin and banned and admin_id and banned_id then
			text = '#BAN\n*Admin*: '..admin..'  #'..admin_id..'\n*User*: '..banned..'  #'..banned_id
			if extra.motivation then
				text = text..'\n\n> _'..extra.motivation:escape_hard('italic')..'_'
			end
		end
	end
	if event == 'kick' then
		local admin, kicked = misc.getnames_complete(msg, blocks)
		local admin_id, kicked_id = msg.from.id, misc.get_user_id(msg, blocks)
		if admin and kicked and admin_id and kicked_id then
			text = '#KICK\n*Admin*: '..admin..'  #'..admin_id..'\n*User*: '..banned..'  #'..banned_id
			if extra.motivation then
				text = text..'\n\n> _'..extra.motivation:escape_hard('italic')..'_'
			end
		end
	end
	if event == 'join' then
		local member = misc.getname_link(msg.new_chat_member.first_name, msg.new_chat_member.username) or '`'..msg.new_chat_member.first_name:escape_hard('fixed')..'`'
		text = '#NEW_MEMBER\n'..member.. '  #'..msg.new_chat_member.id
	end
	if event == 'warn' then
		local admin, warned = misc.getnames_complete(msg, blocks)
		local admin_id, warned_id = msg.from.id, misc.get_user_id(msg, blocks)
		if admin and warned and admin_id and warned_id then
			text = '#WARN ('..extra.warns..'/'..extra.warnmax..') ('..type..')\n*Admin*: '..admin..'  #'..admin_id..']\n*User*: '..banned..'  #'..banned_id..']'
			if extra.motivation then
				text = text..'\n\n> _'..extra.motivation:escape_hard('italic')..'_'
			end
		end
	end
	if event == 'mediawarn' then
		local name = misc.getname_link(msg.from.first_name, msg.from.username) or '`'..msg.from.first_name:escape_hard('fixed')..'`'
		text = '#MEDIAWARN ('..extra.warns..'/'..extra.warnmax..') '..extra.media..'\n'..name..'  #'..msg.from.id
		if extra.hammered then
			text = text..'\n*'..extra.hammered..'*'
		end
	end
	if event == 'flood' then
		local name = misc.getname_link(msg.from.first_name, msg.from.username) or '`'..msg.from.first_name:escape_hard('fixed')..'`'
		text = '#FLOOD\n'..name..'  #'..msg.from.id
		if extra.hammered then
			text = text..'\n*'..extra.hammered..'*'
		end
	end
	
	if text then
		api.sendMessage(log_id, text, true)
	end
end

function misc.getUserStatus(chat_id, user_id)
	local res = api.getChatMember(chat_id, user_id)
	if res then
		return res.result.status
	else
		return false
	end
end

function misc.saveBan(user_id, motivation)
	local hash = 'ban:'..user_id
	return db:hincrby(hash, motivation, 1)
end

function misc.is_info_message_key(key)
    if key == 'Extra' or key == 'Rules' then
        return true
    else
        return false
    end
end

function misc.table2keyboard(t)
	local keyboard = {inline_keyboard = {}}
    for i, line in pairs(t) do
        if type(line) ~= 'table' then return false, 'Wrong structure (each line need to be a table, not a single value)' end
        local new_line ={}
        for k,v in pairs(line) do
            if type(k) ~= 'string' then return false, 'Wrong structure (table of arrays)' end
            local button = {}
            button.text = k
            button.callback_data = v
            table.insert(new_line, button)
        end
        table.insert(keyboard.inline_keyboard, new_line)
    end
    
    return keyboard
end

return misc, roles, users
