local b = {}

-- load external triggers
--triggers = {} -- { trigger_id = trigger_func(bot, chan, msg) }
--dofile("triggers.lua")

-- extra class vars
b.trusted_users = {"sweetfish"}

-- fancy print to console
function b:log(str)
  print("[" .. os.date() .. "] " .. str)
end

-- send a raw message to the server
function b:send(str, prio)
  --self.client:send(str .. "\n")
  --self:log("[<-] " .. str)
  if prio == nil then
    prio = 1
  end
  table.insert(self.outputqueue, {msg = str, prio = prio})
end

-- called when we have a working connection
function b:on_connected()
  
  -- join all channels we know
  for k,v in pairs(self.config.channels) do
    self:join_channel(v)
  end
end

function b:is_trusted_user(nickname)
  
  for k,v in pairs(self.trusted_users) do
    if v == nickname then
      return true
    end
  end
  
  return false
end

-- parse incomming messages
function b:parse_message(line, err)
  if not err then
    self:log("[->] " .. tostring(line))
  else
    self:log("Recieved an error: " .. tostring(err) .. " (line '" .. tostring(line) .. "')")
  end

  -- first incomming message?
  if not self.firstresponse then
    
    -- make sure we have the latest config
    self:load_config("settings")
    
    self.firstresponse = true
  
    -- send auth response
    self:send("NICK " .. self.config.nickname)
    self:send("USER " .. self.config.nickname .. " lua bot :mr lurch")
    return
  end
  
  -- response id ?
  local i,j,respid,respstr = string.find(line, ":.- (%d+) (.+)")
  if not (i == nil) then
    if respid == "433" then    
      
      -- nick allready in use, try to change to alternative
      local new_nick = ""
      self.altnickid = self.altnickid + 1
      if self.altnickid >= #self.config.altnicks then
        -- run out of alternative nicks, make up a new one!
        new_nick = self.config.nickname .. tostring(math.random(1,9999))
      else
        new_nick = self.config.altnicks[self.altnickid]
      end
    
      self:change_nickname(new_nick)
    
      return
    end
  end
  
  -- we have a working connection!
  if string.sub(line, 1, 1) == ":" then
    if not self.connection_ok then
      self.connection_ok = true
      if not (self.on_connected == nil) then
        self:on_connected()
      end
    end
  end

  -- ping message?
  if string.sub(line, 1, 4) == "PING" then
    self:send("PONG " .. string.sub(line, 6))
    return
  end
  
  -- trigger ?
  -- (triggers are in the form of ':<triggername>')
  local i,j,s,c,k = string.find(line, ":(.-)!.- PRIVMSG (.-) :" .. self.config.triggerprefix .. "(.+)")
  if not (i == nil) then
    
    -- if 'sender' was not a channel, it must be the nickname
    if not (string.sub(c, 1, 1) == "#") then
      c = s
    end
    
    self:trigger(s, c, k)
  end
  
  -- forward to modules
  for k,v in pairs(self.modules) do
    if not (v.parse_message == nil) then
      if type(v.parse_message) == "function" then
        setfenv(v.parse_message, _G)(self, line)
      end
    end
  end
end

-- send a message to a specific channel or nickname
function b:say(chan, msg)
  if not (self.client) then
    return
  end
  
  if not (msg == nil) then
    
    -- broadcast?
    if (chan == nil) then
      chan = ""
      local i = 1
      for k,v in pairs(self.config.channels) do
        if not (string.sub(v, 1, 1) == "#") then
          v = "#" .. v
        end
        
        if #chan == 0 then
          chan = v
        else
          chan = chan .. "," .. v
        end
      end
    end
    
    local pre = ""
    local suf = msg
    while (not (suf == "")) do
      pre = string.sub(suf, 1, self.maxstringlength)
      suf = string.sub(suf, self.maxstringlength)
      --table.insert(self.outputqueue, {msg = pre, prio = prio})
      self:send("PRIVMSG " .. chan .. " :" .. pre)
    end
    
    --self:send("PRIVMSG " .. chan .. " :" .. msg)
  end
end

-- join a channel
function b:join_channel(chan)
  if not (string.sub(chan, 1, 1) == "#") then
    chan = "#" .. chan
  end
  
  self:send("JOIN " .. chan)
end

-- change nickname
function b:change_nickname(new_nick)
  self.config.nickname = new_nick
  self:send("NICK " .. new_nick)
end

-- quit the irc network and exit the script
function b:quit(msg)
  self:say(nil, msg)
  self:send("QUIT :" .. msg)
  os.exit()
end


