--- 模块功能：自定义常用工具类接口
-- @module mutils
-- @author jwls
-- @license MIT
-- @copyright openLuat
-- @release 2020.03.21
module(..., package.seeall)




function byte2bin(n)
    local t = {}
	for i=31,0,-1 do
	   t[#t+1] =  n / 2^i;
	   n = n % 2^i;

	   if i%4 == 0 and i ~= 0 then
	    	t[#t+1] =' ';
	   end 
	end
	return table.concat(t);
end


function string.findsubstr(src, sub,st_pos)
  return string.find(src, sub, st_pos);
end

function string.find_char_pos(src, sub, tms)
	local i=0;
	local ret_val=nil;
	local st_pos =0;
	while( i < tms )
	do
	   ret_val  = string.find(src, sub, st_pos);
	   if ret_val == nil then
	       break;
	   else
	   	   st_pos = ret_val +1;
	   end
	   i = i+1;
	end
	return ret_val;
end

function string.dumpstr(src, str_begin, str_end)
   local ret_val=nil;
   local st_pos =1;
   local pos_begin = string.find(src, str_begin, st_pos);
   if pos_begin ~=nil then
       pos_begin =  pos_begin + string.len(str_begin);
       st_pos = pos_begin + 1;
	   local pos_end = string.find(src, str_end, st_pos);
	   if pos_end ~=nil then 
	       pos_end = pos_end -1;
	       ret_val = string.sub(src, pos_begin,pos_end);
	   end
   end
   return ret_val;
end

function string.trim(s)
	if s == nil then
		return nil;
	end
	local t={}
	local c=0
	for i=1,#s do
		c = string.byte(s ,i,i)
		if c ~= 0 then
			table.insert(t,string.char(c))
		end 
	end
	local s = table.concat(t)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end


function readfile(filename)
    local filehandle=io.open(filename,"r");
    if filehandle then         
        return filehandle:read("*all");
    else
        print(string.format("readfile:{%s} is not exist!", filename));
	end
	return nil;
end

 

function writefile(filename,filedata,overwrite)
	local filehandle =nil;
	--io.open第一个参数是文件名，后一个是打开模式
	--'r'读模式,
	--'w'写模式，对数据进行覆盖,
	--'a'附加模式,
	--'b'加在模式后面表示以二进制形式打开
	
	if overwrite then
		filehandle= io.open(filename,"w");
	else
	    filehandle= io.open(filename,"a+");
	end
    if filehandle then
        filehandle:write(filedata);
		filehandle:close();
		
		print(string.format("writefile:{%s} len=%d ok!", filename,#filedata));
		return true;
    else
		print(string.format("writefile:{%s} is not exist!", filename));
	end
	return false;
end

function gendefaultpath(filename)

	--return "/lua/"..string.trim(filename);  --AIR724UG 的默认LUA目录
	return string.trim(filename); --AIR724UG 的http 下载目录
end

function checkpathexists(filename,cfunc)

	log.info(cfunc.."-----------checkpath:",filename);

	local try_path = string.trim(filename);
	if io.exists(try_path) then
		log.info(cfunc.."-----------found:",try_path);
		return try_path;
	end	

	local try_path = "/lua/"..string.trim(filename);
	if io.exists(try_path) then
		log.info(cfunc.."-----------found:",try_path);
		return try_path;
	end	

	-- try_path = "/http_down/"..string.trim(filename);
	-- if io.exists(try_path) then
	-- 	log.info(cfunc.."-----------found:",try_path);
	-- 	return try_path;
	-- end

	-- local try_path = "/ldata/"..string.trim(filename);
	-- if io.exists(try_path) then
	-- 	log.info(cfunc.."-----------found:",try_path);
	-- 	return try_path;
	-- end

    return nil;
end

local max_tick=0
function getsystick()
	 local cur_tick =rtos.tick() * 5
	 if max_tick < cur_tick then
	     max_tick =cur_tick
	 end
	return  cur_tick
end

function get_duration_tick(st_tick)
	local cur_tick =  getsystick()
	if cur_tick >= st_tick  then
		return cur_tick - st_tick
	end
	return cur_tick +  (max_tick - st_tick)
end



local function cbFncFile(result,prompt,head,filePath)
    log.info("app_main.cbFncFile",result,prompt,filePath)
    if result and head then
        for k,v in pairs(head) do
            log.info("app_main.cbFncFile",k..": "..v)
        end
    end
    if result and filePath then
        local size = io.fileSize(filePath)
		log.info("+++++++mutils.cbFncFile="..filePath,"fileSize="..size);
		
    end
end


function http_getfile( v_url, v_file)

	local d_file =  checkpathexists(v_file,"http_getfile");
	if d_file ~=nil then 
		os.remove(d_file);
	end
	http.request("GET",v_url,nil,nil,nil,30000,cbFncFile,v_file);
end








