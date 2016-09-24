local function do_keybaord_credits()
	local keyboard = {}
    keyboard.inline_keyboard = {
    	{
    		{text = _("Channel"), url = 'https://telegram.me/'..config.channel:gsub('@', '')},
    		{text = _("GitHub"), url = config.source_code},
    		{text = _("Rate me!"), url = 'https://telegram.me/storebot?start='..bot.username},
		}
	}
	return keyboard
end

local function do_keyboard_cache(chat_id)
	local keyboard = {inline_keyboard = {{{text = _("🔄️ Refresh cache"), callback_data = 'cc:rel:'..chat_id}}}}
	return keyboard
end

local function get_time_remaining(seconds)
	local final = ''
	local hours = math.floor(seconds/3600)
	seconds = seconds - (hours*60*60)
	local min = math.floor(seconds/60)
	seconds = seconds - (min*60)
	
	if hours and hours > 0 then
		final = final..hours..'h '
	end
	if min and min > 0 then
		final = final..min..'m '
	end
	if seconds and seconds > 0 then
		final = final..seconds..'s'
	end
	
	return final
end

local function get_user_id(msg, blocks)
	if msg.reply then
		print('reply')
		return msg.reply.from.id
	elseif blocks[2] then
		if blocks[2]:match('@[%w_]+$') then --by username
			local user_id = misc.resolve_user(blocks[2])
			if not user_id then
				print('username (not found)')
				return false
			else
				print('username (found)')
				return user_id
			end
		elseif blocks[2]:match('%d+$') then --by id
			print('id')
			return blocks[2]
		elseif msg.mentions then --by text mention
			print('text mention')
			return next(msg.mentions)
		else
			return false
		end
	end
end

local function get_name_getban(msg, blocks, user_id)
	if blocks[2] then
		return blocks[2]..' ('..user_id..')'
	else
		return msg.reply.from.first_name..' ('..user_id..')'
	end
end

local function get_ban_info(user_id, chat_id)
	local ban_index = {
		kick = _("Kicked: *%d*"),
		ban = _("Banned: *%d*"),
		tempban = _("Temporary banned: *%d*"),
		flood = _("Removed for flood: *%d*"),
		media = _("Removed for forbidden media: *%d*"),
		warn = _("Removed for warns: *%d*"),
		arab = _("Removed for arab chars: *%d*"),
		rtl = _("Removed for RTL char: *%d*"),
	}
	local lines = {}

	local hash = string.format('ban:%d', user_id)
	local ban_info = db:hgetall(hash)
	for t, n in pairs(ban_info) do
		table.insert(lines, ban_index[t]:format(tonumber(n)))
	end
	if not next(lines) then
		table.insert(lines, _("_No bans to display_"))
	end

	local hash = string.format('chat:%d:warns', chat_id)
	local warns = tonumber(db:hget(hash, user_id)) or 0
	table.insert(lines, _("Warns: %d"):format(warns))

	local hash = string.format('chat:%d:mediawarn', chat_id)
	local media_warns = tonumber(db:hget(hash, user_id)) or 0
	table.insert(lines, _("Media warns: %d"):format(media_warns))

	return table.concat(lines, '\n')
end

local function do_keyboard_userinfo(user_id)
	local keyboard = {
		inline_keyboard = {
			{{text = _("Remove warns"), callback_data = 'userbutton:remwarns:'..user_id}},
			{{text = _("🔨 Ban"), callback_data = 'userbutton:banuser:'..user_id}},
		}
	}
	
	return keyboard
end

local function get_userinfo(user_id, chat_id)
	return _("*Ban info* (globals):\n") .. get_ban_info(user_id, chat_id)
end