-- reload core.lua script and rebind methods
-- function also pulls the latest commit from the git repo
function b:reload(chan)
  self:say(chan, "Pulling latest git...")
  os.execute("git pull origin master")
  self:say(chan, "Reloading core.lua...")
  
  local succ, err = pcall(dofile, "core.lua")
  if succ then
    local succ, err = pcall(bind_functions, self)
    
    if succ then
      self:say(chan, "Done.")
    else
      self:say(chan, "Method binding failed:")
      self:say(chan, tostring(err))
    end
  else
    self:say(chan, "Failed, error:")
    self:say(chan, tostring(err))
  end
end

function b:unload_module(chan, modulename)
  if self.config.modules[modulename] == nil then
    self:say(chan, "No module with that name.")
  else
    package.loaded["modules/" .. modulename .. "/" .. modulename] = nil
    self.config.modules[modulename] = nil
    self.modules[modulename] = nil
  end
end

function b:load_module(chan, modulename, moduleurl)
  if not (moduleurl == nil) then

    -- does module exist allready?
    local tryopen, errmsg = io.open("modules/" .. tostring(modulename) .. "/tmpfile", "w")
    if tryopen == nil then
      -- create dir
      os.execute("mkdir modules/" .. tostring(modulename))
    end

    self.config.modules[modulename] = moduleurl
    self.modules[modulename] = {}

  else

    if (self.config.modules[modulename] == nil) then
    --local tryopen, errmsg = io.open("modules/" .. tostring(modulename) .. "/tmpfile", "w")
    --if tryopen == nil then
      -- module does not exist
      self.say(chan,"Module does not exist! Use " .. tostring(self.config.triggerprefix) .. "loadmodule <name> <giturl> instead.")
      return
    end

  end

  -- remove old
  os.execute("rm -rf modules/" .. tostring(modulename))

  -- pull code
  print("tostring(self.config.modules[modulename]): " .. tostring(self.config.modules[modulename]))
  os.execute("git clone " .. tostring(self.config.modules[modulename]) .. " modules/" .. tostring(modulename))

  -- reload into modules
  package.loaded["modules/" .. modulename .. "/" .. modulename] = nil
  self.modules[modulename] = require("modules/" .. modulename .. "/" .. modulename)
  
  self:say(chan, "Module loaded.")

end

