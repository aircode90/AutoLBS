-- @module cxd_proto
-- @author jwls
-- @license MIT
-- @copyright openLuat
-- @release 2020.11.16
module(..., package.seeall)

glogin=false
track_slot=0
gtr_changed=false
local messageID =0
wifiinfo=nil




local function get_csq_per(csq)
   csq =tonumber(csq)
   local percent=0
   if csq >=1 and csq <=31 then 
       if csq>25 then
          percent = 80 + (csq-25) *4
       elseif csq >19 then
          percent = 60 + (csq-19) *3
       elseif csq >13 then
          percent = 40 + (csq-13) *3
       elseif csq >7  then
          percent = 20 + (csq-7) *3
       end
   end
   if percent >100 then percent =100 end
   return tostring(percent)
end
local function get_msgid()
     messageID = messageID+1
     return tostring(messageID)
end



function UPLD(payload)
    sys.publish("T_SOCKET_SEND_DATA",payload)
end



---------------------------C5,S5
function cxd_comon_ack(strcap,stret)
    local str_msgid = get_msgid()
    local str_imei = misc.getImei()
 
    local tmparry={}
    table.insert(tmparry,str_msgid)
    table.insert(tmparry,str_imei)
    table.insert(tmparry,strcap)
    table.insert(tmparry,stret)
    UPLD("[C5,"..  table.concat(tmparry,",").."]")
end

---------------------------C4/C18,S4
function cxd_upgps_req(strcap)

    local str_msgid = get_msgid()
    local str_imei = misc.getImei()
    local str_msgtyp = "0" -- 0 为正常定位，1 为进入休眠请求，2 为 SOS 告警，3 为震动告警， 4 为摔倒告警，5 为拆卸告警。
    local str_batlvl = battery.getCapacity()
    local str_charge = battery.isChargerIn() and "1" or "0"
    local str_steps  = "0"   -->
    local tm = misc.getClock()
    local str_utc  = string.format("%04d-%02d-%02d %02d:%02d:%02d", tm.year, tm.month, tm.day, tm.hour, tm.min, tm.sec)

    local str_mcc  = sim.getMcc()
    local str_mnc  = sim.getMnc()

    
    local cellinfo = net.getCellList()
    local strcells = ""

    local str_curcell = net.getLac().."#"..net.getCi().."#"..net.getRssi()
    log.info("now using base info----->",str_curcell)
    if cellinfo ~=nil then
        local cnt=0
        for i=1,#cellinfo do
          
           if cellinfo[i].lac ~=0 and cellinfo[i].ci~=0 then
               if strcells ~="" then strcells = strcells.."|"  end
               strcells=strcells.. cellinfo[i].lac.."#".. cellinfo[i].ci.."#"..tostring(cellinfo[i].rssi*2-113)
               cnt=cnt+1
               if cnt>=6 then break end
           end
        end
    end

    local strwifis=""

    if wifiinfo ~=nill then
        local cnt=0
        for k,v in pairs(wifiinfo) do
            cnt=cnt+1
            log.info("testWifi.scanCb",k:upper(),v)
            if strwifis ~="" then strwifis = strwifis.."|"  end
            strwifis=strwifis..string.format("AP%02d",cnt).."#"..k:upper().."#"..v
          
            if cnt>=10 then break end
        end
    end

    local location, str_lng,str_lat,str_speed,str_course,str_altitude,str_wxcnt

    location=gps.getLocation()
    str_lng  = location.lng   
    str_lat  =  location.lat   
    str_speed=  gps.getOrgSpeed()
    str_course= gps.getCourse()
    str_altitude= gps.getAltitude()
    str_wxcnt=  gps.getUsedSateCnt()

    
    local str_gps=""
    local tmpgps={}

    table.insert(tmpgps,str_lng or "")
    table.insert(tmpgps,str_lat or "")
    table.insert(tmpgps,str_speed or "")
    table.insert(tmpgps,str_course or "")
    table.insert(tmpgps,str_altitude or "")
    table.insert(tmpgps,str_wxcnt or "")
    str_gps = table.concat(tmpgps,'|')


    local tmparry={}
    table.insert(tmparry,str_msgid)
    table.insert(tmparry,str_imei)
    table.insert(tmparry,str_msgtyp)
    table.insert(tmparry,str_batlvl)
    table.insert(tmparry,str_charge)
    table.insert(tmparry,str_steps)
    table.insert(tmparry,str_utc)
    table.insert(tmparry,str_mcc)
    table.insert(tmparry,str_mnc)
    table.insert(tmparry,str_gps)
    table.insert(tmparry,strwifis)
    table.insert(tmparry,strcells)
    UPLD(  "["..strcap..","..  table.concat(tmparry,",").."]")
end