local action = function(msg, blocks)
    if blocks[1] == 'adminlist' then
    	if msg.chat.type == 'private' then return end
		local text = misc.getAdminlist(msg.chat.id, msg.from.id)
		if misc.is_silentmode_on(msg.chat.id) then
			api.sendMessage(msg.from.id, text, true)
        else
			api.sendMessage(msg.chat.id, text, true)
        end
    end
    if blocks[1] == 'status' then
    	if msg.chat.type == 'private' then return end
    	if roles.is_admin_cached(msg) then
    		if not blocks[2] and not msg.reply then return end
    		local user_id, error_tr_id = misc.get_user_id(msg, blocks)
    		if not user_id then
				api.sendReply(msg, _(error_tr_id), true)
		 	else
		 		local res = api.getChatMember(msg.chat.id, user_id)
		 		if not res then
		 			api.sendReply(msg, _("This user has nothing to do with this chat"))
		 			return
		 		end
		 		local status = res.result.status
				local name = misc.getname_final(res.result.user)
				local texts = {
					kicked = _("%s is banned from this group"),
					left = _("%s left the group or has been kicked and unbanned"),
					administrator = _("%s is an admin"),
					creator = _("%s is the group creator"),
					unknown = _("%s has nothing to do with this chat"),
					member = _("%s is a chat member")
				}
				api.sendReply(msg, texts[status]:format(name), true)
		 	end
	 	end
 	end
 	if blocks[1] == 'id' then
 		if not(msg.chat.type == 'private') and not roles.is_admin_cached(msg) then return end
 		local id
 		if msg.reply then
 			id = msg.reply.from.id
 		else
 			id = msg.chat.id
 		end
 		api.sendReply(msg, '`'..id..'`', true)
 	end
	if blocks[1] == 'user' then
		if msg.chat.type == 'private' or not roles.is_admin_cached(msg) then return end
		
		if not msg.reply and (not blocks[2] or not blocks[2]:match('%d+$') and not msg.mentions) then
			api.sendReply(msg, _("Reply to an user or mention him (works by id too)"))
			return
		end
		
		------------------ get user_id --------------------------
		local user_id = get_user_id(msg, blocks)
		
		if roles.is_superadmin(msg.from.id) and msg.reply and not msg.cb and msg.reply.forward_from then
			user_id = msg.reply.forward_from.id
		end
		
		if not user_id then
			api.sendReply(msg, _("I've never seen this user before.\n"
				.. "If you want to teach me who is he, forward me a message from him"), true)
		 	return
		end
		-----------------------------------------------------------------------------
		
		local keyboard = do_keyboard_userinfo(user_id)
		
		local text = get_userinfo(user_id, msg.chat.id)
		
		api.sendKeyboard(msg.chat.id, text, keyboard, true)
	end
	if blocks[1] == 'banuser' then
		if not roles.is_admin_cached(msg) then
			api.answerCallbackQuery(msg.cb_id, _("You are not an admin"))
    		return
		end
		
		local user_id = msg.target_id
		
		local res, text = api.banUser(msg.chat.id, user_id, msg.normal_group)
		if res then
			misc.saveBan(user_id, 'ban')
			local name = misc.getname_link(msg.from.first_name, msg.from.username) or msg.from.first_name:escape()
			text = _("_Banned!_\n(Admin: %s)"):format(name)
		end
		api.editMessageText(msg.chat.id, msg.message_id, text, false, true)
	end
	if blocks[1] == 'remwarns' then
		if not roles.is_admin_cached(msg) then
			api.answerCallbackQuery(msg.cb_id, _("You are not an admin"))
    		return
		end
		db:hdel('chat:'..msg.chat.id..':warns', msg.target_id)
		db:hdel('chat:'..msg.chat.id..':mediawarn', msg.target_id)
        
        local name = misc.getname_link(msg.from.first_name, msg.from.username) or msg.from.first_name:escape()
		local text = _("The number of warns received by this user has been *reset*\n(Admin: %s)")
        api.editMessageText(msg.chat.id, msg.message_id, text:format(name), false, true)
    end
    if blocks[1] == 'cache' then
    	if msg.chat.type == 'private' or not roles.is_admin_cached(msg) then return end
    	local text
    	local hash = 'cache:chat:'..msg.chat.id..':admins'
    	if db:exists(hash) then
    		local seconds = db:ttl(hash)
    		local cached_admins = db:scard(hash)
    		text = '📌 Status: `CACHED`\n⌛ ️Remaining: `'..get_time_remaining(tonumber(seconds))..'`\n👥 Admins cached: `'..cached_admins..'`'
    	else
    		text = 'Status: NOT CACHED'
    	end
    	local keyboard = do_keyboard_cache(msg.chat.id)
    	api.sendKeyboard(msg.chat.id, text, keyboard, true)
    end
    if blocks[1] == 'msglink' and roles.is_admin_cached(msg) and msg.reply and msg.chat.username then
		api.sendReply(msg, '[msg n° '..msg.reply.message_id..'](https://telegram.me/'..msg.chat.username..'/'..msg.reply.message_id..')', true)
	end
    if blocks[1] == 'cc:rel' and msg.cb then
    	if not roles.is_admin_cached(msg) then
			api.answerCallbackQuery(msg.cb_id, _("You are not an admin"))
			return
		end
		local missing_sec = tonumber(db:ttl('cache:chat:'..msg.target_id..':admins') or 0)
		if (config.bot_settings.cache_time.adminlist - missing_sec) < 3600 then
			api.answerCallbackQuery(msg.cb_id, 'The adminlist has just been updated. This button will be available in an hour after the last update', true)
		else
    		local res = misc.cache_adminlist(msg.target_id)
    		if res then
    			local cached_admins = db:smembers('cache:chat:'..msg.target_id..':admins')
    			local time = get_time_remaining(config.bot_settings.cache_time.adminlist)
    			local text = '📌 Status: `CACHED`\n⌛ ️Remaining: `'..time..'`\n👥 Admins cached: `'..#cached_admins..'`'
    			api.answerCallbackQuery(msg.cb_id, '✅ Updated. Next update in '..time)
    			api.editMessageText(msg.chat.id, msg.message_id, text, do_keyboard_cache(msg.target_id), true)
    			api.sendLog('#recache\nChat: '..msg.target_id..'\nFrom: '..msg.from.id)
    		end
    	end
    end
end

return {
	action = action,
	triggers = {
		config.cmd..'(id)$',
		config.cmd..'(adminlist)$',
		config.cmd..'(status) (.+)$',
		config.cmd..'(status)$',
		config.cmd..'(cache)$',
		config.cmd..'(msglink)$',
		
		config.cmd..'(user)$',
		config.cmd..'(user) (.*)',
		
		'^###cb:userbutton:(banuser):(%d+)$',
		'^###cb:userbutton:(remwarns):(%d+)$',
		'^###cb:(cc:rel):'
	}
}