-- parse triggers
function b:trigger(user, chan, msg)
  
  
  -----------------------------
  -- core triggers
  
  if (self:is_trusted_user(user)) then
    -- echo trigger?
    if string.sub(msg, 1, 4) == "echo" then
      self:say(chan, string.sub(msg, 6))
    end
  
    -- quit ?
    if string.sub(msg, 1) == "quit" then
      self:quit("good bye!")
    end
  
    -- reload ?
    if string.sub(msg, 1) == "reload" then
      self:save_config("settings")
      self:reload(chan)
    end

    -- saveconf ?
    if string.sub(msg, 1) == "saveconf" then
      self:save_config("settings")
    end

    -- loadconf ?
    if string.sub(msg, 1) == "loadconf" then
      self:load_config("settings")
    end
    
    -- clearqueue ?
    if string.sub(msg, 1) == "clearqueue" then
      self.outputqueue = {}
    end
    
    -- loadmod ?
    if string.sub(msg, 1, 7) == "loadmod" then
      --self:save_config("settings")
      local i,j,m,u = string.find(msg, "loadmod (.-) (.+)")
      if not (i == nil) then
        self:load_module(chan, m, u)
      else
        local i,j,m = string.find(msg, "loadmod (.+)")
        if not (i == nil) then
          self:load_module(chan, m, nil)
        end
      end
    end

    -- unloadmod ?
    if string.sub(msg, 1, 9) == "unloadmod" then
      --self:load_config("settings")
      local i,j,m = string.find(msg, "unloadmod (.+)")
      if not (i == nil) then
        self:unload_module(chan, m)
      end
    end
    
    --[[ rebase ?
    --- Depricated!
    if string.sub(msg, 1, 6) == "rebase" then
      local i,j,gitid = string.find(msg, "rebase (%d+)")
      if not (i == nil) then
        self:save_config("settings")
        self:rebase(chan, gitid)
      end
    end
    ]]
  
    -- join ?
    if string.sub(msg, 1, 4) == "join" then
      local i,j,c = string.find(msg, "join (.+)")
      if not (i == nil) then
        if not (string.sub(c, 1, 1) == "#") then
          c = "#" .. c
        end
        
        self:send("JOIN " .. c)
        
        -- add channel to internal channel list
        for k,v in pairs(self.config.channels) do
          if v == c then
            return
          end
        end
        table.insert(self.config.channels, c)
        
      end
    end
  
    -- nick ?
    if string.sub(msg, 1, 4) == "nick" then
      local i,j,n = string.find(msg, "nick (.+)")
      if not (i == nil) then
        self:change_nickname(n)
      end
    end

    -- exec ?
    if string.sub(msg, 1, 4) == "exec" then
      local i,j,s = string.find(msg, "exec (.+)")
      if not (i == nil) then
        
        local res = assert(loadstring("return (" .. s .. ")"))()
        self:say(chan, res)
        --self:send(tostring(res))
      end
    end
  
  end
  
  
  --------------------------------
  -- normal (public) triggers
  
  for k,v in pairs(self.triggers) do
    if string.sub(msg, 1, #tostring(k)) == tostring(k) then
      setfenv(v, _G)(self, chan, msg)
      break
    end
  end
  
end

-- save bot config to file
function b:load_config(file)
  local filecheck, err = io.open(file .. ".lua")
  
  if not (filecheck == nil) then
    package.loaded[file] = nil
    local config = require(file)
  
    self.config = {}
    for k,v in pairs(config) do
      if not (string.sub(tostring(k), 1, 1) == "_") then
        self.config[k] = v
      end
    end
  end
end

-- load bot config from file
function b:save_config(file)
  local new_data = 'module("' .. tostring(file) .. '")\n'
  
  local function configval_to_string(k,v,indent)
    local ret_str = ""
    if not (type(k) == "number") then
      ret_str = tostring(k) .. " = "
    end
    
    if type(v) == "number" then
      ret_str = ret_str .. tostring(v)
    elseif type(v) == "string" then
      ret_str = ret_str .. '"' .. tostring(v) .. '"'
    elseif type(v) == "table" then
      
      ret_str = ret_str .. "{"
      
      local ret_table = {}
      for i,j in pairs(v) do
        table.insert(ret_table, configval_to_string(i,j,indent + #tostring(k) + 3))
      end
      local sep = ""
      for b=1,indent do
        sep = sep .. " "
      end
      ret_str = ret_str .. table.concat(ret_table, ",\n" .. sep )
      
      ret_str = ret_str .. "\n" .. sep .. "}"
    else
      return "ERROR"
    end
    
    return ret_str
  end
  
  local new_config_table = {}
  if not (self.config == nil) then
    for k,v in pairs(self.config) do
      local new_value = ""
      table.insert(new_config_table, configval_to_string(k,v, #tostring(k) + 3))
    end
  end
  
  new_data = new_data .. table.concat(new_config_table, "\n")
  
  local new_file = io.open(tostring(file) .. ".lua", "w+")
  new_file:write(new_data .. "\n")
  new_file:close()
  
end

-- main bot loop
-- pumps through all messages sent from the server
-- retruns false if an error occurs
function b:pump()
  
  -- handle outgoing messages
  local msgdelta = os.time() - self.lastsentstamp
  if (#self.outputqueue > 0) and (msgdelta >= self.msgwait) then
    
    if (#self.outputqueue > self.queuemax) then
      -- make sure we wait extra long for messages outside the queue
      if (msgdelta >= self.queuewait) then
        -- send first one in queue
        local elem = self.outputqueue[1]
        self.client:send(elem.msg .. "\n")
        self:log("[<-] " .. elem.msg)
        table.remove(self.outputqueue, 1)
      
        self.lastsentstamp = os.time()
      end
    else
      -- send all remaining
      local elem = self.outputqueue[1]
      self.client:send(elem.msg .. "\n")
      self:log("[<-] " .. elem.msg)
      table.remove(self.outputqueue, 1)
      
      self.lastsentstamp = os.time()
    end

    --[[if prio == nil then
      prio = 1
    end
    table.insert(self.outputqueue, {msg = str, prio = prio})]]
  end
  
  -- handle incomming messages
  local line, err = self.client:receive()
  
  if not (err == nil) then
    if not (err == "timeout") then
      self:log("Error from client:recieve(): " .. tostring(err))
      return false
    end
  end
  
  if line then
    -- got message
    self.activitystamp = os.time()
    local succ, err = pcall(self.parse_message, self, line, err)
    if not succ then
      self:log("Error when trying to parse message: " .. tostring(err))
    end
    return true
  end
  
  if (os.time() - self.activitystamp >= self.activitytimeout) then
    self:log("Connection timeout!")
    return false
  end
  
  return true
end


-- bind functions to specific bot instance
function bind_functions( bot )
  for k,v in pairs(b) do
    bot[tostring(k)] = v
  end
  
  -- load triggers
  package.loaded["triggers"] = nil
  bot.triggers = require("triggers")
end