---------------------------C22,S22
function cxd_apn_ack()
    local str_msgid = get_msgid()
    local str_imei = misc.getImei()
    local str_simplmn = (sim.getImsi():sub(1,5)) or ""
    local str_oprplmn =sim.getMcc()..sim.getMnc()  
    local str_apn,str_username,str_password =link.getAPN()
 
    local tmparry={}
    table.insert(tmparry,str_msgid)
    table.insert(tmparry,str_imei)
    table.insert(tmparry,str_simplmn)
    table.insert(tmparry,str_oprplmn)
    table.insert(tmparry,str_apn)
    table.insert(tmparry,str_username)
    table.insert(tmparry,str_password)
    UPLD("[C22,"..table.concat(tmparry,",").."]")
end


function cxd_chk_cmd(payload)
    local zkhpos = string.find(payload, "%[")
    local fkhpos = string.find(payload, "%]")
    if zkhpos ~=nil and fkhpos ~=nil and fkhpos > zkhpos then
        return true, zkhpos,fkhpos
    end
    return false,zkhpos,fkhpos
end

function cxd_any_cmd(payload)

    local unprocessed=""
    local result, zkhpos, fkhpos  =cxd_chk_cmd(payload)
    log.info("payload=", payload)

    if result then
        local str_msg = string.sub(payload,1,fkhpos)
        local str_ctx  = string.match(str_msg, "%[(.+)%]")
        unprocessed = string.sub(payload, fkhpos +1,-1)
        if str_ctx ~=nil and str_ctx ~="" then 
            local paralist = string.split(str_ctx,',')
            if paralist ~=nil and #paralist >0 then
                if paralist[1] =="S1" then       --终端登录请求
                    glogin =(paralist[4] == "1") and true or false
                    log.info("S1 login, UTC, ZONE LOGIN ", glogin,paralist[3], paralist[5], paralist[4])
                    if glogin then
                        log.info("===============login succeed================")
                        cxd_heart_req()
                    end
                elseif paralist[1] =="S3" then   --终端心跳包
                    log.info("S3 heart", glogin,paralist[2])
                elseif paralist[1] =="S4" then   --终端定位数据上报
                    log.info("S4 UTC,svlng,svlat,ZONE",  paralist[3],paralist[4],paralist[5], paralist[6])
                elseif paralist[1] =="S5" then   --通用标准应答协议
                    log.info("S5 commonrsp for",paralist[3], paralist[4])
                elseif paralist[1] =="S6" then   --平台设置定位时间间隔
                    log.info("S6 track_slot ,str_ctx", paralist[3], str_ctx)
                    local tmpval = paralist[3]
                    if tmpval ~=nil then 
                        track_slot = tonumber(tmpval)
                        gtr_changed =true
                    end
                    cxd_comon_ack(paralist[1], (tmpval~=nil) and "1" or "0" )
                elseif paralist[1] =="S25" then  --平台设置定位时间间隔 2
                    log.info("S25 cycle_slot ", paralist[3])
                    local tmpval = paralist[3]
                    ---------这个目前有什么作用不清楚
                    cxd_comon_ack(paralist[1], (tmpval~=nil) and "1" or "0" )
                elseif paralist[1] =="S7" then   --平台设置心跳包时间间隔
                    log.info("S25 heart_slot ", paralist[3])
                    local tmpval = paralist[3]
                    if tmpval ~=nil then 
                        nvm.set("heart_slot",tonumber(tmpval))
                    end
                    cxd_comon_ack(paralist[1], (tmpval~=nil) and "1" or "0" )
                elseif paralist[1] =="S8" then   --平台下发定位请求
                    log.info("S8 locate gps ")
                    cxd_comon_ack(paralist[1],"1")
                    log.info("open_gps by locate->",30)
                    sys.publish("APPMSG_OPEN_GPS",30)

                elseif paralist[1] =="S9" then   --平台下发关机命令
                    log.info("S9 poweroff ")
                    cxd_comon_ack(paralist[1],"1")
                    sys.timerStart(function() 
                        rtos.poweroff()
                    end, 1500)

                elseif paralist[1] =="S10" then  --平台下发恢复出厂设置
                    log.info("S10 restore to factory ")
                    cxd_comon_ack(paralist[1],"1")
                    sys.timerStart(function() 
                        nvm.restore()
                        sys.restart("CXD_S10")
                    end, 1500)
                
                elseif paralist[1] =="S11" then  --平台下发服务器修改命令
                    local flag_ok=true
                    local flag_changed=false
                    if paralist[3] ~= nil and #paralist[3] >0 then
                        if nvm.get("serv_ipadd") ~= paralist[3] then
                            nvm.set("serv_ipadd",paralist[3] )
                            flag_changed=true
                        end
                    elseif paralist[4] ~= nil and #paralist[4] >0 then
                        if nvm.get("serv_ipadd") ~= paralist[4] then
                            nvm.set("serv_ipadd",paralist[4] )
                            flag_changed=true
                        end
                    else
                        flag_ok =false
                    end
                    if flag_ok then
                        if paralist[5] ~= nil and #paralist[5] >0 then
                            if nvm.get("serv_port") ~= paralist[5] then
                                nvm.set("serv_port",paralist[5] )
                                flag_changed=true
                            end
                        else
                            flag_ok=false
                        end
                        if flag_ok and flag_changed ==true then
                            ---要重新连新的服务器地址
                            sys.publish("T_SOCKET_SEND_DATA","CLIENT_EXIT")
                        end
                    end
                    log.info("S11 update serv info, flag_ok,flag_changed ",flag_ok,flag_changed)
                    cxd_comon_ack(paralist[1], flag_ok and "1" or "0" )
                elseif paralist[1] =="S14" then  --平台下发重启命令
                    log.info("S14 restart")
                    cxd_comon_ack(paralist[1],"1")
                    sys.timerStart(function() 
                        sys.restart("CXD_S14")
                    end, 1500)
                elseif paralist[1] =="S15" then  --平台下发APN设置指令
                    log.info("S15 set apn info")
                    nvm.set("plmn",paralist[3] or "" )
                    nvm.set("apn",paralist[4]  or "")
                    nvm.set("username",paralist[5] or "")
                    nvm.set("password",paralist[6] or "")
                    cxd_comon_ack(paralist[1],"1")
                elseif paralist[1] =="S17" then  --终端上报进入休眠模式请求
                    log.info("S17 terinal goto sleep")
                    --向平台请求休眠确认
                elseif paralist[1] =="S22" then  --平台下发查询当前 APN 指令
                    log.info("S22 serv query apn")
                    cxd_apn_ack()
                elseif paralist[1] =="S26" then  --平台控制 LED 灯闪烁
                    log.info("S26  led blink ", paralist[3])
                    local tmpval = paralist[3]
                    if tmpval ~=nil then 
                        app_main.led_keepblks = (tonumber(tmpval)/3 ) *2 +1
                        
                        sys.timerLoopStart(app_main.led_blink,1500)
                    end
                end
            end
        end
    else
        if fkhpos ~=nil then
            unprocessed = string.sub(payload, fkhpos +1,-1)
        else
            unprocessed =payload
        end
    end
    return unprocessed
end

---------------------------C1,S1
function cxd_login_req()
    local tm = misc.getClock()
    local str_utc  = string.format("%04d-%02d-%02d %02d:%02d:%02d", tm.year, tm.month, tm.day, tm.hour, tm.min, tm.sec)
    local str_imei = misc.getImei()
    local str_iccid= sim.getIccid()
    local str_imsi = sim.getImsi()
    local str_mcc  = sim.getMcc()
    local str_mnc  = sim.getMnc()
    local str_lac  = net.getLac()
    local str_ci   = net.getCi()
    local str_dbm  = tostring(net.getRssi()*2-113)   
    local str_devtype =_G.PROJECT
    local str_protover ="0"
    local str_msgid = get_msgid()
    local str_custid= "0000"

    local tmparry={}
    table.insert(tmparry,str_msgid)
    table.insert(tmparry,str_imei)
    table.insert(tmparry,str_utc)
    table.insert(tmparry,str_devtype)
    table.insert(tmparry,str_custid)
    table.insert(tmparry,str_protover)
    table.insert(tmparry,str_imsi)
    table.insert(tmparry,str_iccid)
    table.insert(tmparry,str_mcc)
    table.insert(tmparry,str_mnc)
    table.insert(tmparry,str_lac.."#"..str_ci.."#"..str_dbm)
    table.insert(tmparry, get_csq_per (net.getRssi()) )
    UPLD("[C1,"..  table.concat(tmparry,",").."]")
end

---------------------------C3,S3
function cxd_heart_req()
    local str_msgid = get_msgid()
    local str_imei = misc.getImei()
    local str_batlvl = battery.getCapacity()
    local str_charge = battery.isChargerIn() and "1" or "0"
    local str_steps  = gsensor.mir3da_get_step()
    local str_csqlvl = get_csq_per (net.getRssi()) 
    local tmparry={}
    table.insert(tmparry,str_msgid)
    table.insert(tmparry,str_imei)
    table.insert(tmparry,str_batlvl)
    table.insert(tmparry,str_charge)
    table.insert(tmparry,str_steps)
    table.insert(tmparry,str_csqlvl)
    UPLD( "[C3,"..  table.concat(tmparry,",").."]")
end







---------------------------C17,S17
function cxd_sleep_req()
    local str_msgid = get_msgid()
    local str_imei = misc.getImei()
    local tmparry={}
    table.insert(tmparry,str_msgid)
    table.insert(tmparry,str_imei)
    UPLD(  "[C17,"..  table.concat(tmparry,",").."]")
end





